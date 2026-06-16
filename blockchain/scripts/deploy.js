const fs = require('fs');
const path = require('path');
const solc = require('solc');
const { ethers } = require('ethers');
const { ROOT, DEPLOYMENT_FILE, RPC_URL, provider } = require('./common');

async function main() {
  const sourcePath = path.join(ROOT, 'contracts', 'AccessRegistry.sol');
  const source = fs.readFileSync(sourcePath, 'utf8');
  const input = {
    language: 'Solidity',
    sources: { 'AccessRegistry.sol': { content: source } },
    settings: {
      optimizer: { enabled: true, runs: 200 },
      outputSelection: { '*': { '*': ['abi', 'evm.bytecode.object'] } }
    }
  };

  const output = JSON.parse(solc.compile(JSON.stringify(input)));
  const errors = (output.errors || []).filter((entry) => entry.severity === 'error');
  if (errors.length) {
    throw new Error(errors.map((entry) => entry.formattedMessage).join('\n'));
  }

  const artifact = output.contracts['AccessRegistry.sol'].AccessRegistry;
  const rpc = provider();
  const owner = await rpc.getSigner(0);
  const testWalletSigner = await rpc.getSigner(1);
  const testWallet = await testWalletSigner.getAddress();
  const factory = new ethers.ContractFactory(
    artifact.abi,
    `0x${artifact.evm.bytecode.object}`,
    owner
  );

  const contract = await factory.deploy();
  await contract.waitForDeployment();
  const address = await contract.getAddress();
  const deployment = {
    rpcUrl: RPC_URL,
    chainId: 31337,
    contractAddress: address,
    testWallet,
    abi: artifact.abi,
    deployedAt: new Date().toISOString()
  };
  fs.writeFileSync(DEPLOYMENT_FILE, JSON.stringify(deployment, null, 2));
  console.log(`Contrato implantado: ${address}`);
  console.log(`Carteira de teste: ${testWallet}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
