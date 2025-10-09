import { network, config } from "hardhat";
import {ethers} from "ethers";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const USDT_ADDRESS = "0x55d398326f99059fF775485246999027B3197955";
const USDC_ADDRESS = "0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d";

const BURN_ACCOUNT = "0x04A0600F50BF6a213939d3820568CE2efdAbE9a4";
const TEAM_ACCOUNT = "0x8c6f19f97c4980F1397CdA79Fa81EbFBEc96074d";

const ALFAKey_ADDRESS = '0x0f2F071870c3e25E02565c12729032e986b4f011';
const ALFAReferral_ADDRESS = '0xC957d27C5dB79e3a13b0a1ec0df32580A82C03cc';
const ALFAVault_ADDRESS = '0x16B07eE9b3fa66FC6513247542d6FEb112E01D58';

const EXPLORER_URLS: Record<string, string> = {
  bsc: "https://bscscan.com",
};

function delay(ms = 1000) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function sendTx(txPromise: Promise<any>, description: string) {
  const tx = await txPromise;
  console.log(`  ${description}`);
  console.log(`    tx: ${tx.hash}`);
  await tx.wait();
}

class ContractParams {
  args: any[];
  onDeploy: (contract: any, deployed?: Record<string, any>) => Promise<void>;
  constructor(args: any[] = [], onDeploy: (contract: any, deployed?: Record<string, any>) => Promise<void> = async () => {}) {
    this.args = args;
    this.onDeploy = onDeploy;
  }
}

async function main() {
  const networkName = network.name;
  console.log("");
  console.log("DEPLOY TO", networkName);

  const customChain = config
    .verify?.etherscan?.customChains
    ?.find((chain: any) => chain.network === networkName);
  console.log('customChain', customChain);

  const deployments: Record<string, { address: string; args: any[] }> = {};

  const deployed: Record<string, any> = {};

  const contracts: Record<string, ContractParams> = {
    ALFAForge: new ContractParams([
      ALFAKey_ADDRESS,
      BURN_ACCOUNT,
      ALFAReferral_ADDRESS,
      ALFAVault_ADDRESS,
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

    const factory = await ethers.getContractFactory(name);
    const contract = await factory.deploy(...args);
    await contract.waitForDeployment();
    const address = await contract.getAddress();

    deployed[name] = contract;
    deployments[name] = { address, args };

    console.log(`${name} deployed to:`);
    console.log(address);

    await delay(10000);
    // Hardhat v3: no hre.run in scripts; print CLI verify command instead
    const explorerBase = customChain?.urls?.browserURL || EXPLORER_URLS[networkName];
    console.log("To verify run:");
    console.log(`npx hardhat verify --network ${networkName} ${address} ${args.map(String).join(" ")}`);
    if (explorerBase) {
      console.log("Explorer:");
      console.log(`${explorerBase}/address/${address}`);
    }

    if (typeof params.onDeploy === "function") {
      await params.onDeploy(contract, deployed);
    }

    console.log("");
  }

  console.log("Configuring contract roles and permissions...");
  const ALFAKey = await ethers.getContractAt("ALFAKey", ALFAKey_ADDRESS);
  const ALFAReferral = await ethers.getContractAt("ALFAReferral", ALFAReferral_ADDRESS);
  const ALFAForge = deployed.ALFAForge ?? await ethers.getContractAt("ALFAForge", deployments.ALFAForge.address);

  await sendTx(
    ALFAKey.grantRole(await ALFAKey.BURNER_ROLE(), ALFAForge.getAddress()),
    "ALFAKey: grant BURNER_ROLE to ALFAForge",
  );
  await sendTx(
    ALFAKey.grantRole(await ALFAKey.MINTER_ROLE(), ALFAForge.getAddress()),
    "ALFAKey: grant MINTER_ROLE to ALFAForge",
  );
  await sendTx(
    ALFAReferral.grantRole(await ALFAReferral.CONNECTOR_ROLE(), ALFAForge.getAddress()),
    "ALFAReferral: grant CONNECTOR_ROLE to ALFAForge",
  );

  console.log("");
  const explorerBase = customChain?.urls?.browserURL || EXPLORER_URLS[networkName];
  for (let i = 0; i < contractNames.length; i++) {
    const name = contractNames[i];
    const { address } = deployments[name];
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
