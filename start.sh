#!/usr/bin/env bash
#
# GDR Live Transcriber — record a session
#
# Records your MICROPHONE and your PC AUDIO (Discord voices, game sounds)
# as two separate tracks. Recording is very light on the CPU, so you can play
# normally. When you stop with Ctrl+C, both tracks are transcribed with
# whisper.cpp and merged into a single transcript.txt, time-ordered, with
# [ME] / [PC] speaker labels.
#
# Files land in ./sessions/<timestamp>/
#
# While recording, a DRAFT transcript scrolls in the terminal ~30 seconds
# behind live (handy to re-read names and events), done with a fast model.
# The accurate transcript is still the one produced at the end.
#
# Options (environment variables):
#   LANG_CODE=it        spoken language (default: it, use 'auto' to detect)
#   MODEL=small         whisper model for the transcription at the end
#   AUTO_TRANSCRIBE=0   record only; transcribe later with ./transcribe.sh
#   LIVE=0              disable the live draft in the terminal
#   LIVE_MODEL=tiny     fast model for the live draft (default: base, else tiny)
#   LIVE_CHUNK=30       seconds of audio per live chunk
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RATE=16000   # whisper wants 16 kHz mono; recording it directly avoids conversions
AUTO_TRANSCRIBE="${AUTO_TRANSCRIBE:-1}"

for cmd in pactl parec ffmpeg; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "ERROR: '$cmd' not found. Run ./install.sh first." >&2; exit 1; }
done

# --- pick the devices --------------------------------------------------------
# Mic = default input, PC audio (Discord/game) = monitor of the default output.
# Set them in Settings -> Sound before starting.
MIC_SRC="$(pactl get-default-source)"
OUT_SINK="$(pactl get-default-sink)"
MON_SRC="$OUT_SINK.monitor"

if [ "$MIC_SRC" = "auto_null" ] || [ "$OUT_SINK" = "auto_null" ]; then
    echo "WARNING: PipeWire reports no real audio device (default is 'auto_null')." >&2
    echo "         Check Settings -> Sound. Recording will likely be silent." >&2
fi
case "$MIC_SRC" in
    *.monitor)
        echo "WARNING: your default input is a monitor, not a microphone." >&2
        echo "         Pick your real mic in Settings -> Sound." >&2 ;;
esac

# --- output location ---------------------------------------------------------
STAMP="$(date +%Y-%m-%d_%H-%M-%S)"
OUT_DIR="$HERE/sessions/$STAMP"
mkdir -p "$OUT_DIR"
MIC_RAW="$OUT_DIR/mic.raw"
PC_RAW="$OUT_DIR/pc.raw"
MIC_WAV="$OUT_DIR/mic.wav"
PC_WAV="$OUT_DIR/pc.wav"

echo "==> Session:      $OUT_DIR"
echo "    Microphone:   $MIC_SRC"
echo "    PC audio:     $MON_SRC"

# --- record ------------------------------------------------------------------
# Raw PCM (no header): safe to cut at any moment, converted to .wav afterwards.
parec -d "$MIC_SRC" --rate="$RATE" --channels=1 --format=s16le > "$MIC_RAW" &
MIC_PID=$!
parec -d "$MON_SRC" --rate="$RATE" --channels=1 --format=s16le > "$PC_RAW" &
PC_PID=$!

# Live draft: a helper process transcribes the tracks in near-real-time with
# a fast model and prints the lines here. If it can't start (no fast model),
# it says why and recording simply continues without it.
LIVE="${LIVE:-1}"
LIVE_PID=""
if [ "$LIVE" = "1" ]; then
    "$HERE/live.sh" "$OUT_DIR" &
    LIVE_PID=$!
    echo "==> Live draft: on screen ~${LIVE_CHUNK:-30}s behind (also saved to live.txt). LIVE=0 disables it."
fi

STOP=""
trap 'STOP=1' INT TERM
trap 'kill "$MIC_PID" "$PC_PID" ${LIVE_PID:+"$LIVE_PID"} 2>/dev/null || true' EXIT

echo
echo "==> RECORDING — play your session. Press Ctrl+C to stop and transcribe."
START_TS="$(date +%s)"
while [ -z "$STOP" ]; do
    sleep 1 || true
    # On Ctrl+C the recorders die together with us — that's a normal stop,
    # so check STOP again before diagnosing a dead recorder.
    [ -n "$STOP" ] && break
    if ! kill -0 "$MIC_PID" 2>/dev/null || ! kill -0 "$PC_PID" 2>/dev/null; then
        echo
        echo "WARNING: a recorder died (device unplugged?). Stopping." >&2
        break
    fi
    ELAPSED=$(( $(date +%s) - START_TS ))
    printf '\r    Recording... %02d:%02d:%02d ' \
        $((ELAPSED/3600)) $((ELAPSED%3600/60)) $((ELAPSED%60))
done
echo
echo "==> Stopping recorders..."
# Stop the live draft first: it reads the .raw files we are about to delete.
if [ -n "$LIVE_PID" ]; then
    kill "$LIVE_PID" 2>/dev/null || true
    wait "$LIVE_PID" 2>/dev/null || true
fi
kill "$MIC_PID" "$PC_PID" 2>/dev/null || true
wait "$MIC_PID" 2>/dev/null || true
wait "$PC_PID" 2>/dev/null || true
trap - EXIT INT TERM

# --- raw -> wav ---------------------------------------------------------------
for pair in "$MIC_RAW:$MIC_WAV" "$PC_RAW:$PC_WAV"; do
    raw="${pair%%:*}"; wav="${pair##*:}"
    if [ -s "$raw" ]; then
        ffmpeg -hide_banner -loglevel error -y \
            -f s16le -ar "$RATE" -ac 1 -i "$raw" "$wav"
        rm -f "$raw"
    else
        echo "WARNING: $(basename "$raw") is empty — that track recorded nothing." >&2
        rm -f "$raw"
    fi
done

# Warn if a track is (almost) silent — usually a wrong default device.
check_level() {
    local wav="$1" name="$2" mean
    [ -f "$wav" ] || return 0
    mean="$(ffmpeg -hide_banner -i "$wav" -af volumedetect -f null - 2>&1 \
            | sed -n 's/.*mean_volume: *\(-\{0,1\}[0-9.]*\) dB.*/\1/p')"
    [ -n "$mean" ] || return 0
    if awk -v m="$mean" 'BEGIN{exit !(m < -55)}'; then
        echo "WARNING: the $name track sounds silent (mean volume ${mean} dB)." >&2
        echo "         Check the default devices in Settings -> Sound." >&2
    fi
}
check_level "$MIC_WAV" "microphone"
check_level "$PC_WAV" "PC-audio"

echo "==> Recording saved:"
[ -f "$MIC_WAV" ] && echo "    $MIC_WAV"
[ -f "$PC_WAV" ] && echo "    $PC_WAV"

# --- transcribe ----------------------------------------------------------------
if [ "$AUTO_TRANSCRIBE" = "1" ]; then
    echo
    exec "$HERE/transcribe.sh" "$OUT_DIR"
else
    echo
    echo "Transcribe later with:  ./transcribe.sh sessions/$STAMP"
fi
