#!/usr/bin/env bash
#
# GDR Live Transcriber — ri-trascrizione di alta qualità
#
# Prende un file audio (di solito il recording.wav di una sessione) e lo
# ri-trascrive con un modello più preciso (default: large-v3), generando un
# .txt accanto al file audio.
#
# Uso:
#   ./transcribe.sh sessions/2026-06-28_21-00-00/recording.wav
#   MODEL=medium LANG_CODE=en ./transcribe.sh registrazione.wav
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHISPER_DIR="$HERE/whisper.cpp"
BIN_DIR="$WHISPER_DIR/build/bin"

LANG_CODE="${LANG_CODE:-it}"
MODEL="${MODEL:-large-v3}"
MODEL_FILE="$WHISPER_DIR/models/ggml-$MODEL.bin"

AUDIO="${1:-}"
if [ -z "$AUDIO" ] || [ ! -f "$AUDIO" ]; then
    echo "Uso: ./transcribe.sh <file-audio.wav>" >&2
    exit 1
fi

CLI_BIN="$BIN_DIR/whisper-cli"
[ -x "$CLI_BIN" ] || CLI_BIN="$BIN_DIR/main"   # build più vecchie usano 'main'
if [ ! -x "$CLI_BIN" ]; then
    echo "ERRORE: whisper-cli non trovato. Esegui prima ./install.sh" >&2
    exit 1
fi
if [ ! -f "$MODEL_FILE" ]; then
    echo "ERRORE: modello '$MODEL' non trovato in $MODEL_FILE" >&2
    echo "Scaricalo con:  MODEL=$MODEL ./install.sh" >&2
    exit 1
fi

OUT="${AUDIO%.*}"   # whisper-cli aggiunge .txt
echo "==> Ri-trascrizione di '$AUDIO' (modello: $MODEL, lingua: $LANG_CODE)..."
"$CLI_BIN" -m "$MODEL_FILE" -l "$LANG_CODE" -t 4 -otxt -of "$OUT" -f "$AUDIO"
echo "==> Fatto: $OUT.txt"
