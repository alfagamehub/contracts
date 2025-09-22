const deployAndSetupContracts = require("./fixtures/deployCore.js");
const {
  DAY,
} = require("./fixtures/const");
const {
  increaseTime,
} = require("./fixtures/utils");
const {ethers, network} = require("hardhat");

const MASTER_KEY_TYPE_ID = 5;

describe("ALFAVault Contract", function () {
  let owner, user;
  let contracts;

  beforeEach(async function () {
    await network.provider.send("hardhat_reset");
    [owner, user] = await ethers.getSigners();
    contracts = await deployAndSetupContracts(owner.address, user.address);
  });

  it("should return tokens", async function () {
    const {expect} = await import("chai");
    const {
      ALFAVault,
    } = contracts;

    const tokens = await ALFAVault.getVaultTokens();

    expect(tokens.length).to.equal(2);
  });

  it("should calculate holder share proportionally to master key ownership", async function () {
    const {expect} = await import("chai");
    const {
      ALFAVault,
      ALFAKey,
    } = contracts;

    const PERCENT_PRECISION = ethers.BigNumber.from(1_000_000);

    await ALFAKey.connect(owner).mint(owner.address, MASTER_KEY_TYPE_ID);
    await ALFAKey.connect(owner).mint(owner.address, MASTER_KEY_TYPE_ID);
    await ALFAKey.connect(owner).mint(user.address, MASTER_KEY_TYPE_ID);

    const totalKeys = await ALFAVault.getKeysTotalAmount();
    expect(totalKeys.toNumber()).to.equal(3);

    const ownerShare = await ALFAVault.getHolderShare(owner.address);
    const userShare = await ALFAVault.getHolderShare(user.address);

    const expectedOwnerShare = PERCENT_PRECISION.mul(2).div(3);
    const expectedUserShare = PERCENT_PRECISION.div(3);

    expect(ownerShare.toString()).to.equal(expectedOwnerShare.toString());
    expect(userShare.toString()).to.equal(expectedUserShare.toString());
  });

  it("should allow holder to redeem their share within the redemption window", async function () {
    const {expect} = await import("chai");
    const {
      ALFAVault,
      ALFAKey,
      MockUSDT,
    } = contracts;

    await ALFAKey.connect(owner).mint(owner.address, MASTER_KEY_TYPE_ID);
    await ALFAKey.connect(owner).mint(owner.address, MASTER_KEY_TYPE_ID);

    const mintTx = await ALFAKey.connect(owner).mint(user.address, MASTER_KEY_TYPE_ID);
    const mintReceipt = await mintTx.wait();
    const tokenId = mintReceipt.events.find(e => e.event === "TokenMinted").args.tokenId;

    const bnbDeposit = ethers.utils.parseEther("3");
    await owner.sendTransaction({to: ALFAVault.address, value: bnbDeposit});

    const usdtDeposit = ethers.utils.parseEther("300");
    await MockUSDT.connect(owner).mint(owner.address, usdtDeposit);
    await MockUSDT.connect(owner).transfer(ALFAVault.address, usdtDeposit);

    const totalKeys = await ALFAVault.getKeysTotalAmount();
    const expectedShareBNB = bnbDeposit.div(totalKeys);
    const expectedShareUSDT = usdtDeposit.div(totalKeys);

    const vaultBNBBefore = await ethers.provider.getBalance(ALFAVault.address);
    const vaultUSDTBefore = await MockUSDT.balanceOf(ALFAVault.address);
    const userUSDTBefore = await MockUSDT.balanceOf(user.address);

    await increaseTime(DAY + 1);

    await ALFAVault.connect(user).redeem(tokenId);

    const vaultBNBAfter = await ethers.provider.getBalance(ALFAVault.address);
    const vaultUSDTAfter = await MockUSDT.balanceOf(ALFAVault.address);
    const userUSDTAfter = await MockUSDT.balanceOf(user.address);
    const totalKeysAfter = await ALFAVault.getKeysTotalAmount();

    expect(vaultBNBBefore.sub(vaultBNBAfter).toString()).to.equal(expectedShareBNB.toString());
    expect(vaultUSDTBefore.sub(vaultUSDTAfter).toString()).to.equal(expectedShareUSDT.toString());
    expect(userUSDTAfter.sub(userUSDTBefore).toString()).to.equal(expectedShareUSDT.toString());
    expect(totalKeysAfter.toString()).to.equal(totalKeys.sub(1).toString());
    expect((await ALFAKey.balanceOf(user.address)).toNumber()).to.equal(0);
  });
});
