package relay

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/eventbridge"
	ebtypes "github.com/aws/aws-sdk-go-v2/service/eventbridge/types"
	smithy "github.com/aws/smithy-go"
)

// ErrSkip signals that a Pub/Sub message should be silently ack'd.
var ErrSkip = errors.New("skip")

// ebAuthCodes are EventBridge errors that indicate the current credentials are
// invalid. These are dropped (ErrSkip) rather than retried because retrying
// with the same dead client is pointless; CredLoop will rotate credentials
// independently and the next invocation will use fresh ones.
var ebAuthCodes = map[string]bool{
	"ExpiredTokenException":       true,
	"AccessDeniedException":       true,
	"UnrecognizedClientException": true,
	"InvalidClientTokenId":        true,
}

// ebEntryRetryCodes are entry-level PutEvents error codes that indicate transient
// failures. Everything else (auth, validation, unknown) is dropped via ErrSkip.
var ebEntryRetryCodes = map[string]bool{
	"InternalFailure":     true,
	"ThrottlingException": true,
}

// Event holds a pre-processed message ready to send to EventBridge.
type Event struct {
	Detail []byte
	Time   time.Time
}

// EBPutter is the subset of *eventbridge.Client used by the relay.
// Defined as an interface so tests can substitute a mock.
type EBPutter interface {
	PutEvents(ctx context.Context, params *eventbridge.PutEventsInput, optFns ...func(*eventbridge.Options)) (*eventbridge.PutEventsOutput, error)
}

// Config holds the configuration for a Relay.
type Config struct {
	Putters    <-chan EBPutter
	PutterWait time.Duration // how long Forward waits for a putter before dropping
	DiscardAge time.Duration // if > 0, events older than this are silently dropped
	BusName    string
	DetailType string
}

// Relay forwards events to AWS EventBridge.
type Relay struct {
	cfg Config
}

// New creates a Relay from cfg.
func New(cfg Config) *Relay {
	return &Relay{cfg: cfg}
}

// Forward sends ev to EventBridge. It returns ErrSkip if the event should be
// silently ack'd (backoff in progress, context cancelled, stale event, permanent EB failure).
func (r *Relay) Forward(ctx context.Context, ev Event) error {
	if r.cfg.DiscardAge > 0 {
		if age := time.Since(ev.Time); age > r.cfg.DiscardAge {
			slog.Info("Dropping stale event", "age", age.Round(time.Second))
			return ErrSkip
		}
	}
	t := time.NewTimer(r.cfg.PutterWait)
	defer t.Stop()
	select {
	case eb := <-r.cfg.Putters:
		if eb != nil {
			return r.send(ctx, eb, ev)
		}
		slog.Debug("Dropping event; credential backoff in progress")
	case <-t.C:
		slog.Warn("Putter not ready; dropping event", "wait", r.cfg.PutterWait)
	case <-ctx.Done():
		slog.Warn("Context done before client ready", "err", ctx.Err())
	}
	return ErrSkip
}

func (r *Relay) send(ctx context.Context, eb EBPutter, ev Event) error {
	resp, err := eb.PutEvents(ctx, &eventbridge.PutEventsInput{
		Entries: []ebtypes.PutEventsRequestEntry{{
			Time:         &ev.Time,
			Source:       aws.String("GCP Relay"),
			DetailType:   aws.String(r.cfg.DetailType),
			Detail:       aws.String(string(ev.Detail)),
			EventBusName: aws.String(r.cfg.BusName),
		}},
	})
	if err != nil {
		var ae smithy.APIError
		if errors.As(err, &ae) && ebAuthCodes[ae.ErrorCode()] {
			slog.Info("EventBridge auth error, dropping", "code", ae.ErrorCode())
			return ErrSkip
		}
		return err
	}
	if resp.FailedEntryCount > 0 {
		if len(resp.Entries) == 0 {
			return fmt.Errorf("EventBridge: FailedEntryCount=%d but Entries is empty", resp.FailedEntryCount)
		}
		entry := resp.Entries[0]
		code := aws.ToString(entry.ErrorCode)
		slog.Warn("EventBridge rejected entry",
			"code", code,
			"message", aws.ToString(entry.ErrorMessage),
			"retryable", ebEntryRetryCodes[code])
		if ebEntryRetryCodes[code] {
			return fmt.Errorf("EventBridge transient entry failure: %s", code)
		}
		return ErrSkip
	}
	return nil
}
