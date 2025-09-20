const hre = require("hardhat");
const { Etherscan } = require("@nomicfoundation/hardhat-verify/etherscan");

function delay() {
  return new Promise((resolve) => setTimeout(resolve, 5 * 1000));
}

class ContractParams {
  constructor(args = [], onDeploy = address => {}) {
    this.args = args;
    this.onDeploy = onDeploy;
  }
}

const old = {
  skale: {
    coreV5: '0x049eEE4028Fb4fF8591Ea921F15843Cd2d9e9f94',
  },
}

async function main() {

  let contracts;

  const networkName = hre.network.name;
  console.log("");
  console.log('DEPLOY TO', networkName);
  const customChain = hre.config
    .etherscan
    .customChains
    .find(chain => chain.network === networkName);

  contracts = {
    DAOStaking: new ContractParams([
      () => '0x41c544303d45205f6717AEEa168D74A4E59284a7',
      () => '0x087e8705E56602158Cc98E41E8589dD2E5ABF61C',
    ]),
  };
  console.log('CONTRACTS', contracts);

  for (let i = 0; i < Object.keys(contracts).length; i++) {
    const name = Object.keys(contracts)[i];
    const params = contracts[name];
    const args = (params.args || []).map(argument => {
      return typeof argument === 'function'
        ? argument()
        : argument;
    });
    params.args = args;

    const contract = await hre.ethers.deployContract(name, args);
    await contract.deployTransaction.wait();
    const address = contract.deployTransaction.creates;
    params.address = address;

    console.log(`${name} deployed to:`);
    console.log(address);
    try {
      if (!customChain) continue;
      //await delay();
      await hre.run("verify:verify", {
        address,
        constructorArguments: args,
      });
      console.log("Contract verified to");
      console.log(customChain.urls.browserURL + "/address/" + address);
    } catch (error) {
      console.error("Error veryfing Contract. Reason:", error);
    }
    console.log("");
  }
  for (let i = 0; i < Object.keys(contracts).length; i++) {
    const name = Object.keys(contracts)[i];
    const params = contracts[name];
    const {address} = params;
    console.log("");
    console.log(name);
    console.log(address);
    console.log(customChain.urls.browserURL + "/address/" + address + '/contracts#address-tabs');
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
