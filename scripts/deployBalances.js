const hre = require('hardhat');

const EXPLORER_URLS = {
  bsc: "https://bscscan.com",
};

function delay(ms = 1000) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function sendTx(txPromise, description) {
  const tx = await txPromise;
  console.log(`  ${description}`);
  console.log(`    tx: ${tx.hash}`);
  await tx.wait();
}

class ContractParams {
  constructor(args = [], onDeploy = async () => {}) {
    this.args = args;
    this.onDeploy = onDeploy;
  }
}

async function main() {
  const networkName = hre.network.name;
  console.log("");
  console.log("DEPLOY TO", networkName);
  await hre.run("compile");
  
  const customChain = hre.config
    .etherscan?.customChains
    ?.find(chain => chain.network === networkName);
  console.log('customChain', customChain);
  
  const deployments = {};
  
  const deployed = {};
  
  const contracts = {
    Balances: [],
  };
  
  const contractNames = Object.keys(contracts);
  
  for (let i = 0; i < contractNames.length; i++) {
    const name = contractNames[i];
    const params = contracts[name];
    
    const args = await Promise.all((params.args || []).map(async argument => {
      return typeof argument === "function"
        ? await argument()
        : argument;
    }));
    
    const factory = await hre.ethers.getContractFactory(name);
    const contract = await factory.deploy(...args);
    await contract.deployTransaction.wait();
    const address = contract.address;
    
    deployed[name] = contract;
    deployments[name] = {address, args};
    
    console.log(`${name} deployed to:`);
    console.log(address);
    
    await delay(10000);
    try {
      await hre.run("verify:verify", {
        address,
        constructorArguments: args,
      });
      const explorerBase = customChain?.urls?.browserURL || EXPLORER_URLS[networkName];
      if (explorerBase) {
        console.log("Contract verified at:");
        console.log(`${explorerBase}/address/${address}`);
      } else {
        console.log("Contract verified");
      }
    } catch (error) {
      console.error("Error verifying contract", name, error.message ?? error);
    }
    
    if (typeof params.onDeploy === "function") {
      await params.onDeploy(contract, deployed);
    }
    
    console.log("");
  }
  
  const explorerBase = customChain?.urls?.browserURL || EXPLORER_URLS[networkName];
  for (let i = 0; i < contractNames.length; i++) {
    const name = contractNames[i];
    const {address} = deployments[name];
    console.log(name);
    console.log(address);
    if (explorerBase) {
      console.log(`${explorerBase}/address/${address}#code`);
    }
    console.log("");
  }
  
  console.log("Deployment completed.");
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
