const stateUrl = "/api/state";
let lastTimelineId = null;
let firstRender = true;

const byId = (id) => document.getElementById(id);
const architecture = byId("architecture");
const toast = byId("toast");

function shortHash(value, size = 8) {
  if (!value || value === "—") return "—";
  return value.length > size * 2 + 3
    ? `${value.slice(0, size)}…${value.slice(-size)}`
    : value;
}

function setStatusElement(id, status, customText = null) {
  const element = byId(id);
  if (!element) return;
  element.className = `node-status ${status || "neutral"}`;
  const labels = {
    online: "ONLINE",
    offline: "OFFLINE",
    checking: "VERIFICANDO",
    allowed: "PERMITIDO",
    blocked: "BLOQUEADO",
    unknown: "NÃO TESTADO",
    neutral: "SEM ESTADO",
  };
  element.textContent = customText || labels[status] || status;
}

function renderComponent(name, status) {
  const dot = byId(`dot-${name}`);
  const text = byId(`text-${name}`);
  if (dot) dot.className = `component-dot ${status}`;
  if (text) text.textContent = status === "online" ? "online" : status === "offline" ? "offline" : "verificando";
}


function setRouteCard(prefix, status, detail, active = false) {
  const card = byId(`route${prefix}`);
  const badge = byId(`route${prefix}Badge`);
  const text = byId(`route${prefix}Text`);
  if (!card || !badge || !text) return;
  const normalized = status || "neutral";
  card.className = `route-card ${normalized === "unknown" ? "neutral" : normalized} ${active ? "active" : ""}`.trim();
  badge.className = `route-badge ${normalized === "unknown" ? "neutral" : normalized}`;
  const labels = { allowed: "PERMITIDO", blocked: "BLOQUEADO", neutral: "SEM TESTE", unknown: "NÃO TESTADO" };
  badge.textContent = labels[normalized] || normalized.toUpperCase();
  text.textContent = detail;
}

function renderAccess(state) {
  const mode = state.mode || "idle";
  architecture.className = `architecture mode-${mode}`;
  const routeBoard = byId("routeBoard");
  if (routeBoard) routeBoard.classList.toggle("hidden", mode === "baseline");

  const a = mode === "baseline" ? state.access.baselineA : state.access.ztnaA;
  const b = mode === "baseline" ? state.access.baselineB : state.access.ztnaB;
  setStatusElement("apiAAccess", a);
  setStatusElement("apiBAccess", b);

  const walletStatus = state.wallet.authorized ? "allowed" : "blocked";
  setStatusElement("walletStatus", walletStatus, state.wallet.authorized ? "AUTORIZADA" : "REVOGADA");

  setRouteCard("BaselineA", state.access.baselineA, state.access.baselineA === "allowed" ? "Acesso direto via porta 8081" : "Exposição direta pela porta 8081", mode === "baseline");
  setRouteCard("BaselineB", state.access.baselineB, state.access.baselineB === "allowed" ? "Acesso direto via porta 8082" : "Exposição direta pela porta 8082", mode === "baseline");

  const ztnaADetail = state.wallet.authorized
    ? (state.access.ztnaA === "allowed" ? "Permitido por identidade + contexto" : "Autorizado, aguardando conexão")
    : "Bloqueado após revogação da carteira";
  const ztnaBDetail = state.wallet.authorized
    ? "Movimento lateral bloqueado por privilégio mínimo"
    : "Sem política Dial ativa para o serviço lateral";
  setRouteCard("ZtnaA", state.access.ztnaA, ztnaADetail, mode !== "baseline" && mode !== "idle");
  setRouteCard("ZtnaB", state.access.ztnaB, ztnaBDetail, mode !== "baseline" && mode !== "idle");
}

function renderMetrics(metrics) {
  byId("dockerCpu").textContent = metrics.dockerCpu == null ? "—" : `${metrics.dockerCpu}%`;
  byId("dockerMemory").textContent = metrics.dockerMemoryMb == null ? "—" : `${metrics.dockerMemoryMb} MB`;
  byId("containerCount").textContent = `${metrics.containers || 0} contêineres`;

  const baseline = metrics.baseline;
  const ztna = metrics.ztna;
  byId("baselineP95").textContent = baseline?.p95Ms == null ? "—" : `${baseline.p95Ms} ms`;
  byId("ztnaP95").textContent = ztna?.p95Ms == null ? "—" : `${ztna.p95Ms} ms`;
  byId("baselineRps").textContent = baseline ? `${baseline.rps} req/s · ${baseline.successRate}% sucesso` : "execute o benchmark";
  byId("ztnaRps").textContent = ztna ? `${ztna.rps} req/s · ${ztna.successRate}% sucesso` : "execute o benchmark";

  const max = Math.max(baseline?.p95Ms || 0, ztna?.p95Ms || 0, 1);
  byId("baselineBar").style.width = baseline ? `${Math.max(4, (baseline.p95Ms / max) * 100)}%` : "0%";
  byId("ztnaBar").style.width = ztna ? `${Math.max(4, (ztna.p95Ms / max) * 100)}%` : "0%";
  byId("baselineBarValue").textContent = baseline ? `${baseline.p95Ms} ms` : "—";
  byId("ztnaBarValue").textContent = ztna ? `${ztna.p95Ms} ms` : "—";
}

function renderTimeline(events) {
  const container = byId("timeline");
  if (!events.length) {
    container.innerHTML = '<div class="empty-state">Os eventos da execução aparecerão aqui.</div>';
    lastTimelineId = null;
    return;
  }

  const recent = [...events].reverse().slice(0, 12);
  container.innerHTML = recent.map((event) => `
    <article class="event ${event.kind || "info"}">
      <time>${escapeHtml(event.time)}</time>
      <strong>${escapeHtml(event.title)}</strong>
      <p>${escapeHtml(event.detail || "")}</p>
    </article>
  `).join("");

  if (!firstRender && events[events.length - 1].id !== lastTimelineId) {
    const panel = container.firstElementChild;
    panel?.animate([
      { transform: "translateY(-8px)", opacity: 0 },
      { transform: "translateY(0)", opacity: 1 },
    ], { duration: 350, easing: "ease-out" });
  }
  lastTimelineId = events[events.length - 1].id;
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function render(state) {
  byId("headline").textContent = state.headline;
  byId("message").textContent = state.message;
  byId("activeAction").textContent = state.busy ? `Executando: ${state.activeAction}` : "";

  const badge = byId("phaseBadge");
  badge.className = `phase-badge ${state.phase || "ready"}`;
  const phaseLabels = { ready: "PRONTO", running: "EM EXECUÇÃO", done: "CONCLUÍDO", error: "ERRO" };
  badge.textContent = phaseLabels[state.phase] || String(state.phase).toUpperCase();

  byId("busySpinner").hidden = !state.busy;
  document.querySelectorAll("[data-action]").forEach((button) => {
    if (button.dataset.action !== "clear") button.disabled = state.busy;
  });

  byId("walletShort").textContent = shortHash(state.wallet.address, 7);
  byId("zitiRole").textContent = state.wallet.role;
  byId("contractShort").textContent = shortHash(state.blockchain.contract, 7);
  byId("txHash").textContent = state.blockchain.lastTx === "—" ? "Nenhuma transação" : shortHash(state.blockchain.lastTx, 10);
  byId("txHash").title = state.blockchain.lastTx || "";
  byId("blockNumber").textContent = state.blockchain.block;

  setStatusElement("tunnelStatus", state.components.tunnel);
  setStatusElement("controllerStatus", state.components.controller);
  setStatusElement("blockchainStatus", state.components.blockchain);

  Object.entries(state.components).forEach(([name, status]) => renderComponent(name, status));
  renderAccess(state);
  renderMetrics(state.metrics);
  renderTimeline(state.timeline);

  if (state.error) showToast(state.error);
  firstRender = false;
}

function showToast(message) {
  toast.textContent = message;
  toast.classList.add("show");
  window.clearTimeout(showToast.timer);
  showToast.timer = window.setTimeout(() => toast.classList.remove("show"), 6500);
}

async function fetchState() {
  try {
    const response = await fetch(stateUrl, { cache: "no-store" });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    render(await response.json());
  } catch (error) {
    showToast(`Painel desconectado: ${error.message}`);
  }
}

async function runAction(action) {
  try {
    const response = await fetch(`/api/action/${action}`, { method: "POST" });
    const result = await response.json();
    if (!response.ok || !result.ok) throw new Error(result.error || result.message || "Não foi possível executar a ação");
    await fetchState();
  } catch (error) {
    showToast(error.message);
  }
}

document.querySelectorAll("[data-action]").forEach((button) => {
  button.addEventListener("click", () => runAction(button.dataset.action));
});

byId("fullscreenButton").addEventListener("click", async () => {
  try {
    if (!document.fullscreenElement) await document.documentElement.requestFullscreen();
    else await document.exitFullscreen();
  } catch (error) {
    showToast("O navegador não permitiu o modo de tela cheia.");
  }
});

fetchState();
setInterval(fetchState, 220);
