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

    echo "==> CPU rilevata: ${cores} core, ${ram_gb} GB RAM" >&2
    echo "    Modello consigliato per il LIVE su questa macchina: ${rec}" >&2
    echo >&2
    echo "Scegli il modello da scaricare (per il tempo reale):" >&2
    echo "   1) tiny     - velocissimo, qualita' bassa        (~75 MB)"  >&2
    echo "   2) base     - veloce, qualita' discreta          (~140 MB)" >&2
    echo "   3) small    - buon compromesso                   (~460 MB)" >&2
    echo "   4) medium   - lento ma molto preciso             (~1.5 GB)" >&2
    echo "   5) large-v3 - massima qualita', NON per il live  (~3 GB)"   >&2
    echo >&2
    local choice
    read -rp "Numero [Invio = consigliato: ${rec}]: " choice </dev/tty || choice=""
    case "$choice" in
        1) echo "tiny" ;;
        2) echo "base" ;;
        3) echo "small" ;;
        4) echo "medium" ;;
        5) echo "large-v3" ;;
        "") echo "$rec" ;;
        *) echo "Scelta non valida, uso il consigliato: ${rec}" >&2; echo "$rec" ;;
    esac
}

if [ -z "$MODEL" ]; then
    if [ -t 0 ] || [ -e /dev/tty ]; then
        MODEL="$(choose_model)"
    else
        MODEL="small"   # nessun terminale interattivo: usa un default sensato
    fi
fi

echo "==> Installing system packages (needs sudo)..."
sudo apt-get update
sudo apt-get install -y \
    build-essential cmake git \
    ffmpeg \
    pulseaudio-utils \
    pipewire-audio-client-libraries wireplumber \
    libsdl2-dev

echo "==> Getting whisper.cpp..."
if [ -d "$WHISPER_DIR/.git" ]; then
    git -C "$WHISPER_DIR" pull --ff-only
else
    git clone https://github.com/ggerganov/whisper.cpp "$WHISPER_DIR"
fi

echo "==> Building whisper.cpp (with live-stream support)..."
cmake -S "$WHISPER_DIR" -B "$WHISPER_DIR/build" -DWHISPER_SDL2=ON -DCMAKE_BUILD_TYPE=Release
cmake --build "$WHISPER_DIR/build" -j --config Release

echo "==> Downloading model: $MODEL ..."
bash "$WHISPER_DIR/models/download-ggml-model.sh" "$MODEL"

echo
echo "==> Done."
echo "    whisper.cpp built in: $WHISPER_DIR/build/bin"
echo "    model:                $WHISPER_DIR/models/ggml-$MODEL.bin"
echo
echo "Now run a session with:   $HERE/start.sh"
