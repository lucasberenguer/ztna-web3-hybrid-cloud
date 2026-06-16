const { ethers } = require('ethers');
const { readDeployment, provider } = require('./common');

async function main() {
  const deployment = readDeployment();
  const contract = new ethers.Contract(
    deployment.contractAddress,
    deployment.abi,
    provider()
  );
  const authorized = await contract.allowed(deployment.testWallet);
  console.log(JSON.stringify({
    wallet: deployment.testWallet,
    authorized,
    checkedAt: new Date().toISOString()
  }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
