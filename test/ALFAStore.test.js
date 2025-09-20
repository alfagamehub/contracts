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
const {ethers, network} = require("hardhat");

describe("ALFAStore Contract", function () {
  let owner, user, parent, grandpa, elder, dead;
  let contracts;
  
  before(async function () {
    [owner, user, parent, grandpa, elder, dead] = await ethers.getSigners();
    contracts = await deployAndSetupContracts(owner.address, user.address);
  });
  
  it(`should have BNB price`, async function () {
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
    
    const BNBPrice = await MockPancakeRouter.getAmountsOut('1000000000000000000', [MockWBNB.address, MockUSDT.address]);
    
    expect(wei.from(BNBPrice[1])).to.greaterThan(0);
  });
  
  it(`should return right prices`, async function () {
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
    
    const prices = await ALFAStore.getPrices();
    // console.log('PRICES', prices.map(b => wei.from(b[1].amount)));

    for (let i = 0; i < prices.length; i++) {
      for (let t = 0; t < prices[i].length; t++) {
        expect(
          Number(wei.from(prices[i][t].amount)),
          `Failed for typeId=${Number(prices[i][t].typeId)}, tokenIndex=${t}, rawAmount=${prices[i][t].amount.toString()}`
        ).to.be.greaterThan(0);
      }
    }
  });
  
  it(`should mint USDT and have BNB`, async function () {
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
    
    await MockUSDT.connect(owner).mint(owner.address, wei.to(100));
    const amount = await MockUSDT.balanceOf(owner.address);
    const balance = await ethers.provider.getBalance(owner.address);
    
    expect(wei.from(amount)).to.equal(100);
    expect(wei.from(balance)).to.greaterThan(1);
  });
  
  it(`should buy with USDT`, async function () {
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
    
    await MockUSDT.connect(owner).approve(ALFAStore.address, wei.to(1000));
    await ALFAStore.connect(owner)['buy(uint256,address,uint256,address[])'](
      1,
      MockUSDT.address,
      1,
      []
    );
    const vault = await ALFAVault.getVaultTokens();
    const vaultUsdt = vault.find(v => v.tokenAddress.toLowerCase() === MockUSDT.address.toLowerCase());
    
    
    expect(wei.from(vaultUsdt.amount)).to.greaterThanOrEqual(0.8);
  });
  
  it(`should buy with BNB`, async function () {
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
    
    const typeId = 2;
    const prices = await ALFAStore.getPrices();
    const bnbPrices = prices.map(t => t.find(p => p.tokenAddress.toLowerCase() === ZERO_ADDRESS.toLowerCase()))
    const tokenPrice = wei.from(bnbPrices.find(t => Number(t.typeId) === typeId).amount);
    await ALFAStore.connect(owner)['buy(uint256,uint256,address[])'](
      2,
      1,
      [],
      { value: wei.to(tokenPrice) }
    );
    const vault = await ALFAVault.getVaultTokens();
    const vaultBnb = vault.find(v => v.tokenAddress.toLowerCase() === ZERO_ADDRESS.toLowerCase());
    
    
    expect(wei.from(vaultBnb.amount)).to.greaterThanOrEqual(tokenPrice * 0.8);
  });
  
  it(`should set referral`, async function () {
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
    
    await MockUSDT.connect(owner).approve(ALFAStore.address, wei.to(1000));
    await ALFAStore.connect(owner)['buy(uint256,address,uint256,address[])'](
      1,
      MockUSDT.address,
      1,
      [
        user.address,
        parent.address,
        grandpa.address,
        elder.address,
        dead.address,
      ]
    );
    const deadBalance = await MockUSDT.balanceOf(dead.address);
    
    
    expect(wei.from(deadBalance)).to.greaterThan(0);
  });
});
