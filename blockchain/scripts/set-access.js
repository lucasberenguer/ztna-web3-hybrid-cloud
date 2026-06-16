const { ethers } = require('ethers');
const { readDeployment, provider } = require('./common');

async function main() {
  const mode = process.argv[2];
  if (!['allow', 'revoke'].includes(mode)) {
    throw new Error('Uso: node scripts/set-access.js allow|revoke');
  }

  const deployment = readDeployment();
  const rpc = provider();
  const owner = await rpc.getSigner(0);
  const contract = new ethers.Contract(deployment.contractAddress, deployment.abi, owner);
  const authorized = mode === 'allow';
  const tx = await contract.setAccess(deployment.testWallet, authorized);
  const receipt = await tx.wait();
  console.log(JSON.stringify({
    wallet: deployment.testWallet,
    authorized,
    transactionHash: receipt.hash,
    blockNumber: receipt.blockNumber,
    changedAt: new Date().toISOString()
  }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
