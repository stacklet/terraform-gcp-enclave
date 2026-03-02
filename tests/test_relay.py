import json
from datetime import UTC, datetime, timedelta
from unittest.mock import MagicMock, patch

import pytest
from botocore.exceptions import ClientError
from relay import BackgroundRefreshingRelay, Skip

_FAR_FUTURE = datetime(2099, 1, 1, tzinfo=UTC)


def make_relay(**kwargs) -> BackgroundRefreshingRelay:
    """Construct a BackgroundRefreshingRelay with the background thread suppressed."""
    defaults = dict(
        bus_name="test-bus",
        detail_type="GCP Test",
        refresher=MagicMock(return_value=(MagicMock(), _FAR_FUTURE)),
        role_auth_backoff=timedelta(seconds=600),
        bus_auth_backoff=timedelta(seconds=180),
    )
    with patch("threading.Thread"):
        return BackgroundRefreshingRelay(**{**defaults, **kwargs})


def ready_relay(client: MagicMock | None = None) -> BackgroundRefreshingRelay:
    """Construct a relay with credentials already loaded."""
    r = make_relay()
    r._events_client = client or MagicMock()
    r._ready.set()
    return r


def auth_error(code: str) -> ClientError:
    return ClientError({"Error": {"Code": code, "Message": "denied"}}, "PutEvents")


# --- readiness and backoff checks ---


def test_raises_skip_when_not_ready():
    r = make_relay()
    with patch.object(r._ready, "wait", return_value=False):
        with pytest.raises(Skip):
            r.forward({})


def test_raises_skip_when_bus_auth_backoff_active():
    r = ready_relay()
    r._bus_auth_expiry = _FAR_FUTURE
    with pytest.raises(Skip):
        r.forward({})


# --- successful send ---


def test_sends_event_with_correct_fields():
    client = MagicMock()
    client.put_events.return_value = {"FailedEntryCount": 0, "Entries": [{}]}
    ready_relay(client).forward({"k": "v"})
    entry = client.put_events.call_args[1]["Entries"][0]
    assert entry["DetailType"] == "GCP Test"
    assert entry["EventBusName"] == "test-bus"
    assert json.loads(entry["Detail"]) == {"k": "v"}


# --- error handling ---


def test_sets_bus_auth_backoff_and_raises_skip_on_auth_error():
    client = MagicMock()
    client.put_events.side_effect = auth_error("AccessDeniedException")
    r = ready_relay(client)
    with pytest.raises(Skip):
        r.forward({})
    assert r._bus_auth_expiry is not None


def test_raises_skip_on_failed_entry():
    client = MagicMock()
    client.put_events.return_value = {
        "FailedEntryCount": 1,
        "Entries": [{"ErrorCode": "InternalFailure", "ErrorMessage": "oops"}],
    }
    with pytest.raises(Skip):
        ready_relay(client).forward({})


def test_reraises_non_auth_client_error():
    client = MagicMock()
    client.put_events.side_effect = ClientError(
        {"Error": {"Code": "ThrottlingException", "Message": "slow down"}}, "PutEvents"
    )
    with pytest.raises(ClientError):
        ready_relay(client).forward({})
