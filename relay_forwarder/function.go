package p

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"log/slog"
	"os"
	"strconv"
	"strings"
	"time"

	"stacklet.io/relay_forwarder/relay"

	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	cloudevents "github.com/cloudevents/sdk-go/v2"
)

var _relay *relay.Relay

func init() {
	if os.Getenv("RELAY_DEBUG") != "" {
		slog.SetLogLoggerLevel(slog.LevelDebug)
	}

	discardAgeSecs, err := strconv.Atoi(os.Getenv("RELAY_DISCARD_AGE_S"))
	if err != nil || discardAgeSecs <= 0 {
		log.Fatalf("RELAY_DISCARD_AGE_S must be a positive integer, got %q", os.Getenv("RELAY_DISCARD_AGE_S"))
	}
	discardAge := time.Duration(discardAgeSecs) * time.Second

	busARN := os.Getenv("RELAY_BUS_ARN")
	// ARN format: arn:aws:events:<region>:<account>:event-bus/<name>
	arnParts := strings.SplitN(busARN, ":", 6)
	if len(arnParts) != 6 {
		log.Fatalf("RELAY_BUS_ARN must be a valid ARN, got %q", busARN)
	}
	region := arnParts[3]
	busParts := strings.SplitN(arnParts[5], "/", 2)
	if len(busParts) != 2 {
		log.Fatalf("RELAY_BUS_ARN must be a valid ARN, got %q", busARN)
	}
	busName := busParts[1]

	roleARN := os.Getenv("RELAY_ROLE_ARN")
	if roleARN == "" {
		log.Fatal("RELAY_ROLE_ARN is required")
	}

	detailType := os.Getenv("RELAY_DETAIL_TYPE")
	if detailType == "" {
		log.Fatal("RELAY_DETAIL_TYPE is required")
	}

	ctx := context.Background()
	clients := relay.Serve(ctx, relay.CredLoop(ctx, relay.DefaultCredConfig, relay.GCPSTSRefresher(region, roleARN)))
	_relay = relay.New(relay.Config{
		Putters:    clients,
		PutterWait: 30 * time.Second,
		DiscardAge: discardAge,
		BusName:    busName,
		DetailType: detailType,
	})
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
