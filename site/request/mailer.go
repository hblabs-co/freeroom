// Package request implements the Freeroom page's feature-request
// form: a POST endpoint guarded by a double-submit CSRF cookie, a
// honeypot and a per-IP rate limit, which forwards each request by
// email to freeroom@hblabs.co through the Scaleway Transactional
// Email API (the shared client in github.com/hblabs-co/kit/mail/scaleway).
//
// Mail config comes from the env keys below
// (HB_SCALEWAY_SECRET_KEY, HB_SCALEWAY_PROJECT_ID, HB_SCALEWAY_REGION,
// HB_MAIL_FROM, HB_MAIL_FROM_NAME). Without a key, project or sender
// the mailer reports Enabled() == false and the page shows a mailto:
// fallback instead of the form.
package request

import (
	"context"
	"errors"
	"fmt"
	"net/http"

	"github.com/hblabs-co/kit/core/envcfg"
	"github.com/hblabs-co/kit/mail/scaleway"
)

// Recipient is where feature requests land.
const Recipient = "freeroom@hblabs.co"

const defaultFromName = "Freeroom website"

// MailConfig is the Scaleway TEM configuration. Region, BaseURL and
// Client may stay empty: the shared client defaults them (fr-par, the
// production API root, a 10-second-timeout HTTP client).
type MailConfig struct {
	SecretKey string
	ProjectID string
	Region    string
	From      string
	FromName  string
	To        string
	BaseURL   string
	Client    *http.Client
}

// Environment keys for the mail configuration.
const (
	EnvScalewaySecretKey = "HB_SCALEWAY_SECRET_KEY"
	EnvScalewayProjectID = "HB_SCALEWAY_PROJECT_ID"
	EnvScalewayRegion    = "HB_SCALEWAY_REGION"
	EnvMailFrom          = "HB_MAIL_FROM"
	EnvMailFromName      = "HB_MAIL_FROM_NAME"
)

// ConfigFromEnv reads the mail env keys.
func ConfigFromEnv() MailConfig {
	return MailConfig{
		SecretKey: envcfg.String(EnvScalewaySecretKey, ""),
		ProjectID: envcfg.String(EnvScalewayProjectID, ""),
		Region:    envcfg.String(EnvScalewayRegion, ""),
		From:      envcfg.String(EnvMailFrom, ""),
		FromName:  envcfg.String(EnvMailFromName, ""),
	}
}

// Mailer sends plain-text mails through Scaleway TEM.
type Mailer struct {
	cfg    MailConfig
	client *scaleway.Client
}

// NewMailer applies defaults to cfg.
func NewMailer(cfg MailConfig) *Mailer {
	if cfg.FromName == "" {
		cfg.FromName = defaultFromName
	}
	if cfg.To == "" {
		cfg.To = Recipient
	}
	return &Mailer{cfg: cfg, client: scaleway.New(scaleway.Options{
		SecretKey:  cfg.SecretKey,
		ProjectID:  cfg.ProjectID,
		Region:     cfg.Region,
		BaseURL:    cfg.BaseURL,
		HTTPClient: cfg.Client,
	})}
}

// Enabled reports whether the mailer has everything it needs to send.
func (m *Mailer) Enabled() bool {
	return m != nil && m.client.Configured() && m.cfg.From != ""
}

// errDisabled is returned by Send when the mailer is not configured.
var errDisabled = errors.New("request: mailer not configured")

// Send delivers one plain-text mail to the configured recipient.
// replyTo may be empty.
func (m *Mailer) Send(ctx context.Context, subject, text, replyTo string) error {
	if !m.Enabled() {
		return errDisabled
	}
	e := scaleway.Email{
		From:    scaleway.Address{Email: m.cfg.From, Name: m.cfg.FromName},
		To:      []scaleway.Address{{Email: m.cfg.To}},
		Subject: subject,
		Text:    text,
	}
	if replyTo != "" {
		e.Headers = []scaleway.Header{scaleway.ReplyTo(replyTo)}
	}
	if _, err := m.client.Send(ctx, e); err != nil {
		return fmt.Errorf("request: %w", err)
	}
	return nil
}
