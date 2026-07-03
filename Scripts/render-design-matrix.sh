#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENARIOS=(ready processing recording failed empty)
SCHEMES=(light dark)

for scheme in "${SCHEMES[@]}"; do
  for scenario in "${SCENARIOS[@]}"; do
    "$ROOT_DIR/Scripts/render-design-snapshot.sh" \
      "$ROOT_DIR/.build/design-snapshot-$scheme-$scenario.png" \
      "$scheme" \
      "$scenario"
  done
done
