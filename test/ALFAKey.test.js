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

describe("ALFAKey Contract", function () {
  let owner, user, parent, grandpa;
  let contracts;
  
  before(async function () {
    [owner, user] = await ethers.getSigners();
    contracts = await deployAndSetupContracts(owner.address, user.address);
  });
  
  it(`should return types`, async function () {
    const {expect} = await import("chai");
    const {
      ALFAKey,
      ALFALootbox,
      ALFAReferral,
      ALFAVault,
      ALFAStore,
      ALFAForge,
    } = contracts;
    
    // await ALFAKey.connect(owner).claimArea(0,0);
    
    const types = await ALFAKey.getTypes();
    // console.log('TYPES', types);
    
    expect(types.length).to.equal(5);
  });
  
  it(`should mint`, async function () {
    const {expect} = await import("chai");
    const {
      ALFAKey,
      ALFALootbox,
      ALFAReferral,
      ALFAVault,
      ALFAStore,
      ALFAForge,
    } = contracts;
    
    await ALFAKey.connect(owner).mint(owner.address, 1);
    
    const types = await ALFAKey.getTypes();
    const amounts = await ALFAKey.getHolderAmounts(owner.address);
    
    expect(Number(types[0].count)).to.equal(1);
    expect(Number(amounts[0])).to.equal(1);
  });
  
  it(`should transfer`, async function () {
    const {expect} = await import("chai");
    const {
      ALFAKey,
      ALFALootbox,
      ALFAReferral,
      ALFAVault,
      ALFAStore,
      ALFAForge,
    } = contracts;
    
    await ALFAKey.connect(owner).transferFrom(owner.address, user.address, 1);
    
    const types = await ALFAKey.getTypes();
    const amounts = await ALFAKey.getHolderAmounts(user.address);
    
    expect(Number(types[0].count)).to.equal(1);
    expect(Number(amounts[0])).to.equal(1);
  });
  
  it(`should burn`, async function () {
    const {expect} = await import("chai");
    const {
      ALFAKey,
      ALFALootbox,
      ALFAReferral,
      ALFAVault,
      ALFAStore,
      ALFAForge,
    } = contracts;
    
    await ALFAKey.connect(owner).burn(user.address, 1);
    
    const types = await ALFAKey.getTypes();
    const amounts = await ALFAKey.getHolderAmounts(user.address);
    
    expect(Number(types[0].count)).to.equal(0);
    expect(Number(amounts[0])).to.equal(0);
  });
});
