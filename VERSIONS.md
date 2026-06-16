# Versões fixadas no pacote

- OpenZiti controller/CLI: `2.0.0`
- OpenZiti ziti-host: `1.17.1`
- Nginx: `1.27-alpine`
- Hardhat: `2.26.3`
- ethers: `6.14.4`
- solc-js: `0.8.30`

A imagem `grafana/k6:latest` e o binário `ziti-edge-tunnel` baixado pelo instalador devem ter suas versões e digests registrados no dia do experimento por `scripts/record-environment.sh`. Para congelamento total, substitua `latest` por uma tag testada e registre o digest retornado por `docker image inspect`.

As dependências Node são exclusivamente de desenvolvimento e laboratório. Não reutilize as chaves, contas ou serviços Hardhat em redes reais.
