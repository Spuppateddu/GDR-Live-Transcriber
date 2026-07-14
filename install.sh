#!/usr/bin/env bash
#
# GDR Live Transcriber — installer
# Installs all dependencies and builds whisper.cpp (offline speech-to-text).
# Tested on Ubuntu 24.04 (PipeWire).
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHISPER_DIR="$HERE/whisper.cpp"

# Which model to download. You can force it non-interactively with MODEL=...
#   tiny  base  small  medium  large-v3   (smaller = faster, larger = accurate)
# If MODEL is not set, the script detects your CPU/RAM, recommends a model and
# lets you choose.
MODEL="${MODEL:-}"

choose_model() {
    # --- detect hardware -----------------------------------------------------
    local cores ram_gb rec
    cores="$(nproc 2>/dev/null || echo 4)"
    ram_gb="$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 8)"

    # --- recommendation based on cores + RAM ---------------------------------
    if   [ "$cores" -ge 8 ] && [ "$ram_gb" -ge 16 ]; then rec="medium"
    elif [ "$cores" -ge 4 ] && [ "$ram_gb" -ge 8  ]; then rec="small"
    elif [ "$cores" -ge 2 ];                          then rec="base"
    else                                                   rec="tiny"
    fi

    echo "==> Detected CPU: ${cores} cores, ${ram_gb} GB RAM" >&2
    echo "    Recommended model for this machine: ${rec}" >&2
    echo >&2
    echo "Choose the model to download (used to transcribe after each session):" >&2
    echo "   1) tiny     - fastest, low quality            (~75 MB)"  >&2
    echo "   2) base     - fast, decent quality            (~140 MB)" >&2
    echo "   3) small    - good balance                    (~460 MB)" >&2
    echo "   4) medium   - very accurate, slower           (~1.5 GB)" >&2
    echo "   5) large-v3 - best quality, VERY slow on CPU  (~3 GB)"   >&2
    echo >&2
    echo "All models are multilingual and understand Italian." >&2
    echo >&2
    local choice
    read -rp "Number [Enter = recommended: ${rec}]: " choice </dev/tty || choice=""
    case "$choice" in
        1) echo "tiny" ;;
        2) echo "base" ;;
        3) echo "small" ;;
        4) echo "medium" ;;
        5) echo "large-v3" ;;
        "") echo "$rec" ;;
        *) echo "Invalid choice, using recommended: ${rec}" >&2; echo "$rec" ;;
    esac
}

if [ -z "$MODEL" ]; then
    if [ -t 0 ] || [ -e /dev/tty ]; then
        MODEL="$(choose_model)"
    else
        MODEL="small"   # no interactive terminal: use a sensible default
    fi
fi

echo "==> Installing system packages (needs sudo)..."
sudo apt-get update
sudo apt-get install -y \
    build-essential cmake git \
    ffmpeg \
    pulseaudio-utils \
    pipewire-audio-client-libraries wireplumber

echo "==> Getting whisper.cpp..."
if [ -d "$WHISPER_DIR/.git" ]; then
    git -C "$WHISPER_DIR" pull --ff-only
else
    git clone https://github.com/ggerganov/whisper.cpp "$WHISPER_DIR"
fi

echo "==> Building whisper.cpp..."
cmake -S "$WHISPER_DIR" -B "$WHISPER_DIR/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$WHISPER_DIR/build" -j --config Release

echo "==> Downloading model: $MODEL ..."
bash "$WHISPER_DIR/models/download-ggml-model.sh" "$MODEL"

echo
echo "==> Done."
echo "    whisper.cpp built in: $WHISPER_DIR/build/bin"
echo "    model:                $WHISPER_DIR/models/ggml-$MODEL.bin"
echo
echo "Now run a session with:   $HERE/start.sh"
