#!/usr/bin/env bash
set -euo pipefail

# Installs the llama.cpp summary sidecar (runtime + one Gemma 4 GGUF model).
# Same layout the in-app installer uses, so the app picks everything up automatically.

LLAMA_VERSION="${LLAMA_VERSION:-b9873}"
RUNTIME_URL="${RUNTIME_URL:-https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_VERSION}/llama-${LLAMA_VERSION}-bin-macos-arm64.tar.gz}"

# GEMMA_MODEL: e4b | 12b | 26b  (default e4b)
GEMMA_MODEL="${GEMMA_MODEL:-e4b}"
case "$GEMMA_MODEL" in
  e4b) MODEL_FILE="gemma-4-E4B-it-Q4_K_M.gguf"; MODEL_REPO="unsloth/gemma-4-E4B-it-GGUF" ;;
  12b) MODEL_FILE="gemma-4-12b-it-Q4_K_M.gguf"; MODEL_REPO="unsloth/gemma-4-12b-it-GGUF" ;;
  26b) MODEL_FILE="gemma-4-26B-A4B-it-UD-Q4_K_M.gguf"; MODEL_REPO="unsloth/gemma-4-26B-A4B-it-GGUF" ;;
  *) echo "unknown GEMMA_MODEL: $GEMMA_MODEL (use e4b|12b|26b)"; exit 1 ;;
esac
MODEL_URL="${MODEL_URL:-https://huggingface.co/${MODEL_REPO}/resolve/main/${MODEL_FILE}}"

SUMMARY_DIR="${WHISPERDOWN_SUMMARY_DIR:-$HOME/Library/Application Support/Whisperdown/Summary}"
RUNTIME_DIR="$SUMMARY_DIR/llama.cpp"
MODELS_DIR="$SUMMARY_DIR/Models"

mkdir -p "$RUNTIME_DIR" "$MODELS_DIR"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

if [ ! -x "$RUNTIME_DIR/bin/llama-completion" ]; then
  echo "Downloading llama.cpp runtime ${LLAMA_VERSION} (~11 MB)..."
  curl -L "$RUNTIME_URL" -o "$STAGING/runtime.tar.gz"
  tar -xzf "$STAGING/runtime.tar.gz" -C "$STAGING"
  # llama-completion과 dylib들이 형제인 디렉토리를 찾아 통째로 bin/으로 이동 (rpath 형제 참조 유지).
  BIN_SRC="$(dirname "$(find "$STAGING" -name llama-completion -type f | head -1)")"
  [ -n "$BIN_SRC" ] || { echo "llama-completion not found in archive"; exit 1; }
  rm -rf "$RUNTIME_DIR/bin"
  mv "$BIN_SRC" "$RUNTIME_DIR/bin"
fi

if [ ! -f "$MODELS_DIR/$MODEL_FILE" ]; then
  echo "Downloading $MODEL_FILE (several GB, this can take a while)..."
  curl -L "$MODEL_URL" -o "$MODELS_DIR/$MODEL_FILE"
fi

echo "summary cli: $RUNTIME_DIR/bin/llama-completion"
echo "summary model: $MODELS_DIR/$MODEL_FILE"
