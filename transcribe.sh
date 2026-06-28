#!/usr/bin/env bash
#
# GDR Live Transcriber — high-quality re-transcription
#
# Takes an audio file (usually a session's recording.wav) and re-transcribes it
# with a more accurate model (default: large-v3), producing a .txt next to the
# audio file.
#
# Usage:
#   ./transcribe.sh sessions/2026-06-28_21-00-00/recording.wav
#   MODEL=medium LANG_CODE=en ./transcribe.sh recording.wav
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHISPER_DIR="$HERE/whisper.cpp"
BIN_DIR="$WHISPER_DIR/build/bin"

# Spoken language to transcribe (default: Italian).
LANG_CODE="${LANG_CODE:-it}"
MODEL="${MODEL:-large-v3}"
MODEL_FILE="$WHISPER_DIR/models/ggml-$MODEL.bin"

AUDIO="${1:-}"
if [ -z "$AUDIO" ] || [ ! -f "$AUDIO" ]; then
    echo "Usage: ./transcribe.sh <audio-file.wav>" >&2
    exit 1
fi

CLI_BIN="$BIN_DIR/whisper-cli"
[ -x "$CLI_BIN" ] || CLI_BIN="$BIN_DIR/main"   # older builds name it 'main'
if [ ! -x "$CLI_BIN" ]; then
    echo "ERROR: whisper-cli not found. Run ./install.sh first." >&2
    exit 1
fi
if [ ! -f "$MODEL_FILE" ]; then
    echo "ERROR: model '$MODEL' not found at $MODEL_FILE" >&2
    echo "Get it with:  MODEL=$MODEL ./install.sh" >&2
    exit 1
fi

OUT="${AUDIO%.*}"   # whisper-cli appends .txt
echo "==> Re-transcribing '$AUDIO' (model: $MODEL, language: $LANG_CODE)..."
"$CLI_BIN" -m "$MODEL_FILE" -l "$LANG_CODE" -t 4 -otxt -of "$OUT" -f "$AUDIO"
echo "==> Done: $OUT.txt"
