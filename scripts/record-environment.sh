#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/results/environment.txt"
mkdir -p "$ROOT/results"

{
  echo "captured_at=$(date -Iseconds)"
  echo
  echo "===== SISTEMA ====="
  uname -a
  cat /etc/os-release 2>/dev/null || true
  echo
  echo "===== CPU ====="
  lscpu 2>/dev/null || true
  echo
  echo "===== MEMÓRIA ====="
  free -h 2>/dev/null || true
  echo
  echo "===== DISCOS ====="
  lsblk -o NAME,MODEL,SIZE,TYPE,MOUNTPOINTS 2>/dev/null || true
  echo
  echo "===== GPU ====="
  lspci 2>/dev/null | grep -Ei 'vga|3d|display' || true
  command -v nvidia-smi >/dev/null && nvidia-smi || true
  echo
  echo "===== SOFTWARE ====="
  docker --version 2>/dev/null || true
  docker compose version 2>/dev/null || true
  node --version 2>/dev/null || true
  npm --version 2>/dev/null || true
  ziti-edge-tunnel version 2>/dev/null || true
  echo
  echo "===== IMAGENS E DIGESTS ====="
  docker images --digests 2>/dev/null || true
} | tee "$OUT"

echo "Ambiente salvo em $OUT"
