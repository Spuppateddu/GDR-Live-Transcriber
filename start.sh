#!/usr/bin/env bash
#
# GDR Live Transcriber — start a session
#
# Mixes your MICROPHONE + your SPEAKER OUTPUT (game / voice chat) into one
# stream, transcribes it live to your screen, and saves:
#   - a .txt transcript
#   - a .wav backup recording
#
# Stop the session with Ctrl+C. Files land in ./sessions/<timestamp>/
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHISPER_DIR="$HERE/whisper.cpp"
BIN_DIR="$WHISPER_DIR/build/bin"

# Language and model (override on the command line, e.g. LANG_CODE=en MODEL=large-v3 ./start.sh)
LANG_CODE="${LANG_CODE:-it}"
MODEL="${MODEL:-small}"
MODEL_FILE="$WHISPER_DIR/models/ggml-$MODEL.bin"

# --- sanity checks -----------------------------------------------------------
STREAM_BIN="$BIN_DIR/whisper-stream"
[ -x "$STREAM_BIN" ] || STREAM_BIN="$BIN_DIR/stream"   # older builds name it 'stream'
if [ ! -x "$STREAM_BIN" ]; then
    echo "ERROR: whisper-stream not found. Run ./install.sh first." >&2
    exit 1
fi
if [ ! -f "$MODEL_FILE" ]; then
    echo "ERROR: model '$MODEL' not found at $MODEL_FILE" >&2
    echo "Get it with: MODEL=$MODEL ./install.sh   (or pick another MODEL)" >&2
    exit 1
fi

# --- output location ---------------------------------------------------------
STAMP="$(date +%Y-%m-%d_%H-%M-%S)"
OUT_DIR="$HERE/sessions/$STAMP"
mkdir -p "$OUT_DIR"
TXT="$OUT_DIR/transcript.txt"
WAV="$OUT_DIR/recording.wav"

# --- build the combined audio source ----------------------------------------
# A null sink "gdr_mix" acts as a mixer. We loop the system output monitor and
# the microphone into it. Its .monitor then carries mic + output together.
echo "==> Setting up audio mixer..."
MOD_SINK=$(pactl load-module module-null-sink \
    sink_name=gdr_mix \
    sink_properties=device.description=GDR_Mix)
MOD_OUT=$(pactl load-module module-loopback \
    source=@DEFAULT_MONITOR@ sink=gdr_mix latency_msec=50)
MOD_MIC=$(pactl load-module module-loopback \
    source=@DEFAULT_SOURCE@ sink=gdr_mix latency_msec=50)

cleanup() {
    echo
    echo "==> Stopping & cleaning up audio mixer..."
    pactl unload-module "$MOD_MIC"  2>/dev/null || true
    pactl unload-module "$MOD_OUT"  2>/dev/null || true
    pactl unload-module "$MOD_SINK" 2>/dev/null || true
    [ -n "${REC_PID:-}" ] && kill "$REC_PID" 2>/dev/null || true
    echo
    echo "    Transcript: $TXT"
    echo "    Recording:  $WAV"
}
trap cleanup EXIT INT TERM

# --- wav backup recording (runs in background) ------------------------------
echo "==> Recording backup to $WAV"
parec -d gdr_mix.monitor --file-format=wav "$WAV" &
REC_PID=$!

# --- live transcription ------------------------------------------------------
# whisper-stream captures from the default PulseAudio source via SDL2, so we
# point that at our mixer's monitor.
export SDL_AUDIODRIVER=pulseaudio
export PULSE_SOURCE=gdr_mix.monitor

echo "==> Live transcription started (language: $LANG_CODE, model: $MODEL)."
echo "    Speak / play — text appears below. Press Ctrl+C to stop."
echo "------------------------------------------------------------"
"$STREAM_BIN" \
    -m "$MODEL_FILE" \
    -l "$LANG_CODE" \
    -t 4 \
    --step 0 --length 5000 --keep 200 -vth 0.6 \
    -f "$TXT"
