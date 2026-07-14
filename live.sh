#!/usr/bin/env bash
#
# GDR Live Transcriber — near-live draft transcript
#
# Started in the background by start.sh while a session is recording.
# Watches the growing mic.raw / pc.raw files and, every LIVE_CHUNK
# seconds of new audio, transcribes the new piece with a FAST whisper model
# and prints time-ordered [HH:MM:SS] [ME]/[PC] lines to the terminal.
# The same lines are appended to live.txt in the session directory.
#
# This is a quick draft to help you remember names and events during play.
# The accurate transcript.txt is still produced at the end of the session.
#
# Usage:  ./live.sh <session-directory-being-recorded>
#
# Options (environment variables):
#   LIVE_MODEL=base   fast model for the draft (default: base, else tiny)
#   LIVE_CHUNK=30     seconds of audio per live chunk
#   LIVE_THREADS=4    CPU threads per live whisper run
#   LANG_CODE=it      spoken language (default: it, use 'auto' to detect)
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR="${1:?Usage: ./live.sh <session-directory>}"
DIR="$(cd "$DIR" && pwd)"

RATE=16000
BPS=$((RATE * 2))            # bytes per second: s16le mono
LIVE_CHUNK="${LIVE_CHUNK:-30}"
LIVE_THREADS="${LIVE_THREADS:-4}"
LANG_CODE="${LANG_CODE:-it}"
MAX_CHUNK=120                # catch-up cap: never transcribe more than this at once

CLI_BIN="$HERE/whisper.cpp/build/bin/whisper-cli"
[ -x "$CLI_BIN" ] || CLI_BIN="$HERE/whisper.cpp/build/bin/main"
if [ ! -x "$CLI_BIN" ]; then
    echo "live: whisper-cli not found — live view disabled." >&2
    exit 1
fi

# The live draft needs a fast model to keep up while you play; the big model
# stays reserved for the accurate final pass.
LIVE_MODEL="${LIVE_MODEL:-}"
if [ -z "$LIVE_MODEL" ]; then
    for m in base tiny; do
        if [ -f "$HERE/whisper.cpp/models/ggml-$m.bin" ]; then LIVE_MODEL="$m"; break; fi
    done
fi
if [ -z "$LIVE_MODEL" ] || [ ! -f "$HERE/whisper.cpp/models/ggml-$LIVE_MODEL.bin" ]; then
    echo "live: no fast model found (get one with: MODEL=base ./install.sh) — live view disabled." >&2
    exit 1
fi
MODEL_FILE="$HERE/whisper.cpp/models/ggml-$LIVE_MODEL.bin"

TMP="$(mktemp -d)"
STOP=""
trap 'STOP=1' INT TERM
trap 'rm -rf "$TMP"' EXIT

LIVE_TXT="$DIR/live.txt"
printf '# Live draft (model: %s) — the final transcript.txt supersedes this file.\n' \
    "$LIVE_MODEL" > "$LIVE_TXT"

# Convert an .srt into "seconds<TAB>label<TAB>text" lines, shifting timestamps
# by the chunk start. Non-speech markers like [BLANK_AUDIO] / (music) dropped,
# same as transcribe.sh.
srt_to_tsv() {  # $1=srt  $2=label  $3=chunk-start-seconds
    awk -v label="$2" -v base="$3" '
        function flush() {
            if (buf != "" && buf !~ /^\[.*\]$/ && buf !~ /^\(.*\)$/)
                printf "%d\t%s\t%s\n", base + start, label, buf
            buf = ""
        }
        /-->/ {
            split($1, t, "[:,]")
            start = t[1]*3600 + t[2]*60 + t[3]
            intext = 1; buf = ""; next
        }
        !intext { next }
        /^[[:space:]]*$/ { flush(); intext = 0; next }
        {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            buf = (buf == "" ? $0 : buf " " $0)
        }
        END { if (intext) flush() }
    ' "$1"
}

# Bytes of a raw file not yet processed, sample-aligned, capped at MAX_CHUNK.
avail() {  # $1=rawfile  $2=offset-bytes
    local size n
    size="$(stat -c %s "$1" 2>/dev/null || echo 0)"
    n=$(( size - $2 ))
    [ "$n" -lt 0 ] && n=0
    [ "$n" -gt $((MAX_CHUNK * BPS)) ] && n=$((MAX_CHUNK * BPS))
    echo $(( n - n % 2 ))
}

# Transcribe one new chunk of one raw track; emits tsv lines on stdout.
# Any failure (device gone, Ctrl+C mid-whisper) just skips the chunk.
do_chunk() {  # $1=rawfile  $2=label  $3=offset-bytes  $4=length-bytes
    local start_s=$(( $3 / BPS )) mean
    rm -f "$TMP/chunk.raw" "$TMP/chunk.wav" "$TMP/chunk.srt"
    dd if="$1" of="$TMP/chunk.raw" iflag=skip_bytes,count_bytes \
        skip="$3" count="$4" status=none 2>/dev/null || return 0
    ffmpeg -hide_banner -loglevel error -y \
        -f s16le -ar "$RATE" -ac 1 -i "$TMP/chunk.raw" "$TMP/chunk.wav" \
        2>/dev/null || return 0
    # Skip silent chunks: whisper hallucinates text on silence.
    mean="$(ffmpeg -hide_banner -i "$TMP/chunk.wav" -af volumedetect -f null - 2>&1 \
            | sed -n 's/.*mean_volume: *\(-\{0,1\}[0-9.]*\) dB.*/\1/p')" || true
    if [ -n "$mean" ] && awk -v m="$mean" 'BEGIN{exit !(m < -55)}'; then
        return 0
    fi
    "$CLI_BIN" -m "$MODEL_FILE" -l "$LANG_CODE" -t "$LIVE_THREADS" -np \
        -osrt -of "$TMP/chunk" -f "$TMP/chunk.wav" >/dev/null 2>&1 || return 0
    [ -f "$TMP/chunk.srt" ] && srt_to_tsv "$TMP/chunk.srt" "$2" "$start_s"
    return 0
}

OFF_MIC=0
OFF_PC=0
NEED=$(( LIVE_CHUNK * BPS ))

while [ -z "$STOP" ]; do
    sleep 1 || true
    [ -n "$STOP" ] && break

    OUT=""
    A="$(avail "$DIR/mic.raw" "$OFF_MIC")"
    if [ "$A" -ge "$NEED" ]; then
        OUT+="$(do_chunk "$DIR/mic.raw" "ME" "$OFF_MIC" "$A")"$'\n'
        OFF_MIC=$(( OFF_MIC + A ))
    fi
    [ -n "$STOP" ] && break
    A="$(avail "$DIR/pc.raw" "$OFF_PC")"
    if [ "$A" -ge "$NEED" ]; then
        OUT+="$(do_chunk "$DIR/pc.raw" "PC" "$OFF_PC" "$A")"$'\n'
        OFF_PC=$(( OFF_PC + A ))
    fi

    [ -n "${OUT//$'\n'/}" ] || continue
    printf '%s' "$OUT" | grep -v '^$' | sort -s -n -k1,1 \
        | awk -F'\t' '{ printf "[%02d:%02d:%02d] [%s] %s\n",
                        $1/3600, ($1%3600)/60, $1%60, $2, $3 }' \
        | while IFS= read -r line; do
              # \r + clear-line first: overwrite the recording timer cleanly.
              printf '\r\033[K%s\n' "$line"
              printf '%s\n' "$line" >> "$LIVE_TXT"
          done
done
