#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/results/docker-stats.csv}"
INTERVAL="${INTERVAL:-1}"
mkdir -p "$(dirname "$OUT")"

echo 'timestamp,name,cpu_percent,memory_usage,network_io,block_io,pids' > "$OUT"
while true; do
  timestamp="$(date -Iseconds)"
  docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}|{{.NetIO}}|{{.BlockIO}}|{{.PIDs}}' \
    | while IFS='|' read -r name cpu mem net block pids; do
        printf '"%s","%s","%s","%s","%s","%s","%s"\n' \
          "$timestamp" "$name" "$cpu" "$mem" "$net" "$block" "$pids"
      done >> "$OUT"
  sleep "$INTERVAL"
done
