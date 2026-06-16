#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$ROOT/results/security-tests.txt"
mkdir -p "$ROOT/results"

ok() { printf '[OK] %s\n' "$*" | tee -a "$LOG"; }
fail() { printf '[FALHA] %s\n' "$*" | tee -a "$LOG"; exit 1; }
expect_success() {
  local label="$1" url="$2"
  if curl -fsS --max-time 5 "$url" >/dev/null; then ok "$label"; else fail "$label"; fi
}
expect_block() {
  local label="$1" url="$2"
  if curl -fsS --max-time 3 "$url" >/dev/null 2>&1; then fail "$label"; else ok "$label"; fi
}

: > "$LOG"
echo "Execução: $(date -Iseconds)" | tee -a "$LOG"

expect_success "Baseline expõe API A" "http://127.0.0.1:8081/"
expect_success "Baseline expõe API B" "http://127.0.0.1:8082/"

npm --prefix "$ROOT/blockchain" run revoke >/dev/null
npm --prefix "$ROOT/blockchain" run sync >/dev/null
sleep 2
expect_block "ZTNA bloqueia identidade revogada na API A" "http://198.18.0.10:8080/"

npm --prefix "$ROOT/blockchain" run allow >/dev/null
npm --prefix "$ROOT/blockchain" run sync >/dev/null
sleep 2
expect_success "ZTNA permite carteira autorizada na API A" "http://198.18.0.10:8080/"
expect_block "Microssegmentação bloqueia movimento lateral para API B" "http://198.18.0.11:8080/"

npm --prefix "$ROOT/blockchain" run revoke >/dev/null
npm --prefix "$ROOT/blockchain" run sync >/dev/null
sleep 2
expect_block "Revogação em blockchain remove acesso à API A" "http://198.18.0.10:8080/"

ok "Todos os cenários de segurança produziram o comportamento esperado"
