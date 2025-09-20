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
    
    // Initialize mocks (constructor-less). If `.initialize` is missing in ABI, skip gracefully.
    // USDT
    {
      const mockUSDT = await ethers.getContractAt("MockUSDT", "0x55d398326f99059fF775485246999027B3197955");
      if (typeof mockUSDT.initialize === "function") {
        await (await mockUSDT.initialize(18)).wait();
      } else if (mockUSDT.interface.functions["initialize(uint8)"]) {
        await (await mockUSDT["initialize(uint8)"](18)).wait();
      } else {
        console.warn("[deployCore] MockUSDT.initialize not found in ABI — skipping");
      }
    }
    // WBNB
    {
      const mockWBNB = await ethers.getContractAt("MockWBNB", "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c");
      if (typeof mockWBNB.initialize === "function") {
        await (await mockWBNB.initialize()).wait();
      } else if (mockWBNB.interface.functions["initialize()"]) {
        await (await mockWBNB["initialize()"]()).wait();
      } else {
        console.warn("[deployCore] MockWBNB.initialize not found in ABI — skipping");
      }
    }
    // ALFA test token (MockERC20)
    {
      const mockERC20 = await ethers.getContractAt("MockERC20", "0x1000000000000000000000000000000000000001");
      if (typeof mockERC20.initialize === "function") {
        await (await mockERC20.initialize("ALFA Game", "ALFA", 18)).wait();
      } else if (mockERC20.interface.functions["initialize(string,string,uint8)"]) {
        await (await mockERC20["initialize(string,string,uint8)"]("ALFA Game", "ALFA", 18)).wait();
      } else {
        console.warn("[deployCore] MockERC20.initialize not found in ABI — skipping");
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
          '0x55d398326f99059fF775485246999027B3197955',
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
    
    return contract;
  } catch (error) {
    console.error('[deployCore]', error);
    throw error;
  }
}

module.exports = deployCore;

