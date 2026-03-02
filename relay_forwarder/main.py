import functools
import logging
import os
from datetime import timedelta

import functions_framework
import google.cloud.logging
from botocore.config import Config
from cloudevents.http import CloudEvent
from handler import handle_event
from relay import BackgroundRefreshingRelay, GCPSTSClientRefresher, Relay

logger = logging.getLogger("relay")

_bus_parts = os.environ["AWS_EVENT_BUS"].split(":")
_relay: Relay = BackgroundRefreshingRelay(
    bus_name=_bus_parts[-1].split("/", 1)[1],
    detail_type=os.environ["RELAY_DETAIL_TYPE"],
    refresher=GCPSTSClientRefresher(
        region=_bus_parts[3],
        aws_role=os.environ["AWS_ROLE"],
        boto_config=Config(
            max_pool_connections=int(os.environ["CLOUD_RUN_CONCURRENCY"]),
            retries={"max_attempts": 3, "mode": "standard"},
        ),
    ),
    role_auth_backoff=timedelta(seconds=int(os.environ["ROLE_AUTH_BACKOFF_S"])),
    bus_auth_backoff=timedelta(seconds=int(os.environ["BUS_AUTH_BACKOFF_S"])),
)


@functools.cache
def setup() -> None:
    base_log_level = logging.DEBUG if os.environ.get("LOG_DEBUG") else logging.INFO
    client = google.cloud.logging.Client()
    client.setup_logging(log_level=base_log_level)
    logging.getLogger("botocore").setLevel(logging.ERROR)
    logging.getLogger("urllib3").setLevel(logging.ERROR)


@functions_framework.cloud_event
def forward_event(cloud_event: CloudEvent) -> None:
    setup()
    handle_event(_relay, cloud_event)
