#!/usr/bin/env bash
#
# GDR Live Transcriber — installer
# Installs all dependencies and builds whisper.cpp (offline speech-to-text).
# Tested on Ubuntu 24.04 (PipeWire).
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHISPER_DIR="$HERE/whisper.cpp"

# Model to download. Options (smaller = faster, larger = more accurate):
#   tiny  base  small  medium  large-v3
# 'small' works well for live transcription on CPU. For best accuracy on a
# recorded file afterwards, also get large-v3:  MODEL=large-v3 ./install.sh
MODEL="${MODEL:-small}"

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
