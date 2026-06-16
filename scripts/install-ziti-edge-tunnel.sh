#!/usr/bin/env bash
set -euo pipefail

for command in curl jq unzip; do
  command -v "$command" >/dev/null || {
    echo "Instale o comando ausente: $command" >&2
    exit 1
  }
done

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ASSET='ziti-edge-tunnel-Linux_x86_64.zip' ;;
  aarch64|arm64) ASSET='ziti-edge-tunnel-Linux_arm64.zip' ;;
  *) echo "Arquitetura não contemplada automaticamente: $ARCH" >&2; exit 1 ;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
URL="$(curl -fsSL https://api.github.com/repos/openziti/ziti-tunnel-sdk-c/releases/latest \
  | jq -r --arg asset "$ASSET" '.assets[] | select(.name == $asset) | .browser_download_url' \
  | head -n1)"

if [[ -z "$URL" || "$URL" == "null" ]]; then
  echo "Não foi possível localizar o artefato $ASSET na versão mais recente." >&2
  exit 1
fi

curl -fL "$URL" -o "$TMP/ziti-edge-tunnel.zip"
unzip -q "$TMP/ziti-edge-tunnel.zip" -d "$TMP"
BIN="$(find "$TMP" -type f -name ziti-edge-tunnel | head -n1)"
[[ -n "$BIN" ]] || { echo "Binário não encontrado no arquivo baixado." >&2; exit 1; }

sudo install -o root -g root -m 0755 "$BIN" /usr/local/bin/ziti-edge-tunnel
sudo groupadd --system ziti 2>/dev/null || true
sudo mkdir -p /opt/openziti/etc/identities
sudo chown -R root:ziti /opt/openziti/etc/identities
sudo chmod -R ug=rwX,o-rwx /opt/openziti/etc/identities

ziti-edge-tunnel version || true
echo "ziti-edge-tunnel instalado em /usr/local/bin."
