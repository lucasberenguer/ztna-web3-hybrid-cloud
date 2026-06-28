#!/usr/bin/env python3
from __future__ import annotations

import concurrent.futures
import copy
import http.client
import json
import math
import os
import re
import socket
import statistics
import subprocess
import threading
import time
from datetime import datetime
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
STATIC = ROOT / "visual" / "static"
BLOCKCHAIN = ROOT / "blockchain"
RESULTS = ROOT / "results"
ENV_FILE = ROOT / ".env"
HOST = os.environ.get("VISUAL_HOST", "127.0.0.1")
PORT = int(os.environ.get("SITE_PORT", "5050"))
ACTION_DELAY = float(os.environ.get("ACTION_DELAY", "1.0"))
TUNNEL_PID = int(os.environ.get("ZITI_TUNNEL_PID", "0") or 0)
HARDHAT_PID = int(os.environ.get("HARDHAT_PID", "0") or 0)

RESULTS.mkdir(parents=True, exist_ok=True)


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def load_env_file() -> dict[str, str]:
    result: dict[str, str] = {}
    if not ENV_FILE.exists():
        return result
    for raw in ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        result[key.strip()] = value.strip().strip('"').strip("'")
    return result


PROCESS_ENV = os.environ.copy()
PROCESS_ENV.update(load_env_file())

INITIAL_STATE: dict[str, Any] = {
    "updatedAt": now_iso(),
    "busy": False,
    "activeAction": None,
    "phase": "ready",
    "headline": "Ambiente ZTNA + Web3 pronto",
    "message": "Selecione uma operação no painel de controle.",
    "mode": "idle",
    "wallet": {
        "address": "—",
        "authorized": False,
        "role": "wallet-revoked",
    },
    "blockchain": {
        "online": False,
        "contract": "—",
        "lastTx": "—",
        "block": "—",
        "latencyMs": None,
    },
    "components": {
        "controller": "checking",
        "tunnel": "checking",
        "blockchain": "checking",
        "apiA": "checking",
        "apiB": "checking",
    },
    "access": {
        "baselineA": "unknown",
        "baselineB": "unknown",
        "ztnaA": "unknown",
        "ztnaB": "unknown",
    },
    "metrics": {
        "baseline": None,
        "ztna": None,
        "dockerCpu": None,
        "dockerMemoryMb": None,
        "containers": 0,
    },
    "timeline": [],
    "error": None,
}

STATE = copy.deepcopy(INITIAL_STATE)
LOCK = threading.RLock()


def add_event(kind: str, title: str, detail: str = "") -> None:
    with LOCK:
        STATE["timeline"].append(
            {
                "id": f"{time.time_ns()}",
                "time": datetime.now().strftime("%H:%M:%S"),
                "kind": kind,
                "title": title,
                "detail": detail,
            }
        )
        STATE["timeline"] = STATE["timeline"][-80:]
        STATE["updatedAt"] = now_iso()
        event_record = STATE["timeline"][-1]
    try:
        with (RESULTS / "site-events.jsonl").open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(event_record, ensure_ascii=False) + "\n")
    except OSError:
        pass


def update_state(**values: Any) -> None:
    with LOCK:
        for key, value in values.items():
            STATE[key] = value
        STATE["updatedAt"] = now_iso()


def update_nested(section: str, **values: Any) -> None:
    with LOCK:
        STATE[section].update(values)
        STATE["updatedAt"] = now_iso()


def snapshot() -> dict[str, Any]:
    with LOCK:
        return copy.deepcopy(STATE)


def run_command(
    args: list[str],
    *,
    cwd: Path = ROOT,
    timeout: float = 60,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        args,
        cwd=str(cwd),
        env=PROCESS_ENV,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )
    if check and result.returncode != 0:
        raise RuntimeError(
            f"Comando falhou ({result.returncode}): {' '.join(args)}\n"
            f"{result.stderr.strip() or result.stdout.strip()}"
        )
    return result


def parse_json_output(text: str) -> dict[str, Any]:
    text = text.strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", text, re.DOTALL)
        if not match:
            raise RuntimeError(f"Resposta JSON não encontrada em: {text[-500:]}")
        return json.loads(match.group(0))


def node_script(script: str, *args: str, timeout: float = 60) -> dict[str, Any] | None:
    result = run_command(["node", f"scripts/{script}", *args], cwd=BLOCKCHAIN, timeout=timeout)
    if not result.stdout.strip():
        return None
    try:
        return parse_json_output(result.stdout)
    except Exception:
        return {"raw": result.stdout.strip()}


def process_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def port_open(host: str, port: int, timeout: float = 0.6) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def rpc_online() -> bool:
    try:
        conn = http.client.HTTPConnection("127.0.0.1", 8545, timeout=1.2)
        body = json.dumps({"jsonrpc": "2.0", "method": "eth_chainId", "params": [], "id": 1})
        conn.request("POST", "/", body=body, headers={"Content-Type": "application/json"})
        response = conn.getresponse()
        payload = response.read()
        conn.close()
        return response.status == 200 and b"result" in payload
    except OSError:
        return False


def http_probe(url: str, timeout: float = 3.0) -> dict[str, Any]:
    parsed = urlsplit(url)
    start = time.perf_counter()
    status = 0
    body = ""
    error = None
    try:
        conn = http.client.HTTPConnection(parsed.hostname, parsed.port or 80, timeout=timeout)
        path = parsed.path or "/"
        if parsed.query:
            path += f"?{parsed.query}"
        conn.request("GET", path, headers={"Connection": "close"})
        response = conn.getresponse()
        status = response.status
        body = response.read(4096).decode("utf-8", errors="replace")
        conn.close()
    except Exception as exc:
        error = str(exc)
    elapsed = round((time.perf_counter() - start) * 1000, 2)
    return {
        "ok": status == 200,
        "status": status,
        "latencyMs": elapsed,
        "body": re.sub(r"\s+", " ", body).strip()[:180],
        "error": error,
    }


def apply_access_result(key: str, result: dict[str, Any]) -> None:
    update_nested("access", **{key: "allowed" if result["ok"] else "blocked"})


def record_tx(data: dict[str, Any], authorized: bool) -> None:
    update_nested(
        "wallet",
        address=data.get("wallet", STATE["wallet"]["address"]),
        authorized=authorized,
        role="wallet-allowed" if authorized else "wallet-revoked",
    )
    update_nested(
        "blockchain",
        lastTx=data.get("transactionHash", "—"),
        block=data.get("blockNumber", "—"),
    )


def set_access(authorized: bool) -> dict[str, Any]:
    action = "allow" if authorized else "revoke"
    started = time.perf_counter()
    data = node_script("set-access.js", action, timeout=45) or {}
    blockchain_ms = round((time.perf_counter() - started) * 1000, 2)
    record_tx(data, authorized)
    update_nested("blockchain", latencyMs=blockchain_ms)
    add_event(
        "success" if authorized else "warning",
        "Permissão registrada na blockchain" if authorized else "Revogação registrada na blockchain",
        f"Bloco {data.get('blockNumber', '—')} · {blockchain_ms:.0f} ms",
    )

    sync_started = time.perf_counter()
    sync_data = node_script("sync-ziti.js", "--once", timeout=45) or {}
    sync_ms = round((time.perf_counter() - sync_started) * 1000, 2)
    role = sync_data.get("role", "wallet-allowed" if authorized else "wallet-revoked")
    update_nested("wallet", role=role)
    add_event("info", "Política ZTNA atualizada", f"Função {role} aplicada em {sync_ms:.0f} ms")
    return data


def check_baseline() -> None:
    update_state(
        mode="baseline",
        phase="running",
        headline="Cenário tradicional: confiança baseada na rede",
        message="O cliente alcança diretamente as duas APIs publicadas por portas locais.",
    )
    add_event("info", "Teste do modelo tradicional iniciado", "Verificando as portas 8081 e 8082")
    a = http_probe("http://127.0.0.1:8081/")
    b = http_probe("http://127.0.0.1:8082/")
    apply_access_result("baselineA", a)
    apply_access_result("baselineB", b)
    add_event("danger" if a["ok"] and b["ok"] else "warning", "APIs alcançáveis diretamente", f"API A: HTTP {a['status'] or 'bloqueada'} · API B: HTTP {b['status'] or 'bloqueada'}")
    update_state(phase="done", headline="Verificação do baseline concluída", message="As duas APIs estavam acessíveis após a entrada na rede.")


def authorize_access() -> None:
    update_state(
        mode="authorized",
        phase="running",
        headline="Carteira autorizada: acesso mínimo necessário",
        message="A blockchain concede a função que permite somente a API A.",
    )
    set_access(True)
    time.sleep(ACTION_DELAY)
    a = http_probe("http://198.18.0.10:8080/", timeout=5)
    b = http_probe("http://198.18.0.11:8080/", timeout=3)
    apply_access_result("ztnaA", a)
    apply_access_result("ztnaB", b)
    if a["ok"]:
        add_event("success", "API A liberada pelo ZTNA", f"HTTP 200 em {a['latencyMs']:.1f} ms")
    else:
        raise RuntimeError(f"A API A deveria estar acessível, mas falhou: {a['error'] or a['status']}")
    if not b["ok"]:
        add_event("success", "Movimento lateral bloqueado", "A carteira não possui política Dial para a API B")
    else:
        raise RuntimeError("A API B deveria estar bloqueada, mas respondeu HTTP 200.")
    update_state(phase="done", headline="Privilégio mínimo aplicado", message="API A permitida; API B permaneceu invisível para a mesma identidade.")


def revoke_access() -> None:
    update_state(
        mode="revoked",
        phase="running",
        headline="Carteira revogada: acesso removido",
        message="A mudança registrada na blockchain é sincronizada com a política ZTNA.",
    )
    set_access(False)
    time.sleep(ACTION_DELAY)
    a = http_probe("http://198.18.0.10:8080/", timeout=3)
    b = http_probe("http://198.18.0.11:8080/", timeout=3)
    apply_access_result("ztnaA", a)
    apply_access_result("ztnaB", b)
    if not a["ok"]:
        add_event("success", "Acesso removido após revogação", f"Conexão bloqueada em {a['latencyMs']:.1f} ms")
    else:
        raise RuntimeError("A API A continuou acessível após a revogação.")
    update_state(phase="done", headline="Revogação concluída", message="A carteira revogada não consegue mais alcançar a API protegida.")


def run_full_flow() -> None:
    update_state(
        mode="intro",
        phase="running",
        headline="Fluxo completo iniciado",
        message="Comparando perímetro tradicional com ZTNA integrado à blockchain.",
    )
    add_event("info", "Fluxo completo", "Início da sequência de verificações")
    time.sleep(ACTION_DELAY)
    check_baseline()
    time.sleep(ACTION_DELAY)
    revoke_access()
    time.sleep(ACTION_DELAY)
    authorize_access()
    time.sleep(ACTION_DELAY * 1.5)
    revoke_access()
    update_state(
        mode="complete",
        phase="done",
        headline="Fluxo completo concluído",
        message="O ZTNA aplicou verificação explícita, privilégio mínimo e revogação dinâmica.",
    )
    add_event("success", "Fluxo finalizado", "Todos os controles funcionaram como esperado")


def percentile(values: list[float], percentage: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = max(0, min(len(ordered) - 1, math.ceil((percentage / 100) * len(ordered)) - 1))
    return ordered[index]


def benchmark_url(url: str, requests: int = 40, workers: int = 5) -> dict[str, Any]:
    started = time.perf_counter()
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        futures = [executor.submit(http_probe, url, 5.0) for _ in range(requests)]
        results = [future.result() for future in concurrent.futures.as_completed(futures)]
    total = time.perf_counter() - started
    successes = [item for item in results if item["ok"]]
    latencies = [float(item["latencyMs"]) for item in successes]
    return {
        "requests": requests,
        "success": len(successes),
        "successRate": round((len(successes) / requests) * 100, 1),
        "avgMs": round(statistics.fmean(latencies), 2) if latencies else None,
        "p95Ms": round(percentile(latencies, 95), 2) if latencies else None,
        "rps": round(requests / total, 2) if total else 0,
    }


def quick_benchmark() -> None:
    update_state(
        mode="benchmark",
        phase="running",
        headline="Teste de desempenho",
        message="Executando 40 requisições com 5 trabalhadores em cada cenário.",
    )
    add_event("info", "Benchmark iniciado", "Baseline: 40 requisições concorrentes")
    baseline = benchmark_url("http://127.0.0.1:8081/")
    update_nested("metrics", baseline=baseline)
    add_event("info", "Baseline medido", f"p95 {baseline.get('p95Ms')} ms · {baseline.get('rps')} req/s")

    set_access(True)
    time.sleep(ACTION_DELAY)
    add_event("info", "Medição ZTNA iniciada", "Mesma carga aplicada à API protegida")
    ztna = benchmark_url("http://198.18.0.10:8080/")
    update_nested("metrics", ztna=ztna)
    add_event("success", "ZTNA medido", f"p95 {ztna.get('p95Ms')} ms · {ztna.get('rps')} req/s")
    update_state(phase="done", headline="Benchmark concluído", message="Medição local concluída para os dois caminhos de acesso.")


def initialize_state() -> None:
    deployment_file = BLOCKCHAIN / "deployment.json"
    if deployment_file.exists():
        try:
            deployment = json.loads(deployment_file.read_text(encoding="utf-8"))
            update_nested(
                "wallet",
                address=deployment.get("testWallet", "—"),
            )
            update_nested(
                "blockchain",
                contract=deployment.get("contractAddress", "—"),
            )
        except Exception:
            pass

    if rpc_online():
        update_nested("blockchain", online=True)
        try:
            status = node_script("status.js", timeout=10) or {}
            authorized = bool(status.get("authorized", False))
            update_nested(
                "wallet",
                address=status.get("wallet", STATE["wallet"]["address"]),
                authorized=authorized,
                role="wallet-allowed" if authorized else "wallet-revoked",
            )
        except Exception:
            pass
    add_event("info", "Site iniciado", "Serviços locais conectados")


def component_monitor() -> None:
    while True:
        components = {
            "controller": "online" if port_open("127.0.0.1", 1280) else "offline",
            "tunnel": "online" if process_alive(TUNNEL_PID) else "offline",
            "blockchain": "online" if rpc_online() else "offline",
            "apiA": "online" if http_probe("http://127.0.0.1:8081/", 1)["ok"] else "offline",
            "apiB": "online" if http_probe("http://127.0.0.1:8082/", 1)["ok"] else "offline",
        }
        update_state(components=components)
        update_nested("blockchain", online=components["blockchain"] == "online")

        try:
            stats = run_command(
                [
                    "docker",
                    "stats",
                    "--no-stream",
                    "--format",
                    "{{.CPUPerc}}|{{.MemUsage}}",
                ],
                timeout=8,
                check=False,
            )
            cpu_total = 0.0
            mem_total = 0.0
            containers = 0
            for line in stats.stdout.splitlines():
                if "|" not in line:
                    continue
                cpu, memory = line.split("|", 1)
                try:
                    cpu_total += float(cpu.strip().rstrip("%"))
                except ValueError:
                    pass
                current = memory.split("/", 1)[0].strip()
                match = re.match(r"([0-9.]+)([KMG]i?B)", current, re.I)
                if match:
                    value = float(match.group(1))
                    unit = match.group(2).lower()
                    if unit.startswith("g"):
                        value *= 1024
                    elif unit.startswith("k"):
                        value /= 1024
                    mem_total += value
                containers += 1
            update_nested(
                "metrics",
                dockerCpu=round(cpu_total, 2),
                dockerMemoryMb=round(mem_total, 1),
                containers=containers,
            )
        except Exception:
            pass
        time.sleep(3)


ACTIONS = {
    "baseline": check_baseline,
    "authorize": authorize_access,
    "revoke": revoke_access,
    "full-run": run_full_flow,
    "benchmark": quick_benchmark,
}


def launch_action(name: str) -> tuple[bool, str]:
    with LOCK:
        if STATE["busy"]:
            return False, f"Já existe uma ação em execução: {STATE['activeAction']}"
        STATE["busy"] = True
        STATE["activeAction"] = name
        STATE["error"] = None
        STATE["updatedAt"] = now_iso()

    def worker() -> None:
        try:
            ACTIONS[name]()
        except Exception as exc:
            update_state(
                phase="error",
                headline="Falha durante a execução",
                message=str(exc),
                error=str(exc),
            )
            add_event("danger", "Erro", str(exc).splitlines()[-1][:240])
        finally:
            with LOCK:
                STATE["busy"] = False
                STATE["activeAction"] = None
                STATE["updatedAt"] = now_iso()

    threading.Thread(target=worker, daemon=True, name=f"action-{name}").start()
    return True, "Ação iniciada"


class DashboardHandler(SimpleHTTPRequestHandler):
    server_version = "ZTNAPanel/1.0"

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, directory=str(STATIC), **kwargs)

    def log_message(self, fmt: str, *args: Any) -> None:
        return

    def send_json(self, payload: Any, status: int = 200) -> None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:
        if self.path == "/api/state":
            self.send_json(snapshot())
            return
        if self.path == "/api/health":
            self.send_json({"ok": True, "time": now_iso()})
            return
        super().do_GET()

    def do_POST(self) -> None:
        if self.path.startswith("/api/action/"):
            name = self.path.rsplit("/", 1)[-1]
            if name == "clear":
                with LOCK:
                    STATE["timeline"] = []
                    STATE["error"] = None
                    STATE["updatedAt"] = now_iso()
                self.send_json({"ok": True})
                return
            if name not in ACTIONS:
                self.send_json({"ok": False, "error": "Ação desconhecida"}, HTTPStatus.NOT_FOUND)
                return
            ok, message = launch_action(name)
            self.send_json({"ok": ok, "message": message}, 202 if ok else 409)
            return
        self.send_json({"ok": False, "error": "Endpoint desconhecido"}, HTTPStatus.NOT_FOUND)


def main() -> None:
    initialize_state()
    threading.Thread(target=component_monitor, daemon=True, name="component-monitor").start()
    server = ThreadingHTTPServer((HOST, PORT), DashboardHandler)
    print(f"Site disponível em http://{HOST}:{PORT}", flush=True)
    print("Pressione Ctrl+C para encerrar o painel.", flush=True)
    try:
        server.serve_forever(poll_interval=0.3)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
