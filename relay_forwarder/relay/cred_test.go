package relay_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"stacklet.io/relay_forwarder/relay"
)

var fastCfg = relay.CredConfig{MinBackoff: 10 * time.Millisecond, MaxBackoff: 50 * time.Millisecond, RefreshTimeout: time.Second}

// ---- Serve ------------------------------------------------------------------

func TestServeBlocksUntilFirstUpdate(t *testing.T) {
	updates := make(chan relay.EBPutter)
	out := relay.Serve(t.Context(), updates)
	select {
	case <-out:
		t.Fatal("got value before any update")
	case <-time.After(time.Millisecond):
	}
	eb := &mockEB{}
	updates <- eb
	select {
	case got := <-out:
		if got != eb {
			t.Fatalf("want eb, got %v", got)
		}
	case <-time.After(time.Second):
		t.Fatal("timeout waiting for value after update")
	}
}

func TestServeOffersLatestClient(t *testing.T) {
	updates := make(chan relay.EBPutter)
	out := relay.Serve(t.Context(), updates)
	eb1 := &mockEB{}
	eb2 := &mockEB{}
	updates <- eb1
	if got := <-out; got != eb1 {
		t.Fatalf("want eb1, got %v", got)
	}
	updates <- eb2
	if got := <-out; got != eb2 {
		t.Fatalf("want eb2, got %v", got)
	}
}

// ---- CredLoop ---------------------------------------------------------------

func TestCredLoopAuthFailureEmitsNil(t *testing.T) {
	refresher := func(_ context.Context) (relay.EBPutter, time.Time, error) {
		return nil, time.Time{}, relay.NewAuthFailure("bad token")
	}
	ch := relay.CredLoop(t.Context(), fastCfg, refresher)
	select {
	case got := <-ch:
		if got != nil {
			t.Fatalf("want nil on auth failure, got %v", got)
		}
	case <-time.After(time.Second):
		t.Fatal("timeout waiting for nil emit")
	}
}

func TestCredLoopSuccessEmitsPutter(t *testing.T) {
	eb := &mockEB{}
	refresher := func(_ context.Context) (relay.EBPutter, time.Time, error) {
		return eb, time.Now().Add(time.Hour), nil
	}
	ch := relay.CredLoop(t.Context(), fastCfg, refresher)
	select {
	case got := <-ch:
		if got != eb {
			t.Fatalf("want eb, got %v", got)
		}
	case <-time.After(time.Second):
		t.Fatal("timeout waiting for putter")
	}
}

func TestCredLoopTransientErrorDoesNotEmit(t *testing.T) {
	// Close called on the first invocation, then park until the test ends so
	// the goroutine can't loop back and close an already-closed channel.
	called := make(chan struct{})
	refresher := func(ctx context.Context) (relay.EBPutter, time.Time, error) {
		close(called)
		<-ctx.Done()
		return nil, time.Time{}, ctx.Err()
	}
	ch := relay.CredLoop(t.Context(), fastCfg, refresher)
	select {
	case <-called:
	case <-time.After(time.Second):
		t.Fatal("refresher was never called")
	}
	select {
	case got := <-ch:
		t.Fatalf("unexpected emit on transient error: %v", got)
	default:
	}
}

func TestCredLoopRetryAfterTransientError(t *testing.T) {
	eb := &mockEB{}
	calls := 0
	refresher := func(_ context.Context) (relay.EBPutter, time.Time, error) {
		calls++
		if calls == 1 {
			return nil, time.Time{}, errors.New("transient error")
		}
		return eb, time.Now().Add(time.Hour), nil
	}
	ch := relay.CredLoop(t.Context(), fastCfg, refresher)
	select {
	case got := <-ch:
		if got != eb {
			t.Fatalf("want eb after retry, got %v", got)
		}
	case <-time.After(time.Second):
		t.Fatal("timeout waiting for putter after retry")
	}
}
