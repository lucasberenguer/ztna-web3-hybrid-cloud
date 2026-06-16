# Manual experimental: ZTNA, Web3 e nuvem híbrida simulada

## 1. Objetivo

Este laboratório compara duas formas de acesso ao mesmo serviço:

1. **Baseline perimetral:** as APIs são publicadas diretamente em portas TCP locais. Qualquer processo com acesso à máquina pode alcançar os dois serviços.
2. **ZTNA:** as APIs continuam internamente iguais, mas o acesso externo ocorre pelo OpenZiti. A identidade de teste recebe permissão para a API A somente quando sua carteira está autorizada em um contrato inteligente local. A API B permanece bloqueada, simulando microssegmentação e privilégio mínimo.

O laboratório mede:

- exposição dos serviços no baseline;
- bloqueio de clientes sem autorização;
- acesso granular à API A;
- bloqueio de movimento lateral para a API B;
- revogação de acesso a partir do estado da blockchain;
- latência média, mediana, p95 e p99;
- requisições por segundo, falhas, CPU e memória.

> **Escopo ético:** execute apenas na sua máquina ou em infraestrutura expressamente autorizada. Os “ataques” deste manual são somente tentativas controladas de acesso aos serviços criados pelo próprio laboratório.

## 2. Limites do protótipo

A “nuvem híbrida” é simulada por redes Docker separadas na mesma máquina. Portanto, no artigo, descreva o ambiente como **nuvem híbrida simulada em contêineres**, e não como uma implantação multicloud real.

O baseline publica portas diretamente e representa confiança baseada em conectividade de rede. Ele **não é uma VPN real**. Caso o artigo afirme uma comparação específica contra VPN, adicione WireGuard/OpenVPN em uma etapa posterior ou chame este cenário de “baseline perimetral”.

A blockchain funciona como registro de autorização da carteira, enquanto um sincronizador atualiza o atributo da identidade OpenZiti. O protótipo não implementa ainda uma DID padronizada nem um desafio de assinatura de carteira. Essa limitação deve ser declarada.

## 3. Topologia do teste

- **OpenZiti quickstart:** controlador e roteador ZTNA.
- **ziti-host:** identidade que hospeda as duas APIs na rede ZTNA.
- **API A:** serviço permitido ao usuário autorizado.
- **API B:** serviço administrativo, usado para testar movimento lateral.
- **ziti-edge-tunnel:** cliente instalado no Kali/Linux.
- **Hardhat:** blockchain Ethereum local.
- **AccessRegistry:** contrato que registra se a carteira está autorizada.
- **k6:** geração de carga e coleta de métricas.

Endereços usados:

| Cenário | Serviço | Endereço |
|---|---|---|
| Baseline | API A | `http://127.0.0.1:8081/` |
| Baseline | API B | `http://127.0.0.1:8082/` |
| ZTNA | API A | `http://198.18.0.10:8080/` |
| ZTNA | API B | `http://198.18.0.11:8080/` |

A faixa `198.18.0.0/15` é usada somente no laboratório. Antes de começar, verifique se ela não é utilizada na sua rede:

```bash
ip route get 198.18.0.10
```

## 4. Requisitos

Recomendado:

- Linux/Kali x86-64;
- 4 núcleos de CPU ou mais;
- 8 GB de RAM no mínimo, preferencialmente 16 GB;
- Docker Engine e Docker Compose V2;
- Node.js e npm;
- `curl`, `jq`, `unzip`, `git` e Python 3;
- aproximadamente 5 GB livres em disco.

Instale os utilitários básicos no Kali/Debian:

```bash
sudo apt update
sudo apt install -y curl jq unzip git python3
```

Confirme as ferramentas:

```bash
docker --version
docker compose version
node --version
npm --version
```

## 5. Registrar o ambiente

Entre na pasta do laboratório e execute:

```bash
cd lab-ztna-web3
./scripts/record-environment.sh
```

O arquivo `results/environment.txt` deverá ser preservado. Ele fornece CPU, memória, GPU, sistema operacional, versões e imagens Docker para a seção de metodologia.

## 6. Iniciar o controlador ZTNA

Suba inicialmente apenas o OpenZiti:

```bash
docker compose -f compose.yml up -d
```

Verifique:

```bash
docker compose -f compose.yml ps
```

O serviço `quickstart` deve aparecer como saudável. O usuário e a senha padrão deste laboratório são `admin` e `admin`.

A console administrativa fica disponível em:

```text
https://localhost:1280/zac/
```

O certificado é local e o navegador poderá exibir um aviso.

## 7. Criar identidades, serviços e políticas

Execute uma única vez em uma rede recém-criada:

```bash
./scripts/setup-ziti.sh
```

O script cria:

- identidade `ziti-host`, com atributo `hosts`;
- identidade `wallet-user`, inicialmente com atributo `wallet-revoked`;
- serviço ZTNA `api-a`;
- serviço ZTNA `api-b`;
- política que permite ao `ziti-host` hospedar ambos;
- política que permite `wallet-user` acessar somente a API A quando receber o atributo `wallet-allowed`.

Os tokens de matrícula serão copiados para:

```text
identities/ziti-host.jwt
identities/wallet-user.jwt
```

Não publique esses arquivos. Eles são credenciais temporárias do laboratório.

## 8. Iniciar as APIs e o host ZTNA

Exporte o token do host e suba os demais contêineres:

```bash
export ZITI_ENROLL_TOKEN="$(cat identities/ziti-host.jwt)"
docker compose -f compose.yml -f compose.lab.yml up -d
```

Verifique:

```bash
docker compose -f compose.yml -f compose.lab.yml ps
```

Teste o baseline:

```bash
curl http://127.0.0.1:8081/
curl http://127.0.0.1:8082/
```

As duas requisições devem retornar conteúdo. Isso demonstra que, no baseline, um cliente com conectividade consegue alcançar os dois serviços.

## 9. Instalar e matricular o cliente OpenZiti

Instale o túnel OpenZiti:

```bash
./scripts/install-ziti-edge-tunnel.sh
```

Como o controlador e o roteador são anunciados por nomes internos, adicione os nomes ao arquivo de hosts:

```bash
grep -q 'ziti-controller' /etc/hosts || \
  echo '127.0.0.1 ziti-controller ziti-router' | sudo tee -a /etc/hosts
```

Matricule a identidade do usuário:

```bash
sudo ziti-edge-tunnel enroll \
  --jwt "$PWD/identities/wallet-user.jwt" \
  --identity /opt/openziti/etc/identities/wallet-user.json
```

Ajuste as permissões:

```bash
sudo chown -R root:ziti /opt/openziti/etc/identities
sudo chmod -R ug=rwX,o-rwx /opt/openziti/etc/identities
```

Em outro terminal, mantenha o túnel em execução:

```bash
sudo ziti-edge-tunnel run \
  --identity-dir /opt/openziti/etc/identities
```

Não feche esse terminal durante os testes.

## 10. Preparar a blockchain local

Em outro terminal:

```bash
cd lab-ztna-web3/blockchain
npm install
npm run node
```

Mantenha o Hardhat executando. Em outro terminal, implante o contrato:

```bash
cd lab-ztna-web3/blockchain
npm run deploy
npm run status
```

O arquivo `blockchain/deployment.json` armazenará o endereço do contrato, a ABI e a carteira de teste.

O estado inicial esperado é:

```json
{
  "authorized": false
}
```

## 11. Sincronizar blockchain e OpenZiti

Autorize a carteira:

```bash
cd lab-ztna-web3
npm --prefix blockchain run allow
npm --prefix blockchain run sync
```

O sincronizador consulta o contrato e troca o atributo da identidade `wallet-user` para `wallet-allowed`.

Teste:

```bash
curl --max-time 5 http://198.18.0.10:8080/
curl --max-time 3 http://198.18.0.11:8080/
```

Resultado esperado:

- API A responde, pois a carteira está autorizada;
- API B falha, pois não existe política Dial para esse serviço.

Agora revogue:

```bash
npm --prefix blockchain run revoke
npm --prefix blockchain run sync
sleep 2
curl --max-time 3 http://198.18.0.10:8080/
```

A última requisição deve falhar.

Para sincronização contínua a cada segundo, use um terminal separado:

```bash
npm --prefix blockchain run sync:watch
```

## 12. Executar os cenários de segurança

Com OpenZiti, túnel e Hardhat ativos, execute:

```bash
./tests/test-security.sh
```

O script testa automaticamente:

1. acesso às APIs A e B no baseline;
2. bloqueio da API A com carteira revogada;
3. liberação da API A após autorização;
4. bloqueio da API B, representando contenção de movimento lateral;
5. remoção do acesso à API A após revogação.

As evidências serão gravadas em:

```text
results/security-tests.txt
```

## 13. Medir o tempo de revogação

Inicie o sincronizador contínuo:

```bash
npm --prefix blockchain run sync:watch | tee results/sync-watch.log
```

Em outro terminal, autorize e confirme o acesso:

```bash
npm --prefix blockchain run allow
curl --max-time 5 http://198.18.0.10:8080/
```

Depois execute:

```bash
inicio=$(date +%s%3N)
npm --prefix blockchain run revoke >/dev/null

until ! curl -fsS --max-time 1 http://198.18.0.10:8080/ >/dev/null 2>&1; do
  sleep 0.1
done

fim=$(date +%s%3N)
echo "tempo_revogacao_ms=$((fim-inicio))" | tee -a results/revocation-times.txt
```

Repita pelo menos dez vezes. Antes de cada repetição, autorize novamente a carteira e confirme que o acesso voltou.

## 14. Teste piloto de desempenho

Primeiro autorize a carteira:

```bash
npm --prefix blockchain run allow
npm --prefix blockchain run sync
```

Execute um piloto curto:

```bash
REPETITIONS=3 DURATION=30s VUS_LEVELS="10 30" \
  ./tests/run-benchmarks.sh
```

O piloto serve para detectar erros, saturação ou falhas de configuração. Não use esses valores como resultado final se o equipamento estiver instável.

## 15. Teste final de desempenho

Use os mesmos parâmetros nos dois cenários:

```bash
REPETITIONS=10 DURATION=60s VUS_LEVELS="10 30 60" \
  ./tests/run-benchmarks.sh
```

O script executará o baseline e o ZTNA para cada combinação de usuários virtuais e repetição. Os resultados serão gravados como JSON em `results/`.

Durante os testes, colete CPU e memória em outro terminal:

```bash
INTERVAL=1 ./scripts/monitor-resources.sh
```

Interrompa o monitor com `Ctrl+C` após o benchmark.

Agregue os resultados:

```bash
python3 tests/aggregate-results.py
```

Serão produzidos:

```text
results/k6-raw.csv
results/k6-summary.csv
results/docker-stats.csv
```

## 16. Métricas que devem entrar no artigo

Para cada quantidade de usuários virtuais, apresente:

- média e desvio-padrão da latência média;
- mediana;
- p95 e p99;
- requisições por segundo;
- taxa de falha;
- média e pico de CPU;
- média e pico de memória;
- taxa de bloqueio dos acessos não autorizados;
- quantidade de serviços alcançados no movimento lateral;
- tempo médio de revogação.

Calcule a sobrecarga de latência:

```text
sobrecarga (%) = ((latência ZTNA - latência baseline) / latência baseline) × 100
```

Para os testes de segurança:

```text
taxa de bloqueio (%) = tentativas bloqueadas / tentativas não autorizadas × 100
```

## 17. Quantidade de repetições

Use:

- 3 repetições no piloto;
- no mínimo 10 repetições na avaliação final;
- idealmente 20 ou 30 repetições se houver tempo e estabilidade;
- 5 segundos de intervalo entre execuções;
- mesma carga, duração e máquina para baseline e ZTNA;
- nenhuma outra aplicação pesada aberta durante os testes.

Alterne a ordem em parte das execuções, por exemplo:

```text
baseline → ZTNA → ZTNA → baseline
```

Isso reduz o efeito de aquecimento, cache e temperatura.

## 18. Evidências recomendadas

Salve capturas ou arquivos demonstrando:

1. `docker compose ps` com os componentes ativos;
2. acesso às duas APIs no baseline;
3. bloqueio do ZTNA antes da autorização;
4. transação `allow` no Hardhat;
5. acesso permitido somente à API A;
6. tentativa bloqueada contra a API B;
7. transação de revogação;
8. bloqueio da API A após revogação;
9. resumo do k6;
10. arquivos CSV finais;
11. hardware e versões do ambiente.

## 19. Limpeza

Interrompa o túnel OpenZiti com `Ctrl+C`. Depois remova os contêineres, redes e volumes:

```bash
docker compose -f compose.yml -f compose.lab.yml down -v
```

Opcionalmente remova a identidade local:

```bash
sudo rm -f /opt/openziti/etc/identities/wallet-user.json
```

Não apague a pasta `results/` antes de copiar as evidências para o repositório do artigo.

## 20. Dados para preencher na metodologia

Depois dos testes, registre no texto:

- modelo completo da CPU e quantidade de núcleos/threads;
- memória RAM disponível;
- GPU, informando que não foi utilizada no processamento;
- sistema operacional e kernel;
- versões do Docker, Compose, Node.js, npm, OpenZiti, Hardhat, Solidity/solc e k6;
- número de contêineres e função de cada um;
- níveis de carga: 10, 30 e 60 usuários virtuais;
- duração: 60 segundos por execução;
- número de repetições;
- intervalo de sincronização blockchain–ZTNA;
- endereços e portas do laboratório;
- arquivos e commit do repositório usados na execução.
