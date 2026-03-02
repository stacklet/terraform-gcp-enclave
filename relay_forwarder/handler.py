import base64
import json
import logging
from typing import Any

from cloudevents.http import CloudEvent
from relay import Relay, Skip

logger = logging.getLogger("relay")


def get_detail_from_cloud_event(cloud_event: CloudEvent) -> dict[str, Any] | None:
    data = base64.b64decode(cloud_event.data["message"]["data"])
    try:
        return {
            "event": json.loads(data),
            "type": cloud_event["type"],
            "specversion": cloud_event["specversion"],
            "source": cloud_event["source"],
            "id": cloud_event["id"],
            "time": cloud_event["time"],
        }
    except json.decoder.JSONDecodeError:
        logger.debug("not JSON, data=%s", data)
        return None


def handle_event(relay: Relay, cloud_event: CloudEvent) -> None:
    try:
        if payload := get_detail_from_cloud_event(cloud_event):
            relay.forward(payload)
            logger.info("Forwarded event %s (%s)", cloud_event["id"], cloud_event["type"])
        else:
            logger.error("could not parse cloud event payload: %s", cloud_event)
    except Skip:
        pass
    except Exception as e:
        logger.error("Error forwarding event to AWS EventBridge: %s", e, exc_info=True)
        raise
