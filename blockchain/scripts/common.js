const fs = require('fs');
const path = require('path');
const { ethers } = require('ethers');

const ROOT = path.resolve(__dirname, '..');
const DEPLOYMENT_FILE = path.join(ROOT, 'deployment.json');
const RPC_URL = process.env.RPC_URL || 'http://127.0.0.1:8545';

function readDeployment() {
  if (!fs.existsSync(DEPLOYMENT_FILE)) {
    throw new Error('deployment.json não encontrado. Execute: npm run deploy');
  }
  return JSON.parse(fs.readFileSync(DEPLOYMENT_FILE, 'utf8'));
}

function provider() {
  return new ethers.JsonRpcProvider(RPC_URL);
}

module.exports = { ROOT, DEPLOYMENT_FILE, RPC_URL, readDeployment, provider };
