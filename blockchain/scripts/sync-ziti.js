const path = require('path');
const { spawnSync } = require('child_process');
const { ethers } = require('ethers');
const { readDeployment, provider } = require('./common');

const LAB_ROOT = path.resolve(__dirname, '..', '..');
const COMPOSE_BASE = path.join(LAB_ROOT, 'compose.yml');
const COMPOSE_LAB = path.join(LAB_ROOT, 'compose.lab.yml');
const IDENTITY = process.env.ZITI_IDENTITY || 'wallet-user';
const ZITI_USER = process.env.ZITI_USER || 'admin';
const ZITI_PWD = process.env.ZITI_PWD || 'admin';
const CTRL = process.env.ZITI_CTRL || 'quickstart:1280';

for (const value of [IDENTITY, ZITI_USER]) {
  if (!/^[A-Za-z0-9_.@-]+$/.test(value)) {
    throw new Error(`Valor inválido para comando Ziti: ${value}`);
  }
}

function updateZitiRole(authorized) {
  const role = authorized ? 'wallet-allowed' : 'wallet-revoked';
  const command = [
    `ziti edge login ${CTRL} -u ${ZITI_USER} -p '${ZITI_PWD.replaceAll("'", "'\\''")}' -y >/dev/null`,
    `ziti edge update identity ${IDENTITY} -a ${role}`
  ].join(' && ');

  const args = [
    'compose', '-f', COMPOSE_BASE, '-f', COMPOSE_LAB,
    'exec', '-T', 'quickstart', 'bash', '-lc', command
  ];
  const started = Date.now();
  const result = spawnSync('docker', args, { encoding: 'utf8' });
  if (result.status !== 0) {
    throw new Error(`Falha ao atualizar identidade OpenZiti:\n${result.stderr || result.stdout}`);
  }
  return { role, updateMs: Date.now() - started };
}

async function readAuthorized(contract, wallet) {
  return Boolean(await contract.allowed(wallet));
}

async function runOnce(contract, wallet, previous) {
  const authorized = await readAuthorized(contract, wallet);
  if (authorized !== previous) {
    const update = updateZitiRole(authorized);
    console.log(JSON.stringify({
      event: 'ziti-role-updated',
      wallet,
      authorized,
      role: update.role,
      updateMs: update.updateMs,
      timestamp: new Date().toISOString()
    }));
  }
  return authorized;
}

async function main() {
  const deployment = readDeployment();
  const contract = new ethers.Contract(
    deployment.contractAddress,
    deployment.abi,
    provider()
  );
  const watchIndex = process.argv.indexOf('--watch');
  if (watchIndex === -1) {
    await runOnce(contract, deployment.testWallet, undefined);
    return;
  }

  const interval = Number(process.argv[watchIndex + 1] || 1000);
  if (!Number.isFinite(interval) || interval < 100) {
    throw new Error('O intervalo de observação deve ser pelo menos 100 ms.');
  }

  let previous;
  console.log(`Sincronização iniciada a cada ${interval} ms.`);
  while (true) {
    try {
      previous = await runOnce(contract, deployment.testWallet, previous);
    } catch (error) {
      console.error(`${new Date().toISOString()} ${error.message}`);
    }
    await new Promise((resolve) => setTimeout(resolve, interval));
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
