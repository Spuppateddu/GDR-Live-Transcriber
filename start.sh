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
# When you run it the script ASKS for the common options (language, model,
# live draft) with all the valid answers listed — no need to remember anything.
# You can still preset any option as an environment variable to skip its
# question (handy for scripting or a fixed setup):
#   LANG_CODE=it        spoken language (default: it, use 'auto' to detect)
#   MODEL=small         whisper model for the transcription at the end
#   AUTO_TRANSCRIBE=0   record only; transcribe later with ./transcribe.sh
#   LIVE=0              disable the live draft in the terminal
#   LIVE_MODEL=base     fast model for the live draft (default: base)
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

# --- interactive setup -------------------------------------------------------
# Ask the common options here so you never have to remember any argument.
# A question is skipped if that option is already set — either passed on the
# command line (e.g. MODEL=medium ./start.sh) or remembered in config.env from
# a previous run. With no terminal available, the defaults below are used.
MODELS_DIR="$HERE/whisper.cpp/models"
CONFIG_FILE="$HERE/config.env"

# Remember what was set on the command line BEFORE loading the saved file, so a
# command-line value keeps winning even if you later choose to change the setup.
CLI_LANG_CODE="${LANG_CODE:-}"
CLI_MODEL="${MODEL:-}"
CLI_LIVE="${LIVE:-}"

# Load remembered answers (config.env uses ':=' so it fills only what you did
# not set on the command line).
CONFIG_LOADED=0
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
    CONFIG_LOADED=1
fi

ask() {  # $1 = prompt shown on screen; echoes the typed reply on stdout
    local reply=""
    read -rp "$1" reply </dev/tty || reply=""
    printf '%s' "$reply"
}

ASKED=()          # options we prompted for this run (offered for saving)
HEADER_SHOWN=0
maybe_header() {
    [ "$HEADER_SHOWN" = "1" ] && return
    echo "=== Session setup — press Enter to accept the [default] ==="
    HEADER_SHOWN=1
}

# If a saved setup was loaded, show it and let you keep or change it before
# recording. Choosing to change just forgets the saved values (keeping any
# command-line override) so the questions below run again.
if [ "$CONFIG_LOADED" = "1" ] && [ -e /dev/tty ]; then
    echo "==> Current saved setup (config.env):"
    echo "      Language:   ${LANG_CODE:-it}"
    echo "      Model:      ${MODEL:-<best installed>}"
    echo "      Live draft: $([ "${LIVE:-1}" = "0" ] && echo off || echo on)"
    keep="$(ask 'Use this setup? [Y = keep / n = change it]: ')"
    case "$keep" in
        n|N|no|NO)
            LANG_CODE="$CLI_LANG_CODE"
            MODEL="$CLI_MODEL"
            LIVE="$CLI_LIVE"
            ;;
    esac
    echo
fi

if [ -e /dev/tty ]; then
    # 1) Language spoken in the session (used for both draft and final text).
    if [ -z "${LANG_CODE:-}" ]; then
        maybe_header
        echo
        echo "Language spoken in the session:"
        echo "   1) it   - Italian   (default)"
        echo "   2) en   - English"
        echo "   3) auto - let whisper detect it automatically"
        echo "   ...or type any 2-letter code (es, fr, de, pt, ...)"
        c="$(ask 'Choice [1]: ')"
        case "$c" in
            ""|1) LANG_CODE="it" ;;
            2)    LANG_CODE="en" ;;
            3)    LANG_CODE="auto" ;;
            *)    LANG_CODE="$c" ;;
        esac
        ASKED+=("LANG_CODE")
    fi

    # 2) Model for the FINAL transcript — list only models actually installed,
    #    so you can never pick one that isn't there. Default = the best one.
    if [ -z "${MODEL:-}" ]; then
        installed=()
        for m in base small medium large-v3; do
            [ -f "$MODELS_DIR/ggml-$m.bin" ] && installed+=("$m")
        done
        if [ "${#installed[@]}" -gt 1 ]; then
            default="${installed[-1]}"   # base<small<medium<large -> last = best
            maybe_header
            echo
            echo "Model for the final (accurate) transcript — bigger = better but slower:"
            i=1
            for m in "${installed[@]}"; do
                mark=""; [ "$m" = "$default" ] && mark="   (default, best you have)"
                echo "   $i) $m$mark"
                i=$((i+1))
            done
            echo "   (install more models with ./install.sh)"
            c="$(ask "Choice [$default]: ")"
            if [ -n "$c" ] && [ "$c" -ge 1 ] 2>/dev/null \
               && [ "$c" -le "${#installed[@]}" ] 2>/dev/null; then
                MODEL="${installed[$((c-1))]}"
            else
                MODEL="$default"
            fi
            ASKED+=("MODEL")
        fi
        # 0 or 1 model installed: nothing to choose; transcribe.sh auto-picks it.
    fi

    # 3) Live draft transcript on screen while you play?
    if [ -z "${LIVE:-}" ]; then
        maybe_header
        echo
        echo "Show the live draft transcript on screen while recording?"
        echo "   1) yes - rough but very handy to re-read names/events (default)"
        echo "   2) no  - just show the recording timer"
        c="$(ask 'Choice [1]: ')"
        case "$c" in
            2) LIVE="0" ;;
            *) LIVE="1" ;;
        esac
        ASKED+=("LIVE")
    fi

    [ "$HEADER_SHOWN" = "1" ] && echo
fi

# Apply defaults for anything still unset (e.g. no terminal), and export the
# choices so the live.sh / transcribe.sh helpers inherit them.
LANG_CODE="${LANG_CODE:-it}"
LIVE="${LIVE:-1}"
export LANG_CODE LIVE
[ -n "${MODEL:-}" ] && export MODEL

# Offer to remember the answers so future runs skip the questions entirely.
if [ -e /dev/tty ] && [ "${#ASKED[@]}" -gt 0 ]; then
    save="$(ask 'Remember these answers so I stop asking next time? [y/N]: ')"
    case "$save" in
        y|Y|yes|YES)
            {
                echo "# GDR Live Transcriber — saved defaults (written by start.sh)."
                echo "# Delete a line to be asked about that option again;"
                echo "# delete the whole file to reconfigure from scratch."
                echo "# A value passed on the command line still overrides these."
                echo ": \"\${LANG_CODE:=$LANG_CODE}\""
                [ -n "${MODEL:-}" ] && echo ": \"\${MODEL:=$MODEL}\""
                echo ": \"\${LIVE:=$LIVE}\""
            } > "$CONFIG_FILE"
            echo "==> Saved to config.env — you won't be asked again."
            echo
            ;;
    esac
fi

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
