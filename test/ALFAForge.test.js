const deployAndSetupContracts = require("./fixtures/deployCore.js");
const {
  ZERO_ADDRESS,
} = require("./fixtures/const");
const {expect} = require("chai");
const {ethers, network} = require("hardhat");

const PERCENT_PRECISION = ethers.BigNumber.from(1_000_000);

describe("ALFAForge Contract", function () {
  let owner, holder, parent, grandpa, team, burn, refFree, extra;
  let contracts;

  beforeEach(async function () {
    await network.provider.send("hardhat_reset");
    [owner, holder, parent, grandpa, team, burn, refFree, extra] = await ethers.getSigners();
    contracts = await deployAndSetupContracts(owner.address, holder.address);

    const {ALFAForge} = contracts;
    await ALFAForge.connect(owner).setTeamAccount(team.address);
    await ALFAForge.connect(owner).setBurnAccount(burn.address);
  });

  it("should quote non-zero BNB price for upgrades", async function () {
    const {ALFAForge} = contracts;

    const prices = await ALFAForge.getPrices();
    expect(prices.length).to.be.greaterThan(0);

    const typePrices = prices[0];
    const bnbEntry = typePrices.find(p => p.tokenAddress.toLowerCase() === ZERO_ADDRESS.toLowerCase());

    expect(bnbEntry).to.not.equal(undefined);
    expect(bnbEntry.amount.gt(0)).to.equal(true);
  });

  it("should revert upgrade with unsupported token", async function () {
    const {ALFAKey, ALFAForge, MockERC20} = contracts;

    const mintTx = await ALFAKey.connect(owner).mint(holder.address, 1);
    const mintReceipt = await mintTx.wait();
    const tokenId = mintReceipt.events.find(e => e.event === "TokenMinted").args.tokenId;

    await expect(
      ALFAForge.connect(holder)["upgrade(uint256,address)"](tokenId, MockERC20.address)
    ).to.be.revertedWith("Token is not allowed");
  });

  it("should manage payment token allowlist", async function () {
    const {ALFAForge, MockERC20} = contracts;

    await expect(ALFAForge.connect(owner).addToken(MockERC20.address))
      .to.emit(ALFAForge, "TokenAdded")
      .withArgs(MockERC20.address);

    expect(await ALFAForge.getTokenAvailable(MockERC20.address)).to.equal(true);

    await expect(ALFAForge.connect(owner).addToken(MockERC20.address))
      .to.be.revertedWith("Token is already allowed");

    await expect(ALFAForge.connect(owner).removeToken(MockERC20.address))
      .to.emit(ALFAForge, "TokenRemoved")
      .withArgs(MockERC20.address);

    expect(await ALFAForge.getTokenAvailable(MockERC20.address)).to.equal(false);
  });

  it("should distribute ERC20 payments across referrals, team and burn", async function () {
    const {ALFAForge, ALFAKey, ALFAReferral, MockERC20} = contracts;

    if (!(await ALFAForge.getTokenAvailable(MockERC20.address))) {
      await ALFAForge.connect(owner).addToken(MockERC20.address);
    }

    const mintTx = await ALFAKey.connect(owner).mint(holder.address, 1);
    const mintReceipt = await mintTx.wait();
    const tokenId = mintReceipt.events.find(e => e.event === "TokenMinted").args.tokenId;

    await ALFAReferral.connect(owner).setSequence([
      holder.address,
      parent.address,
      grandpa.address,
    ]);

    const prices = await ALFAForge.getPrices();
    const erc20Entry = prices[0].find(p => p.tokenAddress.toLowerCase() === MockERC20.address.toLowerCase());
    const price = erc20Entry.amount;

    await MockERC20.connect(owner).mint(holder.address, price.mul(2));
    await MockERC20.connect(holder).approve(ALFAForge.address, price.mul(2));

    const parentBefore = await MockERC20.balanceOf(parent.address);
    const grandpaBefore = await MockERC20.balanceOf(grandpa.address);
    const teamBefore = await MockERC20.balanceOf(team.address);
    const burnBefore = await MockERC20.balanceOf(burn.address);
    const holderBefore = await MockERC20.balanceOf(holder.address);

    const tx = await ALFAForge.connect(holder)["upgrade(uint256,address)"](tokenId, MockERC20.address);
    const receipt = await tx.wait();

    const refs = await ALFAReferral.getReferralPercents(holder.address);
    let percentsLeft = PERCENT_PRECISION;
    let expectedParent = ethers.BigNumber.from(0);
    let expectedGrandpa = ethers.BigNumber.from(0);

    for (let i = 0; i < refs.length; i++) {
      if (refs[i].parentAddress === ZERO_ADDRESS) break;
      percentsLeft = percentsLeft.sub(refs[i].percents);
      if (i === 0) {
        expectedParent = price.mul(refs[i].percents).div(PERCENT_PRECISION);
      }
      if (i === 1) {
        expectedGrandpa = price.mul(refs[i].percents).div(PERCENT_PRECISION);
      }
    }

    const burnShare = await ALFAForge.burnShare();
    const teamSharePercents = percentsLeft.gt(burnShare)
      ? percentsLeft.sub(burnShare)
      : ethers.BigNumber.from(0);
    const burnSharePercents = percentsLeft.gt(burnShare)
      ? burnShare
      : percentsLeft;

    const expectedTeam = price.mul(teamSharePercents).div(PERCENT_PRECISION);
    const expectedBurn = price.mul(burnSharePercents).div(PERCENT_PRECISION);

    const parentAfter = await MockERC20.balanceOf(parent.address);
    const grandpaAfter = await MockERC20.balanceOf(grandpa.address);
    const teamAfter = await MockERC20.balanceOf(team.address);
    const burnAfter = await MockERC20.balanceOf(burn.address);
    const holderAfter = await MockERC20.balanceOf(holder.address);

    expect(parentAfter.sub(parentBefore)).to.equal(expectedParent);
    expect(grandpaAfter.sub(grandpaBefore)).to.equal(expectedGrandpa);
    expect(teamAfter.sub(teamBefore)).to.equal(expectedTeam);
    expect(burnAfter.sub(burnBefore)).to.equal(expectedBurn);
    expect(holderBefore.sub(holderAfter)).to.equal(price);

    const upgradeEvent = receipt.events.find(e => e.event === "KeyUpgraded" || e.event === "KeyBurned");
    expect(upgradeEvent).to.not.equal(undefined);
    expect(upgradeEvent.args.holder).to.equal(holder.address);
    expect(upgradeEvent.args.typeId).to.equal(ethers.BigNumber.from(1));
  });

  it("should accept native payments and refill burn account", async function () {
    const {ALFAForge, ALFAKey} = contracts;

    const mintTx = await ALFAKey.connect(owner).mint(refFree.address, 1);
    const mintReceipt = await mintTx.wait();
    const tokenId = mintReceipt.events.find(e => e.event === "TokenMinted").args.tokenId;

    const prices = await ALFAForge.getPrices();
    const bnbEntry = prices[0].find(p => p.tokenAddress.toLowerCase() === ZERO_ADDRESS.toLowerCase());
    const price = bnbEntry.amount;
    const burnShare = await ALFAForge.burnShare();
    const expectedBurn = price.mul(burnShare).div(PERCENT_PRECISION);

    await expect(
      ALFAForge.connect(refFree)["upgrade(uint256)"](tokenId, {value: price})
    ).to.emit(ALFAForge, "BurnAccountRefilled")
      .withArgs(refFree.address, ZERO_ADDRESS, expectedBurn);
  });
});

