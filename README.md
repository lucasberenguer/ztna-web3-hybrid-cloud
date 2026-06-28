# Painel ZTNA + Web3

Aplicação local para controle de acesso com OpenZiti, blockchain Hardhat e duas APIs em contêineres.

## Requisitos

- Linux x86-64
- Docker Engine e Docker Compose V2
- Node.js e npm
- Python 3
- curl
- sudo
- dispositivo `/dev/net/tun`

## Execução

Na pasta do projeto, execute:

```bash
chmod +x executar-site.sh scripts/*.sh
./executar-site.sh
```

O site será aberto em `http://127.0.0.1:5050`.

Para encerrar o site e os serviços, pressione `Ctrl+C` no terminal.

## Opções

Executar sem abrir o navegador:

```bash
NO_BROWSER=1 ./executar-site.sh
```

Manter os contêineres ativos ao fechar o site:

```bash
KEEP_RUNNING=1 ./executar-site.sh
```

Usar outra porta:

```bash
SITE_PORT=5051 ./executar-site.sh
```

Preservar o estado existente do ambiente:

```bash
RESET_LAB=0 ./executar-site.sh
```

## Solução de problemas

Em caso de erro ou dificuldade durante a instalação ou execução, consulte o manual do projeto `MANUAL.MD` antes de realizar alterações no ambiente.
