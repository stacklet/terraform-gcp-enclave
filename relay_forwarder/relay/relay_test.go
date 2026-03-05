package relay_test

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"testing"
	"time"

	"stacklet.io/relay_forwarder/relay"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/eventbridge"
	ebtypes "github.com/aws/aws-sdk-go-v2/service/eventbridge/types"
	smithy "github.com/aws/smithy-go"
)

// ---- helpers ----------------------------------------------------------------

type mockEB struct {
	resp *eventbridge.PutEventsOutput
	err  error
	got  *eventbridge.PutEventsInput
}

func (m *mockEB) PutEvents(_ context.Context, params *eventbridge.PutEventsInput, _ ...func(*eventbridge.Options)) (*eventbridge.PutEventsOutput, error) {
	m.got = params
	return m.resp, m.err
}

func apiErr(code string) error {
	return &smithy.GenericAPIError{Code: code, Message: "denied"}
}

// makeClientChan returns a channel that continuously offers eb until the test ends.
func makeClientChan(t *testing.T, eb relay.EBPutter) <-chan relay.EBPutter {
	t.Helper()
	ch := make(chan relay.EBPutter)
	go func() {
		for {
			select {
			case ch <- eb:
			case <-t.Context().Done():
				return
			}
		}
	}()
	return ch
}

func baseConfig(t *testing.T, eb relay.EBPutter) relay.Config {
	return relay.Config{Putters: makeClientChan(t, eb), PutterWait: time.Second, BusName: "test-bus", DetailType: "GCP Test"}
}

func makeRelay(t *testing.T, eb relay.EBPutter) *relay.Relay {
	return relay.New(baseConfig(t, eb))
}

func makeEvent(payload map[string]any, t time.Time) relay.Event {
	detail, _ := json.Marshal(payload)
	return relay.Event{Detail: detail, Time: t}
}

// ---- Relay.Forward / discard age --------------------------------------------

func TestRelayDiscardsStaleEvent(t *testing.T) {
	eb := &mockEB{}
	cfg := baseConfig(t, eb)
	cfg.MaxAge = time.Hour
	stale := makeEvent(map[string]any{}, time.Now().Add(-61*time.Minute))
	err := relay.New(cfg).Forward(t.Context(), stale)
	if !errors.Is(err, relay.ErrSkip) {
		t.Fatalf("want ErrSkip for stale event, got %v", err)
	}
	if eb.got != nil {
		t.Error("PutEvents should not have been called for stale event")
	}
}

func TestRelayForwardsFreshEvent(t *testing.T) {
	eb := &mockEB{resp: &eventbridge.PutEventsOutput{Entries: []ebtypes.PutEventsResultEntry{{}}}}
	cfg := baseConfig(t, eb)
	cfg.MaxAge = time.Hour
	fresh := makeEvent(map[string]any{}, time.Now().Add(-59*time.Minute))
	if err := relay.New(cfg).Forward(t.Context(), fresh); err != nil {
		t.Fatalf("unexpected error for fresh event: %v", err)
	}
	if eb.got == nil {
		t.Error("PutEvents should have been called for fresh event")
	}
}

// ---- Relay.Forward behaviour ------------------------------------------------

func TestRelaySendsCorrectFields(t *testing.T) {
	eb := &mockEB{resp: &eventbridge.PutEventsOutput{FailedEntryCount: 0, Entries: []ebtypes.PutEventsResultEntry{{}}}}
	ts := time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)
	ev := makeEvent(map[string]any{"k": "v"}, ts)
	if err := makeRelay(t, eb).Forward(t.Context(), ev); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if eb.got == nil || len(eb.got.Entries) != 1 {
		t.Fatal("PutEvents not called with one entry")
	}
	e := eb.got.Entries[0]
	if aws.ToString(e.EventBusName) != "test-bus" {
		t.Errorf("EventBusName = %q, want %q", aws.ToString(e.EventBusName), "test-bus")
	}
	if aws.ToString(e.DetailType) != "GCP Test" {
		t.Errorf("DetailType = %q, want %q", aws.ToString(e.DetailType), "GCP Test")
	}
	if !e.Time.Equal(ts) {
		t.Errorf("Time = %v, want %v", e.Time, ts)
	}
	var got map[string]any
	if err := json.Unmarshal([]byte(aws.ToString(e.Detail)), &got); err != nil {
		t.Fatalf("Detail is not valid JSON: %v", err)
	}
	if fmt.Sprint(got["k"]) != "v" {
		t.Errorf("Detail k = %v, want v", got["k"])
	}
}

func TestRelayAuthErrorReturnsSkip(t *testing.T) {
	for _, code := range []string{"AccessDeniedException", "UnrecognizedClientException", "InvalidClientTokenId"} {
		t.Run(code, func(t *testing.T) {
			eb := &mockEB{err: apiErr(code)}
			err := makeRelay(t, eb).Forward(t.Context(), relay.Event{})
			if !errors.Is(err, relay.ErrSkip) {
				t.Fatalf("want ErrSkip for %s, got %v", code, err)
			}
		})
	}
}

func TestRelayExpiredTokenIsRetried(t *testing.T) {
	// ExpiredTokenException is transient: CredLoop refreshes credentials before
	// expiry, but clock skew or a slow refresh can leave an expired client in
	// Serve. Returning a retryable error (not ErrSkip) lets Cloud Functions
	// retry; by then CredLoop will have produced a fresh client. Dropping the
	// message would silently lose it.
	eb := &mockEB{err: apiErr("ExpiredTokenException")}
	err := makeRelay(t, eb).Forward(t.Context(), relay.Event{})
	if errors.Is(err, relay.ErrSkip) {
		t.Fatal("ExpiredTokenException should be retryable, not ErrSkip")
	}
	if err == nil {
		t.Fatal("expected an error")
	}
}

func TestRelayPermanentEntryFailureReturnsSkip(t *testing.T) {
	code, msg := "InvalidSignature", "bad sig"
	eb := &mockEB{resp: &eventbridge.PutEventsOutput{
		FailedEntryCount: 1,
		Entries:          []ebtypes.PutEventsResultEntry{{ErrorCode: &code, ErrorMessage: &msg}},
	}}
	err := makeRelay(t, eb).Forward(t.Context(), relay.Event{})
	if !errors.Is(err, relay.ErrSkip) {
		t.Fatalf("want ErrSkip for permanent entry failure, got %v", err)
	}
}

func TestRelayTransientEntryFailureIsRetried(t *testing.T) {
	for _, code := range []string{"InternalFailure", "ThrottlingException"} {
		t.Run(code, func(t *testing.T) {
			msg := "transient"
			eb := &mockEB{resp: &eventbridge.PutEventsOutput{
				FailedEntryCount: 1,
				Entries:          []ebtypes.PutEventsResultEntry{{ErrorCode: &code, ErrorMessage: &msg}},
			}}
			err := makeRelay(t, eb).Forward(t.Context(), relay.Event{})
			if errors.Is(err, relay.ErrSkip) {
				t.Fatalf("want retryable error for %s, got ErrSkip", code)
			}
			if err == nil {
				t.Fatalf("want error for %s, got nil", code)
			}
		})
	}
}

func TestRelayNonAuthErrorIsReturned(t *testing.T) {
	eb := &mockEB{err: apiErr("ThrottlingException")}
	err := makeRelay(t, eb).Forward(t.Context(), relay.Event{})
	if errors.Is(err, relay.ErrSkip) {
		t.Fatal("ThrottlingException should not return ErrSkip")
	}
	if err == nil {
		t.Fatal("expected an error")
	}
}

// ---- Relay.Forward / client availability ------------------------------------

func TestRelayForwardReturnsSkipOnColdStartTimeout(t *testing.T) {
	r := relay.New(relay.Config{Putters: make(chan relay.EBPutter), PutterWait: time.Millisecond, BusName: "b", DetailType: "dt"})
	err := r.Forward(t.Context(), relay.Event{})
	if !errors.Is(err, relay.ErrSkip) {
		t.Fatalf("want ErrSkip on timeout, got %v", err)
	}
}

func TestRelayForwardReturnsSkipWithNilClient(t *testing.T) {
	err := makeRelay(t, nil).Forward(t.Context(), relay.Event{})
	if !errors.Is(err, relay.ErrSkip) {
		t.Fatalf("want ErrSkip, got %v", err)
	}
}

func TestRelayForwardReturnsSkipOnContextCancel(t *testing.T) {
	ctx, cancel := context.WithCancel(t.Context())
	cancel() // already cancelled
	r := relay.New(relay.Config{Putters: make(chan relay.EBPutter), PutterWait: time.Minute, BusName: "b", DetailType: "dt"})
	err := r.Forward(ctx, relay.Event{})
	if !errors.Is(err, relay.ErrSkip) {
		t.Fatalf("want ErrSkip on cancelled context, got %v", err)
	}
}
