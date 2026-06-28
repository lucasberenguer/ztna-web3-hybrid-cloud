#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

ZITI_USER="${ZITI_USER:-admin}"
ZITI_PWD="${ZITI_PWD:-ztna-lab-2026}"
ZITI_CTRL="${ZITI_CTRL:-quickstart:1280}"
COMPOSE=(docker compose --env-file "$ENV_FILE" -f "$ROOT/compose.yml")
mkdir -p "$ROOT/identities"

ziti() {
  "${COMPOSE[@]}" exec -T quickstart ziti "$@"
}

write_in_container() {
  "${COMPOSE[@]}" exec -T quickstart bash -lc "$1"
}

login_controller() {
  local attempt max_attempts=30
  echo "Entrando no controlador OpenZiti como '$ZITI_USER'..."
  for attempt in $(seq 1 "$max_attempts"); do
    if ziti edge login "$ZITI_CTRL" \
      -u "$ZITI_USER" \
      -p "$ZITI_PWD" \
      -y >/tmp/ziti-login.out 2>&1; then
      cat /tmp/ziti-login.out
      rm -f /tmp/ziti-login.out
      echo "Login administrativo confirmado."
      return 0
    fi

    printf '\rAguardando API administrativa aceitar credenciais... %02d/%02d' \
      "$attempt" "$max_attempts"
    sleep 2
  done

  printf '\n'
  cat /tmp/ziti-login.out >&2 || true
  rm -f /tmp/ziti-login.out
  echo >&2
  echo "Falha no login administrativo após $max_attempts tentativas." >&2
  echo "Controlador esperado: $ZITI_CTRL" >&2
  echo "Usuário esperado: $ZITI_USER" >&2
  echo "Confira os logs com:" >&2
  echo "  docker compose --env-file '$ENV_FILE' -f '$ROOT/compose.yml' logs --tail=100 quickstart" >&2
  return 1
}

login_controller

echo "Criando identidades de laboratório..."
write_in_container "ziti edge create identity ziti-host -a hosts -o /home/ziggy/ziti-host.jwt"
write_in_container "ziti edge create identity wallet-user -a wallet-revoked -o /home/ziggy/wallet-user.jwt"

echo "Criando configurações dos serviços..."
ziti edge create config api-a.intercept intercept.v1 \
  '{"protocols":["tcp"],"addresses":["198.18.0.10"],"portRanges":[{"low":8080,"high":8080}]}'
ziti edge create config api-a.host host.v1 \
  '{"protocol":"tcp","address":"api-a","port":80}'
ziti edge create service api-a --configs api-a.intercept,api-a.host

ziti edge create config api-b.intercept intercept.v1 \
  '{"protocols":["tcp"],"addresses":["198.18.0.11"],"portRanges":[{"low":8080,"high":8080}]}'
ziti edge create config api-b.host host.v1 \
  '{"protocol":"tcp","address":"api-b","port":80}'
ziti edge create service api-b --configs api-b.intercept,api-b.host

echo "Criando políticas de mínimo privilégio..."
ziti edge create service-policy api-a.bind Bind --identity-roles '#hosts' --service-roles '@api-a'
ziti edge create service-policy api-b.bind Bind --identity-roles '#hosts' --service-roles '@api-b'
ziti edge create service-policy api-a.wallet.dial Dial --identity-roles '#wallet-allowed' --service-roles '@api-a'

"${COMPOSE[@]}" cp quickstart:/home/ziggy/ziti-host.jwt "$ROOT/identities/ziti-host.jwt"
"${COMPOSE[@]}" cp quickstart:/home/ziggy/wallet-user.jwt "$ROOT/identities/wallet-user.jwt"
chmod 600 "$ROOT/identities/"*.jwt

echo
printf '%s\n' \
  "Configuração concluída." \
  "Tokens salvos em identities/." \
  "A identidade wallet-user começa sem acesso." \
  "O serviço api-b não possui política Dial para wallet-user."
