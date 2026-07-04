#!/usr/bin/env bash
set -euo pipefail

# Installs the sherpa-onnx speaker-diarization sidecar (engine + two models).
# Same layout the in-app installer uses, so the app picks everything up automatically.

SHERPA_VERSION="${SHERPA_VERSION:-1.13.3}"
ARCHIVE_ROOT="sherpa-onnx-v${SHERPA_VERSION}-osx-arm64-shared"
RUNTIME_URL="${RUNTIME_URL:-https://github.com/k2-fsa/sherpa-onnx/releases/download/v${SHERPA_VERSION}/${ARCHIVE_ROOT}.tar.bz2}"
SEGMENTATION_URL="${SEGMENTATION_URL:-https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2}"
# Note: "recongition" is a real typo in the upstream release tag — do not fix it.
EMBEDDING_URL="${EMBEDDING_URL:-https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/nemo_en_titanet_small.onnx}"

DIARIZE_DIR="${WHISPERDOWN_DIARIZE_DIR:-$HOME/Library/Application Support/Whisperdown/Diarization}"
RUNTIME_DIR="$DIARIZE_DIR/sherpa-onnx"
MODELS_DIR="$DIARIZE_DIR/Models"

mkdir -p "$RUNTIME_DIR" "$MODELS_DIR"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

if [ ! -x "$RUNTIME_DIR/bin/sherpa-onnx-offline-speaker-diarization" ]; then
  echo "Downloading sherpa-onnx runtime (~25 MB)..."
  curl -L "$RUNTIME_URL" -o "$STAGING/runtime.tar.bz2"
  tar -xjf "$STAGING/runtime.tar.bz2" -C "$STAGING"
  rm -rf "$RUNTIME_DIR/bin" "$RUNTIME_DIR/lib"
  # bin/ and lib/ must stay siblings — the binaries locate the dylibs via rpath.
  mv "$STAGING/$ARCHIVE_ROOT/bin" "$STAGING/$ARCHIVE_ROOT/lib" "$RUNTIME_DIR/"
fi

if [ ! -f "$MODELS_DIR/pyannote-segmentation-3-0.onnx" ]; then
  echo "Downloading segmentation model (~7 MB)..."
  curl -L "$SEGMENTATION_URL" -o "$STAGING/segmentation.tar.bz2"
  tar -xjf "$STAGING/segmentation.tar.bz2" -C "$STAGING"
  mv "$STAGING/sherpa-onnx-pyannote-segmentation-3-0/model.onnx" "$MODELS_DIR/pyannote-segmentation-3-0.onnx"
fi

if [ ! -f "$MODELS_DIR/nemo_en_titanet_small.onnx" ]; then
  echo "Downloading speaker embedding model (~38 MB)..."
  curl -L "$EMBEDDING_URL" -o "$MODELS_DIR/nemo_en_titanet_small.onnx"
fi

echo "diarization cli: $RUNTIME_DIR/bin/sherpa-onnx-offline-speaker-diarization"
echo "segmentation model: $MODELS_DIR/pyannote-segmentation-3-0.onnx"
echo "embedding model: $MODELS_DIR/nemo_en_titanet_small.onnx"
