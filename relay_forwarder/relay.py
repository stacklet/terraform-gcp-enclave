import json
import logging
import threading
import time
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from typing import Any, Protocol, cast

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError
from google.auth.compute_engine import IDTokenCredentials
from google.auth.transport.requests import Request

logger = logging.getLogger("relay")

# How long before credential expiry to request a refresh.
_REFRESH_BUFFER = timedelta(minutes=5)

# Minimum sleep between refresh attempts, even on success with a near retry_at.
_RETRY_S = 30


class Skip(Exception):
    """Silently ack the Pub/Sub message; an auth gap or backoff is in progress."""


class AuthFailure(Exception):
    """Raised by a ClientRefresher when authentication fails."""


# Returns a fresh EventBridge client and the time at which to refresh again.
ClientRefresher = Callable[[], tuple[Any, datetime]]


class Relay(Protocol):
    def forward(self, payload: dict) -> None:
        """Send one event to EventBridge.

        Raises Skip if credentials are unavailable or a backoff is active.
        Also raises Skip on bus auth errors or rejected entries.
        """
        ...


class BackgroundRefreshingRelay:
    """Relay that keeps an EventBridge client fresh via a background thread.

    The credential strategy is injected as a ClientRefresher. The refresher
    returns a client and a retry_at hint telling the background thread when to
    refresh next — keeping all timing logic out of this class.

    On cold starts all concurrent requests block on the same _ready event,
    so only the background thread fetches credentials regardless of concurrency.
    The 30s timeout is generous enough for GCP metadata + STS under load.
    """

    _AUTH_ERROR_CODES = frozenset(
        {
            "ExpiredTokenException",  # STS temp credentials past their expiry
            "AccessDeniedException",  # role lacks events:PutEvents on this bus
            "UnrecognizedClientException",  # credentials invalid/malformed or not yet propagated
            "InvalidClientTokenId",  # access key ID not known to AWS
        }
    )

    def __init__(
        self,
        *,
        bus_name: str,
        detail_type: str,
        refresher: ClientRefresher,
        role_auth_backoff: timedelta,
        bus_auth_backoff: timedelta,
    ) -> None:
        self._bus_name = bus_name
        self._detail_type = detail_type
        self._refresher = refresher
        self._role_auth_backoff = role_auth_backoff
        self._bus_auth_backoff = bus_auth_backoff

        self._events_client: Any = None
        self._ready = threading.Event()

        self._bus_auth_expiry: datetime | None = None
        self._bus_auth_lock = threading.Lock()

        threading.Thread(target=self._refresh_loop, daemon=True, name="credential-refresh").start()

    def forward(self, payload: dict) -> None:
        if not self._ready.wait(timeout=30.0):
            logger.warning("Credential refresh not ready after 30s; dropping event.")
            raise Skip

        now = datetime.now(UTC)
        if (expiry := self._bus_auth_expiry) and now < expiry:
            logger.info("Auth backoff active until %s; dropping event.", expiry)
            raise Skip

        client = self._events_client  # snapshot before use
        try:
            response = client.put_events(
                Entries=[
                    {
                        "Time": now,
                        "Source": "GCP Relay",
                        "DetailType": self._detail_type,
                        "Detail": json.dumps(payload),
                        "EventBusName": self._bus_name,
                    }
                ]
            )
        except ClientError as e:
            if e.response["Error"]["Code"] in self._AUTH_ERROR_CODES:
                new_expiry = now + self._bus_auth_backoff
                with self._bus_auth_lock:
                    self._bus_auth_expiry = new_expiry
                logger.warning(
                    "EventBridge auth error (%s: %s) — dropping events until %s.",
                    e.operation_name,
                    e.response["Error"]["Code"],
                    new_expiry,
                )
                raise Skip from e
            raise

        if response["FailedEntryCount"]:
            entry = response["Entries"][0]
            logger.error(
                "EventBridge rejected entry: %s: %s — dropping event.",
                entry.get("ErrorCode"),
                entry.get("ErrorMessage"),
            )
            raise Skip

    def _refresh_loop(self) -> None:
        while True:
            try:
                client, retry_at = self._refresher()
                logger.info("Credential refresh successful, retry at %s", retry_at)
                self._events_client = client
                self._ready.set()
                time.sleep(max(_RETRY_S, (retry_at - datetime.now(UTC)).total_seconds()))
            except AuthFailure:
                logger.warning("Role auth failure — backing off for %s.", self._role_auth_backoff)
                time.sleep(self._role_auth_backoff.total_seconds())
            except Exception:
                logger.exception("Credential refresh failed")
                time.sleep(_RETRY_S)


def get_gcp_token() -> str:
    """Fetch a fresh GCP service account identity token from the metadata server."""
    logger.info("Fetching GCP identity token")
    request = Request()
    creds = IDTokenCredentials(
        request=request,
        target_audience="sts.amazonaws.com",
        use_metadata_identity_endpoint=True,
    )
    creds.refresh(request)
    return cast(str, creds.token)


def assume_role(gcp_token: str, *, region: str, aws_role: str) -> dict[str, Any]:
    """Exchange a GCP identity token for temporary AWS credentials via STS."""
    logger.info("Assuming AWS role %s", aws_role)
    sts = boto3.client("sts", region_name=region)
    res = sts.assume_role_with_web_identity(
        RoleArn=aws_role,
        RoleSessionName="StackletGCPRelay",
        WebIdentityToken=gcp_token,
    )
    creds = cast(dict[str, Any], res["Credentials"])
    logger.info("AWS credentials valid until %s", creds["Expiration"])
    return creds


class GCPSTSClientRefresher:
    """ClientRefresher: GCP identity token → STS assume-role → EventBridge client.

    Returns a retry_at hint of (credential expiry - refresh buffer) so the
    caller refreshes before credentials go stale.
    Translates auth ClientErrors into AuthFailure for the caller to back off on.
    """

    _AUTH_ERROR_CODES = frozenset(
        {
            "InvalidIdentityToken",  # bad signature or OIDC provider not registered
            "IDPRejectedClaim",  # claims rejected (bad audience, trust policy mismatch)
            "ExpiredToken",  # GCP JWT past its exp (note: no "Exception" suffix for STS)
            "AccessDenied",  # IAM policy denies the AssumeRole action
        }
    )

    def __init__(self, *, region: str, aws_role: str, boto_config: Config) -> None:
        self._region = region
        self._aws_role = aws_role
        self._boto_config = boto_config

    def __call__(self) -> tuple[Any, datetime]:
        try:
            token = get_gcp_token()
            creds = assume_role(token, region=self._region, aws_role=self._aws_role)
            client = boto3.client(
                "events",
                region_name=self._region,
                aws_access_key_id=creds["AccessKeyId"],
                aws_secret_access_key=creds["SecretAccessKey"],
                aws_session_token=creds["SessionToken"],
                config=self._boto_config,
            )
            return client, creds["Expiration"] - _REFRESH_BUFFER
        except ClientError as e:
            if e.response["Error"]["Code"] in self._AUTH_ERROR_CODES:
                raise AuthFailure(f"{e.operation_name}: {e.response['Error']['Code']}") from e
            raise
