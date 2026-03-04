package relay

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"cloud.google.com/go/compute/metadata"
	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/eventbridge"
	"github.com/aws/aws-sdk-go-v2/service/sts"
	smithy "github.com/aws/smithy-go"
)

// CredConfig controls the backoff and timeout behaviour of the credential loop.
type CredConfig struct {
	MinBackoff     time.Duration
	MaxBackoff     time.Duration
	RefreshTimeout time.Duration
}

var DefaultCredConfig = CredConfig{
	MinBackoff:     1 * time.Second,
	MaxBackoff:     60 * time.Second,
	RefreshTimeout: 30 * time.Second,
}

// ClientRefresher returns a fresh EBPutter and the time at which
// the credentials should be refreshed.
type ClientRefresher func(ctx context.Context) (EBPutter, time.Time, error)

// AuthFailure is returned by a ClientRefresher when the credential exchange
// is rejected (bad token, wrong role, etc.).
type AuthFailure struct{ msg string }

func (e *AuthFailure) Error() string { return e.msg }

// NewAuthFailure returns an AuthFailure error with the given message.
func NewAuthFailure(msg string) error { return &AuthFailure{msg: msg} }

// Serve takes a sparse stream of EBPutters and returns a channel that always
// offers the latest one to concurrent callers.
func Serve(ctx context.Context, updates <-chan EBPutter) <-chan EBPutter {
	out := make(chan EBPutter)
	go func() {
		var current EBPutter
		var onward chan<- EBPutter // nil until first update arrives
		for {
			select {
			case <-ctx.Done():
				return
			case onward <- current:
			case current = <-updates:
				onward = out
			}
		}
	}()
	return out
}

// CredLoop starts a background goroutine that yields a fresh EBPutter each
// time credentials are obtained. Auth failures yield nil and back off at
// MaxBackoff; transient errors back off exponentially from MinBackoff to
// MaxBackoff. A successful refresh resets the backoff to MinBackoff.
func CredLoop(ctx context.Context, cfg CredConfig, refresher ClientRefresher) <-chan EBPutter {
	out := make(chan EBPutter)
	go func() {
		backoff := cfg.MinBackoff
		for {
			rctx, cancel := context.WithTimeout(ctx, cfg.RefreshTimeout)
			eb, expiry, err := refresher(rctx)
			cancel()
			if ctx.Err() != nil {
				return
			}

			var af *AuthFailure
			var sleep time.Duration
			if errors.As(err, &af) {
				slog.Info("Auth failure, backing off", "backoff", cfg.MaxBackoff, "err", err)
				select {
				case out <- nil:
				case <-ctx.Done():
					return
				}
				sleep = cfg.MaxBackoff
				backoff = cfg.MinBackoff
			} else if err != nil {
				slog.Error("Credential refresh failed", "backoff", backoff, "err", err)
				sleep = backoff
				backoff = min(backoff*2, cfg.MaxBackoff)
			} else {
				slog.Info("Credentials refreshed", "expiry", expiry)
				select {
				case out <- eb:
				case <-ctx.Done():
					return
				}
				sleep = time.Until(expiry)
				backoff = cfg.MinBackoff
			}
			select {
			case <-time.After(sleep):
			case <-ctx.Done():
				return
			}
		}
	}()
	return out
}

// GCPSTSRefresher returns a ClientRefresher that chains:
//
//	GCP metadata identity token → STS AssumeRoleWithWebIdentity → EventBridge client
func GCPSTSRefresher(region, roleARN string) ClientRefresher {
	// stsAuthCodes are STS errors that mean authentication is not configured
	// correctly: the GCP identity token is structurally invalid or untrusted
	// (InvalidIdentityToken), the identity provider rejects the claim
	// (IDPRejectedClaim), or the role doesn't permit this identity (AccessDenied).
	// All require human intervention, so CredLoop is signalled via AuthFailure
	// to emit nil (dropping events) and back off at MaxBackoff.
	//
	// ExpiredToken is intentionally excluded: it means the GCP metadata server
	// returned a token that was already expired, which is an infrastructure
	// hiccup rather than a misconfiguration. It is treated as a transient error
	// and backs off exponentially so CredLoop retries promptly.
	stsAuthCodes := map[string]bool{
		"InvalidIdentityToken": true,
		"IDPRejectedClaim":     true,
		"AccessDenied":         true,
	}
	return func(ctx context.Context) (EBPutter, time.Time, error) {
		// 1. GCP identity token from the metadata server.
		token, err := metadata.GetWithContext(ctx,
			"instance/service-accounts/default/identity?audience=sts.amazonaws.com&format=full")
		if err != nil {
			return nil, time.Time{}, fmt.Errorf("get GCP identity token: %w", err)
		}
		slog.Debug("Fetched GCP identity token")

		// 2. Assume AWS role via STS with the GCP token as the web identity.
		anonCfg, err := awsconfig.LoadDefaultConfig(ctx,
			awsconfig.WithRegion(region),
			awsconfig.WithCredentialsProvider(aws.AnonymousCredentials{}),
		)
		if err != nil {
			return nil, time.Time{}, fmt.Errorf("build anon AWS config: %w", err)
		}
		resp, err := sts.NewFromConfig(anonCfg).AssumeRoleWithWebIdentity(ctx,
			&sts.AssumeRoleWithWebIdentityInput{
				RoleArn:          aws.String(roleARN),
				RoleSessionName:  aws.String("GCPRelay"),
				WebIdentityToken: aws.String(token),
			})
		if err != nil {
			var ae smithy.APIError
			if errors.As(err, &ae) && stsAuthCodes[ae.ErrorCode()] {
				return nil, time.Time{}, &AuthFailure{
					msg: fmt.Sprintf("STS %s: %s", ae.ErrorCode(), ae.ErrorMessage()),
				}
			}
			return nil, time.Time{}, fmt.Errorf("assume role: %w", err)
		}
		creds := resp.Credentials
		slog.Debug("Assumed AWS role", "expiry", *creds.Expiration)

		// 3. Build an EventBridge client with the temporary credentials.
		awsCfg, err := awsconfig.LoadDefaultConfig(ctx,
			awsconfig.WithRegion(region),
			awsconfig.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(
				*creds.AccessKeyId, *creds.SecretAccessKey, *creds.SessionToken,
			)),
		)
		if err != nil {
			return nil, time.Time{}, fmt.Errorf("build AWS config with temp creds: %w", err)
		}
		return eventbridge.NewFromConfig(awsCfg), creds.Expiration.Add(-5 * time.Minute), nil
	}
}
