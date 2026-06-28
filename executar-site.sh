#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT/.env"
RESULTS="$ROOT/results"
LOG="$RESULTS/site-$(date +%Y%m%d-%H%M%S).log"
RESET_LAB="${RESET_LAB:-1}"
KEEP_RUNNING="${KEEP_RUNNING:-0}"
NO_BROWSER="${NO_BROWSER:-0}"
SITE_PORT="${SITE_PORT:-5050}"

mkdir -p "$RESULTS"
exec > >(tee -a "$LOG") 2>&1

if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

COMPOSE=(docker compose --env-file "$ENV_FILE")
HARDHAT_PID=""
TUNNEL_PID=""
SERVER_PID=""

if [[ -t 1 ]]; then
  BOLD='\033[1m'; DIM='\033[2m'; RED='\033[31m'; GREEN='\033[32m'
  YELLOW='\033[33m'; BLUE='\033[34m'; CYAN='\033[36m'; RESET='\033[0m'
else
  BOLD=''; DIM=''; RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; RESET=''
fi

if [[ "$(id -u)" -eq 0 ]]; then
  SUDO=()
else
  SUDO=(sudo)
fi

ok() { printf '%b\n' "${GREEN}[OK]${RESET} $*"; }
warn() { printf '%b\n' "${YELLOW}[AVISO]${RESET} $*"; }
fail() { printf '%b\n' "${RED}[FALHA]${RESET} $*" >&2; exit 1; }
step() {
  printf '\n%b\n' "${BOLD}${BLUE}$1${RESET}"
  printf '%b\n' "${DIM}----------------------------------------------------------------${RESET}"
}

cleanup() {
  local status=$?
  set +e
  printf '\n%b\n' "${DIM}Encerrando os processos do site...${RESET}"
  [[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" 2>/dev/null || true
  [[ -n "$HARDHAT_PID" ]] && kill "$HARDHAT_PID" 2>/dev/null || true
  [[ -n "$TUNNEL_PID" ]] && "${SUDO[@]}" kill "$TUNNEL_PID" 2>/dev/null || true

  if [[ "$KEEP_RUNNING" != "1" ]]; then
    "${COMPOSE[@]}" -f "$ROOT/compose.yml" -f "$ROOT/compose.lab.yml" down --remove-orphans >/dev/null 2>&1 || true
  else
    warn "KEEP_RUNNING=1: contêineres mantidos ativos."
  fi

  if [[ "$status" -ne 0 ]]; then
    printf '%b\n' "${RED}A inicialização falhou. Consulte: $LOG${RESET}"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

wait_health() {
  local i container status
  for i in $(seq 1 60); do
    container="$("${COMPOSE[@]}" -f "$ROOT/compose.yml" ps -q quickstart 2>/dev/null || true)"
    status=""
    if [[ -n "$container" ]]; then
      status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container" 2>/dev/null || true)"
    fi
    if [[ "$status" == "healthy" ]]; then
      printf '\n'
      ok "Controlador OpenZiti saudável."
      return 0
    fi
    printf '\rAguardando OpenZiti... %02d/60 (%s)' "$i" "${status:-iniciando}"
    sleep 2
  done
  printf '\n'
  fail "O controlador OpenZiti não ficou saudável."
}

wait_http() {
  local url="$1" label="$2" i
  for i in $(seq 1 40); do
    if curl -fsS --max-time 2 "$url" >/dev/null 2>&1; then
      printf '\n'
      ok "$label"
      return 0
    fi
    printf '\rAguardando %s... %02d/40' "$label" "$i"
    sleep 1
  done
  printf '\n'
  fail "$label não respondeu."
}

wait_rpc() {
  local i response
  for i in $(seq 1 40); do
    response="$(curl -sS --max-time 2 -H 'Content-Type: application/json' \
      --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
      http://127.0.0.1:8545 2>/dev/null || true)"
    if [[ "$response" == *'"result"'* ]]; then
      printf '\n'
      ok "Blockchain local respondendo."
      return 0
    fi
    printf '\rAguardando blockchain... %02d/40' "$i"
    sleep 1
  done
  printf '\n'
  tail -n 50 "$RESULTS/hardhat-site.log" 2>/dev/null || true
  fail "A blockchain local não iniciou."
}

wait_tunnel() {
  local i
  for i in $(seq 1 45); do
    if [[ -n "$TUNNEL_PID" ]] && ! "${SUDO[@]}" kill -0 "$TUNNEL_PID" 2>/dev/null; then
      printf '\n'
      tail -n 80 "$RESULTS/ziti-tunnel-site.log" 2>/dev/null || true
      fail "O cliente ZTNA foi encerrado durante a inicialização."
    fi
    if grep -Eqi 'connected|controller|tunneler|service' "$RESULTS/ziti-tunnel-site.log" 2>/dev/null; then
      printf '\n'
      ok "Cliente ZTNA em execução."
      return 0
    fi
    printf '\rAguardando cliente ZTNA... %02d/45' "$i"
    sleep 1
  done
  printf '\n'
  warn "O log não confirmou o túnel; o site fará as verificações funcionais."
}

printf '\n%b\n' "${BOLD}${CYAN}================================================================${RESET}"
printf '%b\n' "${BOLD}${CYAN}  PAINEL ZTNA + WEB3${RESET}"
printf '%b\n' "${BOLD}${CYAN}================================================================${RESET}"
printf 'Log de inicialização: %s\n' "$LOG"

step "[1/7] Verificando requisitos"
for command in docker node npm python3 curl; do
  command -v "$command" >/dev/null || fail "Comando ausente: $command"
  printf '  %-18s %b\n' "$command" "${GREEN}encontrado${RESET}"
done
docker info >/dev/null 2>&1 || fail "O Docker daemon não está acessível."
docker compose version >/dev/null 2>&1 || fail "Docker Compose não está disponível."

if [[ "$(id -u)" -ne 0 ]]; then
  command -v sudo >/dev/null || fail "O comando sudo é necessário para o túnel ZTNA."
  sudo -v
fi
if [[ ! -e /dev/net/tun ]]; then
  "${SUDO[@]}" modprobe tun 2>/dev/null || true
fi
[[ -e /dev/net/tun ]] || fail "/dev/net/tun não está disponível."

step "[2/7] Preparando dependências"
npm --prefix "$ROOT/blockchain" ci --silent

if [[ "$RESET_LAB" == "1" ]]; then
  "${COMPOSE[@]}" -f "$ROOT/compose.yml" -f "$ROOT/compose.lab.yml" down -v --remove-orphans >/dev/null 2>&1 || true
  rm -f "$ROOT/identities/"*.jwt "$ROOT/blockchain/deployment.json"
  "${SUDO[@]}" rm -f /opt/openziti/etc/identities/wallet-user.json 2>/dev/null || true
fi

step "[3/7] Iniciando OpenZiti"
"${COMPOSE[@]}" -f "$ROOT/compose.yml" up -d
wait_health
"$ROOT/scripts/setup-ziti.sh"

step "[4/7] Iniciando APIs"
export ZITI_ENROLL_TOKEN
ZITI_ENROLL_TOKEN="$(cat "$ROOT/identities/ziti-host.jwt")"
"${COMPOSE[@]}" -f "$ROOT/compose.yml" -f "$ROOT/compose.lab.yml" up -d
wait_http "http://127.0.0.1:8081/" "API A"
wait_http "http://127.0.0.1:8082/" "API B"

step "[5/7] Preparando cliente ZTNA"
if ! command -v ziti-edge-tunnel >/dev/null; then
  "$ROOT/scripts/install-ziti-edge-tunnel.sh"
fi
if ! grep -Eq '(^|[[:space:]])quickstart([[:space:]]|$)' /etc/hosts; then
  printf '127.0.0.1 quickstart\n' | "${SUDO[@]}" tee -a /etc/hosts >/dev/null
fi
"${SUDO[@]}" mkdir -p /opt/openziti/etc/identities
"${SUDO[@]}" rm -f /opt/openziti/etc/identities/wallet-user.json
"${SUDO[@]}" ziti-edge-tunnel enroll \
  --jwt "$ROOT/identities/wallet-user.jwt" \
  --identity /opt/openziti/etc/identities/wallet-user.json

: > "$RESULTS/ziti-tunnel-site.log"
"${SUDO[@]}" ziti-edge-tunnel run \
  --identity-dir /opt/openziti/etc/identities \
  > "$RESULTS/ziti-tunnel-site.log" 2>&1 &
TUNNEL_PID=$!
wait_tunnel
sleep 2

step "[6/7] Iniciando blockchain"
: > "$RESULTS/hardhat-site.log"
npm --prefix "$ROOT/blockchain" run node > "$RESULTS/hardhat-site.log" 2>&1 &
HARDHAT_PID=$!
wait_rpc
npm --prefix "$ROOT/blockchain" run deploy --silent
npm --prefix "$ROOT/blockchain" run revoke --silent
npm --prefix "$ROOT/blockchain" run sync --silent

step "[7/7] Iniciando site"
export ZITI_TUNNEL_PID="$TUNNEL_PID"
export HARDHAT_PID="$HARDHAT_PID"
export SITE_PORT
python3 "$ROOT/visual/server.py" > "$RESULTS/site-server.log" 2>&1 &
SERVER_PID=$!

wait_http "http://127.0.0.1:${SITE_PORT}/api/health" "Site"

URL="http://127.0.0.1:${SITE_PORT}"
printf '\n%b\n' "${BOLD}${GREEN}SITE DISPONÍVEL: $URL${RESET}"
printf 'Pressione Ctrl+C neste terminal para encerrar.\n\n'

if [[ "$NO_BROWSER" != "1" ]]; then
  if command -v xdg-open >/dev/null; then
    xdg-open "$URL" >/dev/null 2>&1 || true
  elif command -v gio >/dev/null; then
    gio open "$URL" >/dev/null 2>&1 || true
  else
    warn "Abra manualmente no navegador: $URL"
  fi
fi

wait "$SERVER_PID"
