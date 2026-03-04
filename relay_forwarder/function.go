package p

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"strings"
	"time"

	"stacklet.io/relay_forwarder/relay"

	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	cloudevents "github.com/cloudevents/sdk-go/v2"
)

var _relay *relay.Relay

func init() {
	if os.Getenv("LOG_DEBUG") != "" {
		slog.SetLogLoggerLevel(slog.LevelDebug)
	}

	busARN := os.Getenv("AWS_EVENT_BUS")
	// ARN format: arn:aws:events:<region>:<account>:event-bus/<name>
	parts := strings.SplitN(busARN, ":", 6)
	region := parts[3]
	busName := strings.SplitN(parts[5], "/", 2)[1]

	ctx := context.Background()
	clients := relay.Serve(ctx, relay.CredLoop(ctx, relay.DefaultCredConfig, relay.GCPSTSRefresher(region, os.Getenv("AWS_ROLE"))))
	_relay = relay.New(clients, 30*time.Second, busName, os.Getenv("RELAY_DETAIL_TYPE"))
	functions.CloudEvent("ForwardEvent", forwardEvent)
}

func forwardEvent(ctx context.Context, e cloudevents.Event) error {
	ev, err := transformEvent(e)
	if err != nil {
		slog.Warn("Dropping unparseable event", "id", e.ID(), "err", err)
		return nil // drop; can't be retried usefully
	}

	err = _relay.Forward(ctx, ev)
	if errors.Is(err, relay.ErrSkip) {
		return nil
	} else if err != nil {
		slog.Error("Error forwarding event", "id", e.ID(), "type", e.Type(), "err", err)
		return err // trigger Cloud Functions retry
	}
	slog.Debug("Forwarded event", "id", e.ID(), "type", e.Type())
	return nil
}

type pubSubData struct {
	Message struct {
		Data []byte `json:"data"`
	} `json:"message"`
}

// transformEvent converts a CloudEvent wrapping a Pub/Sub message into a relay.Event.
func transformEvent(e cloudevents.Event) (relay.Event, error) {
	var msg pubSubData
	if err := e.DataAs(&msg); err != nil {
		return relay.Event{}, fmt.Errorf("parse CloudEvent data: %w", err)
	}
	var innerEvent map[string]any
	if err := json.Unmarshal(msg.Message.Data, &innerEvent); err != nil {
		return relay.Event{}, fmt.Errorf("message data is not JSON: %w", err)
	}
	detail, err := json.Marshal(map[string]any{
		"event":       innerEvent,
		"type":        e.Type(),
		"specversion": e.SpecVersion(),
		"source":      e.Source(),
		"id":          e.ID(),
		"time":        e.Time(),
	})
	if err != nil {
		return relay.Event{}, fmt.Errorf("marshal event payload: %w", err)
	}
	return relay.Event{Detail: detail, Time: e.Time()}, nil
}
