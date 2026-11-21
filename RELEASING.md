# Releasing Freeroom

Releases are built, signed, notarized and published by GitHub Actions
(`.github/workflows/release.yml`). No Mac with the certificate is needed.

```sh
# 1. bump Sources/FreeroomCore/Version.swift, optionally write docs/releases/vX.Y.Z.md
# 2. commit, then:
git tag v0.1.2 && git push origin main v0.1.2
```

The workflow tests, signs with the HB Labs SAS Developer ID, notarizes and staples the DMG,
creates the GitHub release (notes from `docs/releases/vX.Y.Z.md`, or generated) and updates
`Casks/freeroom.rb` in `hblabs-co/homebrew-tap`.
**Run workflow** in the Actions tab does a dry run: same build and notarization, but the DMG is
kept as an artifact and nothing is published.

`scripts/release.sh` still works on a Mac that has the certificate and a `freeroom-notary`
notarytool profile.

## Credentials (organization level, shared by all HB Labs apps)

They live in **hblabs-co › Settings › Secrets and variables › Actions**, not in this repo, so
every HB Labs app can reuse them. Give each secret access to the repositories that need it
("Selected repositories"). On the GitHub Free plan, organization secrets are only available to
**public** repositories; a private app repo would need the Team plan, or its own copies as
repository secrets.

| Name | Kind | What it is |
|---|---|---|
| `APPLE_DEVELOPER_ID_P12` | secret | "Developer ID Application: HB Labs SAS" certificate **with its private key**, exported as .p12, base64 |
| `APPLE_DEVELOPER_ID_P12_PASSWORD` | secret | password chosen when exporting the .p12 |
| `APPLE_NOTARY_KEY_P8` | secret | App Store Connect API key (.p8), base64 |
| `APPLE_NOTARY_KEY_ID` | secret | its Key ID |
| `APPLE_NOTARY_ISSUER_ID` | secret | the Issuer ID shown above the key list |
| `HOMEBREW_TAP_TOKEN` | secret | fine-grained token: only `hblabs-co/homebrew-tap`, Contents read & write |
| `APPLE_SIGN_IDENTITY` | variable (optional) | `Developer ID Application: HB Labs SAS (KC5LD84VKS)` |

### One-time setup

Run these yourself in Terminal; the values go from your Mac straight to GitHub (encrypted) and
are never printed.

```sh
gh auth refresh -h github.com -s admin:org      # allow gh to manage organization secrets
REPOS=freeroom                                  # later: freeroom,otherapp
```

1. **Certificate.** Keychain Access › My Certificates › "Developer ID Application: HB Labs SAS"
   › right-click › Export… › `.p12`, with a strong password. Then:
   ```sh
   base64 -i ~/Desktop/DeveloperID-HBLabs.p12 | gh secret set APPLE_DEVELOPER_ID_P12 --org hblabs-co --repos $REPOS
   gh secret set APPLE_DEVELOPER_ID_P12_PASSWORD --org hblabs-co --repos $REPOS   # prompts for it
   ```
   Keep the .p12 and its password in a password manager, then delete the file from the Desktop.

2. **Notary API key.** App Store Connect › Users and Access › Integrations › App Store Connect API
   › Team Keys › generate a key with the **Developer** role (or reuse one). The .p8 can be
   downloaded only once. Then:
   ```sh
   base64 -i ~/Downloads/AuthKey_XXXXXXXXXX.p8 | gh secret set APPLE_NOTARY_KEY_P8 --org hblabs-co --repos $REPOS
   gh secret set APPLE_NOTARY_KEY_ID --org hblabs-co --repos $REPOS --body XXXXXXXXXX
   gh secret set APPLE_NOTARY_ISSUER_ID --org hblabs-co --repos $REPOS    # prompts for it
   ```
   Store the .p8 in the password manager and remove it from Downloads.

3. **Tap token.** github.com › Settings › Developer settings › Fine-grained tokens › new token:
   resource owner `hblabs-co`, only `homebrew-tap`, permission Contents: read and write.
   ```sh
   gh secret set HOMEBREW_TAP_TOKEN --org hblabs-co --repos $REPOS   # paste the token
   ```

4. **Signing identity** (optional, it is also the default in `scripts/release.sh`):
   ```sh
   gh variable set APPLE_SIGN_IDENTITY --org hblabs-co --visibility all \
     --body "Developer ID Application: HB Labs SAS (KC5LD84VKS)"
   ```

To let a new app use them: `gh secret set NAME --org hblabs-co --repos freeroom,newapp` again
for each secret, or add the repository in each secret's settings on GitHub.

### Safety

- Workflows from forks never receive secrets, and the release job runs only for tags pushed to
  this repository or manual runs by maintainers.
- The certificate goes into a temporary keychain that is deleted at the end of the job.
- If the .p12 leaks: revoke the certificate at developer.apple.com (apps already notarized keep
  working), create a new one and replace the secret. If the .p8 leaks: revoke it in App Store
  Connect and create another.
