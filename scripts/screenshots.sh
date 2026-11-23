#!/bin/sh
# Captures the README screenshots from demo data (FREEROOM_DEMO=1): sample findings, a fixed
# disk size, nothing real is scanned or deleted and the user's settings are not touched.
# Output: docs/screenshots/*.png. Needs Screen Recording permission for the terminal.
set -eu
cd "$(dirname "$0")/.."
OUT=docs/screenshots
ONLY="$*"   # optional: names of the shots to take, e.g. "menu-light menu-dark"
mkdir -p "$OUT"
FREEROOM_ARCHS="$(uname -m)" scripts/build-app.sh >/dev/null
BIN=build/Freeroom.app/Contents/MacOS/Freeroom

WAS_RUNNING=$(pgrep -x Freeroom >/dev/null && echo yes || echo no)
pkill -x Freeroom 2>/dev/null || true
sleep 1

PID=""
HIDPI=""
finish() {
  [ -n "$PID" ] && kill "$PID" 2>/dev/null || true
  [ -n "$HIDPI" ] && kill "$HIDPI" 2>/dev/null || true
  [ "$WAS_RUNNING" = yes ] && ! pgrep -x Freeroom >/dev/null && open build/Freeroom.app || true
}
trap finish EXIT

stop_hidpi() {
  [ -z "$HIDPI" ] && return 0
  kill "$HIDPI" 2>/dev/null || true; wait "$HIDPI" 2>/dev/null || true
  HIDPI=""; sleep 2
}
# The menu (340x440 pt) fits a 2x mode even on a 1x monitor: switch to it for those shots so they
# stay sharp on Retina screens and phones. The windows are too large for that and stay at 1x.
start_hidpi() {
  [ -n "$HIDPI" ] && return 0
  FIFO=$(mktemp -u); mkfifo "$FIFO"
  swift scripts/hidpi.swift >"$FIFO" & HIDPI=$!
  read -r _ <"$FIFO"; rm -f "$FIFO"
  sleep 3
}

want() { [ -z "$ONLY" ] || case " $ONLY " in *" $1 "*) return 0;; *) return 1;; esac; }

shot() { # name appearance route simpleMode(true|false) [onboarded(true|false)]
  want "$1" || return 0
  if [ "$3" = menu ]; then start_hidpi; else stop_hidpi; fi
  # Values are property-list literals: a plain "NO" would arrive as a string, not a Bool.
  APPEARANCE=$(echo "$2" | tr '[:upper:]' '[:lower:]')
  FREEROOM_DEMO=1 FREEROOM_DEMO_ROUTE="$3" FREEROOM_DEMO_APPEARANCE="$APPEARANCE" "$BIN" -onboarded "<${5:-true}/>" -simpleMode "<$4/>" \
    -language en -textSize medium -AppleLocale en_US >/dev/null 2>&1 &
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
stop_hidpi
