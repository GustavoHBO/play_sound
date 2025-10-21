#!/usr/bin/env bash
# Plays a sound on a specific PulseAudio sink, stops exactly after N seconds,
# then mutes and sends a notification.
# Usage: ./play_once.sh /path/to/sound.wav 5

set -euo pipefail

SINK="alsa_output.pci-0000_03_00.6.analog-stereo"  # seu dispositivo de áudio
FILE="${1:-}"
DURATION="${2:-}"

# --- helpers ---------------------------------------------------------------

die() { echo "Error: $*" >&2; exit 1; }

notify() {
  # Send a desktop notification if available; otherwise just echo.
  if command -v notify-send >/dev/null 2>&1; then
    notify-send --app-name="AudioTimer" --expire-time=3000 \
      "Áudio finalizado" "Parou após ${DURATION}s: $(basename "$FILE")"
  else
    echo "Notification: finished after ${DURATION}s: $FILE"
  fi
}

cleanup() {
  # Always zero volume + mute on exit
  pactl set-sink-volume "$SINK" 0% || true
  pactl set-sink-mute "$SINK" 1 || true
}

# Ensure cleanup on normal exit and on interruption (Ctrl+C, kill, etc.)
trap cleanup EXIT INT TERM

# --- validation ------------------------------------------------------------

[[ -n "$FILE" ]]      || die "Missing audio file argument."
[[ -n "${DURATION}" ]]|| die "Missing duration (seconds)."
[[ -f "$FILE" ]]      || die "Audio file not found: $FILE"
[[ "$DURATION" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "Duration must be a number (seconds)."

command -v paplay >/dev/null 2>&1 || die "paplay not found (install pulseaudio-utils)."
command -v pactl  >/dev/null 2>&1 || die "pactl not found (install pulseaudio)."

# --- do the thing ----------------------------------------------------------

# Unmute + set volume to 100%
pactl set-sink-mute "$SINK" 0
pactl set-sink-volume "$SINK" 100%
sleep 0.1

# Play and stop *exactly* after $DURATION seconds
if command -v timeout >/dev/null 2>&1; then
  # timeout will terminate paplay after the given duration
  timeout "${DURATION}s" paplay "$FILE" --device="$SINK" || true
else
  # Fallback: run in background and kill after sleep
  paplay "$FILE" --device="$SINK" &
  PAPLAY_PID=$!

  # Sleep the requested duration, then try to stop paplay cleanly
  sleep "$DURATION"
  if kill -0 "$PAPLAY_PID" 2>/dev/null; then
    kill "$PAPLAY_PID" 2>/dev/null || true   # SIGTERM first
    # Give it a moment to exit gracefully
    for _ in 1 2 3; do
      sleep 0.1
      kill -0 "$PAPLAY_PID" 2>/dev/null || break
    done
    # If still alive, force kill
    kill -9 "$PAPLAY_PID" 2>/dev/null || true
    wait "$PAPLAY_PID" 2>/dev/null || true
  fi
fi

# Mute + zero volume (handled again by trap, but we do it here immediately too)
pactl set-sink-volume "$SINK" 0%
pactl set-sink-mute "$SINK" 1

# Notify the user that playback finished at the time limit
notify
