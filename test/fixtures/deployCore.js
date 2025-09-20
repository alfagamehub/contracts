const {ethers, artifacts, network} = require("hardhat");

const {
  ZERO_ADDRESS,
  DAY,
} = require('./const');

async function deployCore(deployerAddress, secondAddress) {
  try {
    // Pre-deploy mocks at fixed addresses (Hardhat only)
    
    async function setCodeAt(addr, contractName) {
      const artifact = await artifacts.readArtifact(contractName);
      await network.provider.send("hardhat_setCode", [addr, artifact.deployedBytecode]);
    }
    
    // Deploy mocks at fixed mainnet addresses for testing
    await setCodeAt("0x10ED43C718714eb63d5aA57B78B54704E256024E", "MockPancakeRouter");
    await setCodeAt("0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c", "MockWBNB");
    await setCodeAt("0x55d398326f99059fF775485246999027B3197955", "MockUSDT");
    await setCodeAt("0x1000000000000000000000000000000000000001", "MockERC20");
    
    const MockPancakeRouter = await ethers.getContractAt("MockPancakeRouter", "0x10ED43C718714eb63d5aA57B78B54704E256024E");
    
    // Initialize mocks (constructor-less) — idempotent guards to avoid "Already initialized"
    // USDT
    const MockUSDT = await ethers.getContractAt("MockUSDT", "0x55d398326f99059fF775485246999027B3197955");
    {
      let needInit = false;
      try {
        const dec = await MockUSDT.decimals();
        // If decimals is 0 (default), we consider not initialized
        needInit = (Number(dec) === 0);
      } catch (_) {
        // If call failed or ABI mismatch, try to initialize anyway
        needInit = true;
      }
      if (needInit) {
        if (typeof MockUSDT.initialize === "function") {
          await (await MockUSDT.initialize(18)).wait();
        } else if (MockUSDT.interface.functions["initialize(uint8)"]) {
          await (await MockUSDT["initialize(uint8)"](18)).wait();
        } else {
          console.warn("[deployCore] MockUSDT.initialize not found in ABI — skipping");
        }
      }
    }
    // WBNB
    const MockWBNB = await ethers.getContractAt("MockWBNB", "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c");
    {
      let needInit = false;
      try {
        const nm = await MockWBNB.name();
        needInit = (typeof nm !== "string" || nm.length === 0);
      } catch (_) {
        needInit = true;
      }
      if (needInit) {
        if (typeof MockWBNB.initialize === "function") {
          await (await MockWBNB.initialize()).wait();
        } else if (MockWBNB.interface.functions["initialize()"]) {
          await (await MockWBNB["initialize()"]()).wait();
        } else {
          console.warn("[deployCore] MockWBNB.initialize not found in ABI — skipping");
        }
      }
    }
    // ALFA test token (MockERC20)
    const MockERC20 = await ethers.getContractAt("MockERC20", "0x1000000000000000000000000000000000000001");
    {
      let needInit = false;
      try {
        const nm = await MockERC20.name();
        needInit = (typeof nm !== "string" || nm.length === 0);
      } catch (_) {
        needInit = true;
      }
      if (needInit) {
        if (typeof MockERC20.initialize === "function") {
          await (await MockERC20.initialize("ALFA Game", "ALFA", 18)).wait();
        } else if (MockERC20.interface.functions["initialize(string,string,uint8)"]) {
          await (await MockERC20["initialize(string,string,uint8)"]("ALFA Game", "ALFA", 18)).wait();
        } else {
          console.warn("[deployCore] MockERC20.initialize not found in ABI — skipping");
        }
      }
    }
    
    const list = {
      ALFAKey: [],
      ALFALootbox: [
        'ALFAKey',
      ],
      ALFAReferral: [],
      ALFAVault: [
        'ALFAKey',
        [
          ZERO_ADDRESS,
          MockUSDT.address,
        ],
        Math.floor(Date.now() / 1000) + DAY,
        Math.floor(Date.now() / 1000) + DAY * 2,
      ],
      ALFAStore: [
        'ALFAVault',
        'ALFALootbox',
        'ALFAReferral',
        [],
      ],
      ALFAForge: [
        'ALFAKey',
        secondAddress,
        'ALFAReferral',
        'ALFAVault',
      ]
    }
    const listKeys = Object.keys(list);
    const factory = {};
    const contract = {};
    const getValue = value => {
      return typeof value === 'string' && !!contract[value]
        ? contract[value].address
        : value;
    }
    await Promise.all(listKeys.map(async name => factory[name] = await ethers.getContractFactory(name)));
    for (let i = 0; i < listKeys.length; i++) {
      const name = listKeys[i];
      const args = list[name].map(value => getValue(value));
      // console.log('DEPLOY', name, args);
      contract[name] = await factory[name].deploy(...args);
    }
    
    await Promise.all(Object.keys(contract).map(name => contract[name].deployed()));
    
    // Update dependencies
    await contract.ALFAKey.grantRole(
      await contract.ALFAKey.BURNER_ROLE(),
      contract.ALFAVault.address,
    )
    await contract.ALFAKey.grantRole(
      await contract.ALFAKey.BURNER_ROLE(),
      contract.ALFAForge.address,
    )
    await contract.ALFAKey.grantRole(
      await contract.ALFAKey.MINTER_ROLE(),
      contract.ALFAForge.address,
    )
    await contract.ALFAKey.grantRole(
      await contract.ALFAKey.MINTER_ROLE(),
      contract.ALFALootbox.address,
    )
    
    await contract.ALFALootbox.grantRole(
      await contract.ALFALootbox.MINTER_ROLE(),
      contract.ALFAStore.address,
    )
    
    await contract.ALFAReferral.grantRole(
      await contract.ALFAReferral.CONNECTOR_ROLE(),
      contract.ALFAStore.address,
    )
    await contract.ALFAReferral.grantRole(
      await contract.ALFAReferral.CONNECTOR_ROLE(),
      contract.ALFAForge.address,
    )
    
    await MockPancakeRouter.setRate(MockUSDT.address, MockWBNB.address, 3, 1000);     // USDT->WBNB
    await MockPancakeRouter.setRate(MockWBNB.address, MockUSDT.address, 1000, 3);     // WBNB->USDT
    await MockPancakeRouter.setRate(MockWBNB.address, MockERC20.address, 100, 1);     // WBNB->TOKEN
    await MockPancakeRouter.setRate(MockUSDT.address, MockERC20.address, 2, 1);       // USDT->TOKEN
    
    Object.assign(contract, {
      MockUSDT,
      MockWBNB,
      MockERC20,
      MockPancakeRouter,
    }) 
    
    return contract;
  } catch (error) {
    console.error('[deployCore]', error);
    throw error;
  }
}

module.exports = deployCore;
