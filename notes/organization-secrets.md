# Organization secrets and future apps

The release credentials (Developer ID certificate, notarization key, Homebrew tap token) are
**organization secrets of hblabs-co**, not repository secrets, so every HB Labs SAS app can reuse
them. One Developer ID certificate signs all apps of the team; that is how Apple intends it.

## Why this works today

- hblabs-co is on the **GitHub Free** plan.
- On Free, organization secrets are available **only to public repositories**.
- `freeroom` and `homebrew-tap` are public, so the release workflow receives the secrets without
  any extra setup.

## For future apps

| New app repo | What to do |
|---|---|
| **Public** | Add the repo to each secret's access list: `gh secret set NAME --org hblabs-co --repos freeroom,newapp` (or in each secret's settings on GitHub). Copy `.github/workflows/release.yml` and adapt names. |
| **Private** | Organization secrets are **not** passed to it on the Free plan. Either upgrade the organization to **GitHub Team**, or store copies of the secrets as **repository secrets** in that repo (same names, so the workflow is unchanged). |

If more apps follow, move the generic steps (temporary keychain, certificate import, notarization)
into a reusable workflow in a `hblabs-co/.github` repository and call it from each app with
`uses: hblabs-co/.github/.github/workflows/macos-release.yml@main` and `secrets: inherit`.

## Renewals and rotation

- **Apple Developer Program**: yearly. If it lapses, published apps keep working, new ones cannot
  be signed or notarized.
- **Developer ID certificate**: valid 5 years. Signatures stay valid after it expires (they carry
  a secure timestamp). Before it expires, create a new one, export it as .p12 and replace
  `APPLE_DEVELOPER_ID_P12` and `APPLE_DEVELOPER_ID_P12_PASSWORD`.
- **HOMEBREW_TAP_TOKEN**: fine-grained tokens expire (at most one year). Note the date; when it
  expires the release still publishes but the cask update step fails. Create a new token and
  replace the secret.
- **App Store Connect API key**: does not expire; revoke and replace it if it ever leaks.

See [RELEASING.md](../RELEASING.md) for the one-time setup commands.
