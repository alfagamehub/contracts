const deployAndSetupContracts = require("./fixtures/deployCore.js");
const {
  HOUR,
  DAY,
  ZERO_ADDRESS,
} = require("./fixtures/const");
const {
  increaseTime,
  wei,
} = require("./fixtures/utils");
const {ethers} = require("hardhat");

describe("ALFAVault Contract", function () {
  let owner, user, parent, grandpa;
  let contracts;
  
  before(async function () {
    [owner, user] = await ethers.getSigners();
    contracts = await deployAndSetupContracts(owner.address, user.address);
  });
  
  it(`should return tokens`, async function () {
    const {expect} = await import("chai");
    const {
      ALFAKey,
      ALFALootbox,
      ALFAReferral,
      ALFAVault,
      ALFAStore,
      ALFAForge,
      MockUSDT,
      MockWBNB,
      MockERC20,
      MockPancakeRouter,
    } = contracts;
    
    const tokens = await ALFAVault.getVaultTokens();
    // console.log('TOKENS', tokens);

    expect(tokens.length).to.equal(2);
  });
});
