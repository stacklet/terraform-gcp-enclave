import base64
import json
from unittest.mock import MagicMock

import pytest
from cloudevents.http import CloudEvent
from handler import get_detail_from_cloud_event, handle_event
from relay import Skip


def _make_event(payload: dict | bytes, **attrs: str) -> CloudEvent:
    data = base64.b64encode(
        json.dumps(payload).encode() if isinstance(payload, dict) else payload
    ).decode()
    return CloudEvent(
        attributes={
            "type": "google.cloud.pubsub.topic.v1.messagePublished",
            "source": "//pubsub.googleapis.com/projects/test/topics/test",
            "id": "test-id",
            "time": "2024-01-01T00:00:00Z",
            **attrs,
        },
        data={"message": {"data": data}},
    )


# --- get_detail_from_cloud_event ---


def test_returns_expected_structure():
    result = get_detail_from_cloud_event(_make_event({"key": "value"}))
    assert result is not None
    assert result["event"] == {"key": "value"}
    assert result["type"] == "google.cloud.pubsub.topic.v1.messagePublished"
    assert result["id"] == "test-id"


def test_non_json_returns_none():
    assert get_detail_from_cloud_event(_make_event(b"not json")) is None


# --- handle_event ---


def test_handle_event_forwards_payload():
    relay = MagicMock()
    handle_event(relay, _make_event({"key": "value"}))
    relay.forward.assert_called_once()
    (payload,) = relay.forward.call_args[0]
    assert payload["event"] == {"key": "value"}


def test_handle_event_swallows_skip():
    relay = MagicMock()
    relay.forward.side_effect = Skip
    handle_event(relay, _make_event({"key": "value"}))  # must not raise


def test_handle_event_reraises_other_exceptions():
    relay = MagicMock()
    relay.forward.side_effect = RuntimeError("boom")
    with pytest.raises(RuntimeError):
        handle_event(relay, _make_event({"key": "value"}))


def test_handle_event_skips_non_json():
    relay = MagicMock()
    handle_event(relay, _make_event(b"not json"))
    relay.forward.assert_not_called()
