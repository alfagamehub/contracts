const hre = require("hardhat");

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const USDT_ADDRESS = "0x55d398326f99059fF775485246999027B3197955";
const USDC_ADDRESS = "0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d";

const BURN_ACCOUNT = "0x04A0600F50BF6a213939d3820568CE2efdAbE9a4";
const TEAM_ACCOUNT = "0x8c6f19f97c4980F1397CdA79Fa81EbFBEc96074d";

const UNLOCK_DATE = 1761480000;      // 26 Oct 2025 12:00 UTC
const REDEEM_UNTIL_DATE = 1761912000; // 31 Oct 2025 12:00 UTC

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

  const customChain = hre.config
    .etherscan?.customChains
    ?.find(chain => chain.network === networkName);

  const deployments = {};

  const deployed = {};

  const contracts = {
    ALFAKey: new ContractParams(),
    ALFALootbox: new ContractParams([
      () => deployed.ALFAKey.address,
    ]),
    ALFAReferral: new ContractParams(),
    ALFAVault: new ContractParams([
      () => deployed.ALFAKey.address,
      [ZERO_ADDRESS, USDT_ADDRESS, USDC_ADDRESS],
      UNLOCK_DATE,
      REDEEM_UNTIL_DATE,
    ]),
    ALFAStore: new ContractParams([
      () => deployed.ALFAVault.address,
      () => deployed.ALFALootbox.address,
      () => deployed.ALFAReferral.address,
      [],
    ], async contract => {
      await sendTx(
        contract.setTeamAccount(TEAM_ACCOUNT),
        "ALFAStore: set team account",
      );
    }),
    ALFAForge: new ContractParams([
      () => deployed.ALFAKey.address,
      BURN_ACCOUNT,
      () => deployed.ALFAReferral.address,
      () => deployed.ALFAVault.address,
    ], async contract => {
      await sendTx(
        contract.setTeamAccount(TEAM_ACCOUNT),
        "ALFAForge: set team account",
      );
      await sendTx(
        contract.addToken(USDT_ADDRESS),
        "ALFAForge: add USDT token",
      );
      await sendTx(
        contract.addToken(USDC_ADDRESS),
        "ALFAForge: add USDC token",
      );
    }),
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

  console.log("Configuring contract roles and permissions...");

  const ALFAKey = deployed.ALFAKey;
  const ALFALootbox = deployed.ALFALootbox;
  const ALFAReferral = deployed.ALFAReferral;
  const ALFAVault = deployed.ALFAVault;
  const ALFAStore = deployed.ALFAStore;
  const ALFAForge = deployed.ALFAForge;

  await sendTx(
    ALFAKey.grantRole(await ALFAKey.BURNER_ROLE(), ALFAVault.address),
    "ALFAKey: grant BURNER_ROLE to ALFAVault",
  );
  await sendTx(
    ALFAKey.grantRole(await ALFAKey.BURNER_ROLE(), ALFAForge.address),
    "ALFAKey: grant BURNER_ROLE to ALFAForge",
  );
  await sendTx(
    ALFAKey.grantRole(await ALFAKey.MINTER_ROLE(), ALFAForge.address),
    "ALFAKey: grant MINTER_ROLE to ALFAForge",
  );
  await sendTx(
    ALFAKey.grantRole(await ALFAKey.MINTER_ROLE(), ALFALootbox.address),
    "ALFAKey: grant MINTER_ROLE to ALFALootbox",
  );

  await sendTx(
    ALFALootbox.grantRole(await ALFALootbox.MINTER_ROLE(), ALFAStore.address),
    "ALFALootbox: grant MINTER_ROLE to ALFAStore",
  );

  await sendTx(
    ALFAReferral.grantRole(await ALFAReferral.CONNECTOR_ROLE(), ALFAStore.address),
    "ALFAReferral: grant CONNECTOR_ROLE to ALFAStore",
  );
  await sendTx(
    ALFAReferral.grantRole(await ALFAReferral.CONNECTOR_ROLE(), ALFAForge.address),
    "ALFAReferral: grant CONNECTOR_ROLE to ALFAForge",
  );

  console.log("");
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

