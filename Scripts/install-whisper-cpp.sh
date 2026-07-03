#!/usr/bin/env bash
set -euo pipefail

MODEL_NAME="${MODEL_NAME:-ggml-large-v3-turbo.bin}"
MODEL_URL="${MODEL_URL:-https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${MODEL_NAME}}"
MODEL_DIR="${VOICE_TO_MARKDOWN_MODEL_DIR:-$HOME/Library/Application Support/Voice to Markdown/Models}"

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required to install whisper.cpp automatically."
  echo "Install whisper.cpp manually and set VOICE_TO_MARKDOWN_WHISPER_CLI."
  exit 1
fi

if ! command -v whisper-cli >/dev/null 2>&1; then
  brew install whisper-cpp
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  brew install ffmpeg
fi

mkdir -p "$MODEL_DIR"

if [ ! -f "$MODEL_DIR/$MODEL_NAME" ]; then
  curl -L "$MODEL_URL" -o "$MODEL_DIR/$MODEL_NAME"
fi

echo "whisper-cli: $(command -v whisper-cli)"
echo "ffmpeg: $(command -v ffmpeg)"
echo "model: $MODEL_DIR/$MODEL_NAME"
