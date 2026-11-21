#!/bin/sh
# Captures the README screenshots from demo data (FREEROOM_DEMO=1): sample findings, a fixed
# disk size, nothing real is scanned or deleted and the user's settings are not touched.
# Output: docs/screenshots/*.png. Needs Screen Recording permission for the terminal.
set -eu
cd "$(dirname "$0")/.."
OUT=docs/screenshots
mkdir -p "$OUT"
FREEROOM_ARCHS="$(uname -m)" scripts/build-app.sh >/dev/null
BIN=build/Freeroom.app/Contents/MacOS/Freeroom

WAS_RUNNING=$(pgrep -x Freeroom >/dev/null && echo yes || echo no)
pkill -x Freeroom 2>/dev/null || true
sleep 1

PID=""
finish() {
  [ -n "$PID" ] && kill "$PID" 2>/dev/null || true
  [ "$WAS_RUNNING" = yes ] && ! pgrep -x Freeroom >/dev/null && open build/Freeroom.app || true
}
trap finish EXIT

shot() { # name appearance route simpleMode(true|false) [onboarded(true|false)]
  # Values are property-list literals: a plain "NO" would arrive as a string, not a Bool.
  FREEROOM_DEMO=1 FREEROOM_DEMO_ROUTE="$3" "$BIN" -onboarded "<${5:-true}/>" -simpleMode "<$4/>" \
    -language en -textSize medium -AppleLocale en_US -AppleInterfaceStyle "$2" >/dev/null 2>&1 &
  PID=$!
  sleep 4
  LAYER=""; [ "$3" = menu ] && LAYER="--any-layer"
  ID=$(swift scripts/window-id.swift Freeroom $LAYER)
  screencapture -l "$ID" -o -x "$OUT/$1.png" || {
    echo "Capture failed: give your terminal app Screen Recording permission (System Settings > Privacy & Security)."
    exit 1
  }
  kill "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  PID=""
  sleep 1
  echo "$OUT/$1.png"
}

shot detailed-light Light findings false
shot detailed-dark Dark findings false
shot simple-light Light findings true
shot simple-dark Dark findings true
shot menu-light Light menu true
shot menu-dark Dark menu true
shot onboarding-light Light findings true false
shot history-light Light history false
shot settings-light Light settings false
