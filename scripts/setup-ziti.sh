#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE=(docker compose -f "$ROOT/compose.yml")
ZITI_USER="${ZITI_USER:-admin}"
ZITI_PWD="${ZITI_PWD:-admin}"
mkdir -p "$ROOT/identities"

ziti() {
  "${COMPOSE[@]}" exec -T quickstart ziti "$@"
}

write_in_container() {
  "${COMPOSE[@]}" exec -T quickstart bash -lc "$1"
}

echo "Entrando no controlador OpenZiti..."
ziti edge login ziti-controller:1280 -u "$ZITI_USER" -p "$ZITI_PWD" -y

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
printf '%s\n' "Configuração concluída." \
  "Tokens salvos em identities/." \
  "A identidade wallet-user começa sem acesso." \
  "O serviço api-b não possui política Dial para wallet-user."
