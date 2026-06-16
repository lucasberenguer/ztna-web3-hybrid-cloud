#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS="$ROOT/results"
DURATION="${DURATION:-60s}"
REPETITIONS="${REPETITIONS:-10}"
VUS_LEVELS="${VUS_LEVELS:-10 30 60}"
mkdir -p "$RESULTS"

run_group() {
  local name="$1"
  local target="$2"
  local vus rep output
  for vus in $VUS_LEVELS; do
    for rep in $(seq 1 "$REPETITIONS"); do
      output="/results/${name}_vus${vus}_rep${rep}.json"
      echo "[$(date -Iseconds)] cenário=$name vus=$vus repetição=$rep alvo=$target"
      docker run --rm --network host \
        -v "$ROOT/tests:/scripts:ro" \
        -v "$RESULTS:/results" \
        grafana/k6:latest run \
        -e TARGET_URL="$target" \
        -e VUS="$vus" \
        -e DURATION="$DURATION" \
        --summary-export="$output" \
        /scripts/load.js
      sleep 5
    done
  done
}

run_group baseline "http://127.0.0.1:8081/"
run_group ztna "http://198.18.0.10:8080/"

echo "Resultados gravados em $RESULTS"
