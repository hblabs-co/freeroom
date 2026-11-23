package main

import (
	"github.com/hblabs-co/kit/core/envcfg"
	"github.com/hblabs-co/kit/mail/scaleway"
)

// Mail configuration for the feature-request form. Without a key,
// project or sender the notifier reports Enabled() == false and the
// page shows the mailto: fallback instead of the form.
const (
	EnvScalewaySecretKey = "HB_SCALEWAY_SECRET_KEY"
	EnvScalewayProjectID = "HB_SCALEWAY_PROJECT_ID"
	EnvScalewayRegion    = "HB_SCALEWAY_REGION"
	EnvMailFrom          = "HB_MAIL_FROM"
	EnvMailFromName      = "HB_MAIL_FROM_NAME"
)

// requestRecipient is where feature requests land (also the mailto
// fallback on the page).
const requestRecipient = "freeroom@hblabs.co"

const defaultFromName = "Freeroom website"

// notifierFromEnv builds the Scaleway TEM notifier for feature
// requests. Region empty means the client default (fr-par).
func notifierFromEnv() *scaleway.Notifier {
	client := scaleway.New(scaleway.Options{
		SecretKey: envcfg.String(EnvScalewaySecretKey, ""),
		ProjectID: envcfg.String(EnvScalewayProjectID, ""),
		Region:    envcfg.String(EnvScalewayRegion, ""),
	})
	from := scaleway.Address{
		Email: envcfg.String(EnvMailFrom, ""),
		Name:  envcfg.String(EnvMailFromName, defaultFromName),
	}
	return scaleway.NewNotifier(client, from, scaleway.Address{Email: requestRecipient})
}
