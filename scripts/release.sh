#!/bin/sh
# Builds a signed, notarized and stapled Freeroom DMG, plus the Homebrew cask, into ./build.
# It does NOT publish anything: uploading the GitHub release and the cask are separate steps.
#
# Requirements:
#   - "Developer ID Application" certificate in the keychain
#   - notarization credentials, either
#       a notarytool keychain profile (local Mac):  xcrun notarytool store-credentials freeroom-notary ...
#     or an App Store Connect API key (CI): NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER_ID
#
# Usage: scripts/release.sh
set -eu
cd "$(dirname "$0")/.."

IDENTITY="${FREEROOM_SIGN_IDENTITY:-Developer ID Application: HB Labs SAS (KC5LD84VKS)}"
PROFILE="${FREEROOM_NOTARY_PROFILE:-freeroom-notary}"
VERSION=$(sed -n 's/.*version = "\(.*\)".*/\1/p' Sources/FreeroomCore/Version.swift)
APP=build/Freeroom.app
DMG=build/Freeroom-$VERSION.dmg

echo "==> Building $VERSION"
scripts/build-app.sh >/dev/null

echo "==> Signing with: $IDENTITY"
# Inside-out: the embedded CLI first, then the app. Hardened runtime + secure timestamp are
# required for notarization.
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/Helpers/freeroom"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --deep --verbose=2 "$APP"

echo "==> Creating $DMG"
STAGE=build/dmg-stage
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Freeroom $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

echo "==> Notarizing (this usually takes a few minutes)"
if [ -n "${NOTARY_KEY_PATH:-}" ]; then
  set -- --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID"
else
  set -- --keychain-profile "$PROFILE"
fi
OUT=$(xcrun notarytool submit "$DMG" "$@" --wait 2>&1) || true
echo "$OUT" | grep -E "id:|status:" || true
if ! echo "$OUT" | grep -q "status: Accepted"; then
  ID=$(echo "$OUT" | sed -n 's/^ *id: \(.*\)$/\1/p' | head -1)
  echo "Notarization failed. Log:"
  [ -n "$ID" ] && xcrun notarytool log "$ID" "$@"
  exit 1
fi

echo "==> Stapling"
xcrun stapler staple "$DMG"
xcrun stapler staple "$APP"

echo "==> Gatekeeper check"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
spctl --assess --type execute --verbose=2 "$APP"

SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
cat > build/freeroom.rb <<CASK
cask "freeroom" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/hblabs-co/freeroom/releases/download/v#{version}/Freeroom-#{version}.dmg"
  name "Freeroom"
  desc "Free up disk space on macOS with an agent that understands what it is deleting"
  homepage "https://freeroom.hblabs.co"

  depends_on macos: ">= :sequoia"

  app "Freeroom.app"
  binary "#{appdir}/Freeroom.app/Contents/Helpers/freeroom"

  uninstall quit: "co.hblabs.freeroom"

  # Keep in sync with Sources/FreeroomApp/Uninstaller.swift
  zap trash: [
    "~/Library/Application Support/Freeroom",
    "~/Library/Caches/Freeroom",
    "~/Library/Caches/co.hblabs.freeroom",
    "~/Library/HTTPStorages/co.hblabs.freeroom",
    "~/Library/HTTPStorages/co.hblabs.freeroom.binarycookies",
    "~/Library/Saved Application State/co.hblabs.freeroom.savedState",
    "~/Library/Preferences/co.hblabs.freeroom.plist",
  ]

  caveats <<~EOS
    The Claude Code plugin is managed by Claude Code. To remove it:
      claude plugin uninstall freeroom@freeroom
  EOS
end
CASK

echo
echo "Done: $DMG"
echo "sha256: $SHA"
echo "Cask:   build/freeroom.rb"
