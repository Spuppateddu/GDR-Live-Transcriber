#!/usr/bin/env bash
#
# GDR Live Transcriber — transcription
#
# Two modes:
#
#   1) Session directory (the normal case, run automatically by start.sh):
#        ./transcribe.sh sessions/2026-07-14_21-00-00
#      Transcribes mic.wav and pc.wav and merges them, time-ordered and
#      labeled [ME] / [PC], into transcript.txt in the same directory.
#
#   2) Single audio file:
#        ./transcribe.sh some-audio.wav
#      Produces some-audio.txt next to it.
#
# Options (environment variables):
#   LANG_CODE=it   spoken language (default: it, use 'auto' to detect)
#   MODEL=medium   whisper model (default: best one you have installed)
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHISPER_DIR="$HERE/whisper.cpp"
BIN_DIR="$WHISPER_DIR/build/bin"
LANG_CODE="${LANG_CODE:-it}"

TARGET="${1:-}"
if [ -z "$TARGET" ] || { [ ! -f "$TARGET" ] && [ ! -d "$TARGET" ]; }; then
    echo "Usage: ./transcribe.sh <session-directory | audio-file>" >&2
    exit 1
fi

CLI_BIN="$BIN_DIR/whisper-cli"
[ -x "$CLI_BIN" ] || CLI_BIN="$BIN_DIR/main"   # older builds name it 'main'
if [ ! -x "$CLI_BIN" ]; then
    echo "ERROR: whisper-cli not found. Run ./install.sh first." >&2
    exit 1
fi

# Model: use $MODEL if forced, otherwise the best installed one.
# 'small' is preferred over 'large-v3' because large-v3 on CPU can take
# longer than the session itself.
MODEL="${MODEL:-}"
if [ -z "$MODEL" ]; then
    for m in medium small large-v3 base tiny; do
        if [ -f "$WHISPER_DIR/models/ggml-$m.bin" ]; then MODEL="$m"; break; fi
    done
fi
MODEL="${MODEL:-small}"
MODEL_FILE="$WHISPER_DIR/models/ggml-$MODEL.bin"
if [ ! -f "$MODEL_FILE" ]; then
    echo "ERROR: model '$MODEL' not found at $MODEL_FILE" >&2
    echo "Get it with:  MODEL=$MODEL ./install.sh" >&2
    exit 1
fi

THREADS="$(nproc 2>/dev/null || echo 4)"

# Voice Activity Detection: skip non-speech before it reaches whisper.
# Without it, long silences (e.g. the mic while friends talk) make whisper
# hallucinate a sentence and repeat it in a loop, ruining the whole track.
VAD_ARGS=()
VAD_MODEL="$WHISPER_DIR/models/ggml-silero-v6.2.0.bin"
if [ -f "$VAD_MODEL" ]; then
    VAD_ARGS=(--vad -vm "$VAD_MODEL")
else
    echo "NOTE: VAD model missing; silent stretches may produce hallucinated text." >&2
    echo "      Get it with:  bash whisper.cpp/models/download-vad-model.sh silero-v6.2.0" >&2
fi

# Run whisper on one wav, producing <prefix>.srt (timestamps needed for merging).
run_whisper_srt() {  # $1=wav  $2=output-prefix  $3=threads
    "$CLI_BIN" -m "$MODEL_FILE" -l "$LANG_CODE" -t "$3" "${VAD_ARGS[@]}" \
        -osrt -of "$2" -f "$1" > "$2.log" 2>&1
}

# Convert an .srt into lines of "seconds<TAB>label<TAB>text".
# Segments that are only a non-speech marker like [BLANK_AUDIO] or (music)
# are dropped — whisper emits those on silence/music.
srt_to_tsv() {  # $1=srt  $2=label
    awk -v label="$2" '
        function flush() {
            if (buf != "" && buf !~ /^\[.*\]$/ && buf !~ /^\(.*\)$/)
                printf "%d\t%s\t%s\n", start, label, buf
            buf = ""
        }
        /-->/ {
            split($1, t, "[:,]")
            start = t[1]*3600 + t[2]*60 + t[3]
            intext = 1; buf = ""; next
        }
        !intext { next }                       # subtitle index lines
        /^[[:space:]]*$/ { flush(); intext = 0; next }   # blank line ends the block
        {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            buf = (buf == "" ? $0 : buf " " $0)
        }
        END { if (intext) flush() }
    ' "$1"
}

# ==============================================================================
# Mode 1: session directory -> merged transcript.txt
# ==============================================================================
if [ -d "$TARGET" ]; then
    DIR="$(cd "$TARGET" && pwd)"
    MIC_WAV="$DIR/mic.wav"
    PC_WAV="$DIR/pc.wav"
    # Legacy sessions called the PC-audio track "discord".
    [ ! -f "$PC_WAV" ] && [ -f "$DIR/discord.wav" ] && PC_WAV="$DIR/discord.wav"
    PC_PREFIX="${PC_WAV%.wav}"
    TXT="$DIR/transcript.txt"

    TRACKS=0
    [ -f "$MIC_WAV" ] && TRACKS=$((TRACKS+1))
    [ -f "$PC_WAV" ] && TRACKS=$((TRACKS+1))
    if [ "$TRACKS" -eq 0 ]; then
        # Legacy sessions recorded a single mixed recording.wav.
        if [ -f "$DIR/recording.wav" ]; then
            exec "$0" "$DIR/recording.wav"
        fi
        echo "ERROR: no mic.wav / pc.wav found in $DIR" >&2
        exit 1
    fi

    # Both tracks run in parallel, splitting the CPU threads between them.
    T_EACH=$(( THREADS / TRACKS )); [ "$T_EACH" -lt 1 ] && T_EACH=1
    echo "==> Transcribing $TRACKS track(s) (model: $MODEL, language: $LANG_CODE, $T_EACH threads each)..."
    echo "    This runs offline and can take a while for long sessions."

    PIDS=()
    if [ -f "$MIC_WAV" ]; then
        run_whisper_srt "$MIC_WAV" "$DIR/mic" "$T_EACH" & PIDS+=($!)
    fi
    if [ -f "$PC_WAV" ]; then
        run_whisper_srt "$PC_WAV" "$PC_PREFIX" "$T_EACH" & PIDS+=($!)
    fi
    FAIL=0
    for pid in "${PIDS[@]}"; do
        wait "$pid" || FAIL=1
    done
    if [ "$FAIL" -ne 0 ]; then
        echo "ERROR: whisper failed on a track. See the .log files in $DIR" >&2
        exit 1
    fi

    echo "==> Merging tracks into transcript.txt ..."
    {
        echo "# GDR session $(basename "$DIR") — language: $LANG_CODE, model: $MODEL"
        echo "# [ME] = my microphone. [PC] = my PC's audio: friends on Discord, game sounds."
        echo
        {
            [ -f "$DIR/mic.srt" ]       && srt_to_tsv "$DIR/mic.srt"       "ME"
            [ -f "$PC_PREFIX.srt" ]     && srt_to_tsv "$PC_PREFIX.srt"     "PC"
        } | sort -s -n -k1,1 \
          | awk -F'\t' '{ printf "[%02d:%02d:%02d] [%s] %s\n",
                          $1/3600, ($1%3600)/60, $1%60, $2, $3 }'
    } > "$TXT"

    LINES=$(( $(wc -l < "$TXT") - 3 ))
    [ "$LINES" -lt 0 ] && LINES=0
    echo
    echo "==> Done: $TXT  ($LINES lines)"
    if [ "$LINES" -eq 0 ]; then
        echo "    (empty transcript — were the tracks silent? Check the .wav files)" >&2
    fi
    exit 0
fi

# ==============================================================================
# Mode 2: single audio file -> <file>.txt
# ==============================================================================
AUDIO="$TARGET"
OUT="${AUDIO%.*}"

# whisper.cpp wants 16 kHz mono wav; convert whatever we were given.
TMP_WAV="$(mktemp --suffix=.wav)"
trap 'rm -f "$TMP_WAV"' EXIT
ffmpeg -hide_banner -loglevel error -y -i "$AUDIO" -ar 16000 -ac 1 "$TMP_WAV"

echo "==> Transcribing '$AUDIO' (model: $MODEL, language: $LANG_CODE)..."
"$CLI_BIN" -m "$MODEL_FILE" -l "$LANG_CODE" -t "$THREADS" "${VAD_ARGS[@]}" \
    -otxt -of "$OUT" -f "$TMP_WAV"
echo "==> Done: $OUT.txt"
