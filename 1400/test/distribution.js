const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("DividendsDistribution", function () {
    let owner, addr1, addr2, addr3;
    let sharesToken, payoutToken;
    let dividendsDistribution;
    let partition;
    let dividendBlock, payoutDate, reclaimTime;
    const ZERO_ADDRESS = ethers.constants.AddressZero;

    beforeEach(async function () {
        [owner, addr1, addr2, addr3] = await ethers.getSigners();
        partition = ethers.utils.formatBytes32String("partition1");

        dividendBlock = (await ethers.provider.getBlock()).timestamp
        payoutDate = (await ethers.provider.getBlock()).timestamp + 10;
        reclaimTime = dividendBlock + 100

        const SharesToken = await ethers.getContractFactory("ERC1410Standard");
        sharesToken = await SharesToken.deploy();

        const PayoutToken = await ethers.getContractFactory("ERC20");
        payoutToken = await PayoutToken.deploy("PayoutToken", "PTK");
        const DividendsDistribution = await ethers.getContractFactory("DividendsDistribution");
        dividendsDistribution = await DividendsDistribution.deploy(sharesToken.address, 1);
    });

    it("Should successfully instantiate the contract", async function () {
        expect(await dividendsDistribution.sharesToken()).to.equal(sharesToken.address);
        expect(await dividendsDistribution.reclaim_time()).to.equal(1);
    });

    it("Should allow the owner to deposit dividends", async function () {
        const amount = 1000;
        const dividendAmount = ethers.utils.parseEther("100");
        await sharesToken.connect(owner).addToWhitelist(addr1.address);
        await sharesToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        expect(await sharesToken.balanceOfByPartition(partition, addr1.address)).to.equal(amount);
        const checkBlock = (await ethers.provider.getBlock()).timestamp;
        await payoutToken.connect(owner).mint(owner.address, dividendAmount);
        await payoutToken.approve(dividendsDistribution.address, dividendAmount);
        expect(await sharesToken.totalSupplyAt(partition, checkBlock)).to.equal(amount);
        await dividendsDistribution.connect(owner).depositDividend(dividendBlock, 1, 1, payoutDate, dividendAmount, payoutToken.address, partition);
        expect(await dividendsDistribution.dividends(0)).to.exist;
    });

    it("Should allow the owner to recycle a dividend", async function () {
        const amount = 1000;
        const dividendAmount = ethers.utils.parseEther("100");
        await sharesToken.connect(owner).addToWhitelist(addr1.address);
        await payoutToken.connect(owner).mint(owner.address, dividendAmount);
        await payoutToken.approve(dividendsDistribution.address, dividendAmount);
        await sharesToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await dividendsDistribution.connect(owner).depositDividend(dividendBlock, 1, 1, payoutDate, dividendAmount, payoutToken.address, partition);
        // wait for reclaim time before recycling
        await ethers.provider.send("evm_setNextBlockTimestamp", [reclaimTime]);
        await ethers.provider.send("evm_mine");

        await dividendsDistribution.connect(owner).reclaimDividend(0);
        let dividend = await dividendsDistribution.dividends(0);
        expect(dividend.recycled).to.equal(true);
    });

    // Test Cases for claimDividend

    it("Should allow a shareholder to claim a dividend successfully", async function () {
        const amount = 1000;
        const dividendAmount = ethers.utils.parseEther("100");
        await sharesToken.connect(owner).addToWhitelist(addr1.address);
        await sharesToken.connect(owner).issueByPartition(partition, addr1.address, amount)
        expect(await sharesToken.balanceOfByPartition(partition, addr1.address)).to.equal(amount);
        const checkBlock = (await ethers.provider.getBlock()).timestamp;
        await payoutToken.connect(owner).mint(owner.address, dividendAmount);
        await payoutToken.approve(dividendsDistribution.address, dividendAmount);
        expect(await sharesToken.totalSupplyAt(partition, checkBlock)).to.equal(amount);
        await dividendsDistribution.connect(owner).depositDividend(dividendBlock, 1, 1, payoutDate, dividendAmount, payoutToken.address, partition);
        // check payoutToken balance of dividendsDistribution contract
        expect(await payoutToken.balanceOf(dividendsDistribution.address)).to.equal(dividendAmount);

        // wait for payout date before claiming
        await ethers.provider.send("evm_setNextBlockTimestamp", [payoutDate]);
        await ethers.provider.send("evm_mine");

        // check the claimable dividend amount of addr1
        expect(await dividendsDistribution.getClaimableAmount(addr1.address, 0)).to.equal(dividendAmount);

        await dividendsDistribution.connect(addr1).claimDividend(0);
        expect(await dividendsDistribution.hasClaimedDividend(addr1.address, 0)).to.be.true;

        // check payoutToken balance of dividendsDistribution contract
        expect(await payoutToken.balanceOf(dividendsDistribution.address)).to.equal(0);
        // check payoutToken balance of addr1
        expect(await payoutToken.balanceOf(addr1.address)).to.equal(dividendAmount);

        // check the claimable dividend amount of addr1
        expect(await dividendsDistribution.getClaimableAmount(addr1.address, 0)).to.equal(0);
    });

    it("Should fail if when claiming dividend, dividend index is invalid", async function () {
        await expect(dividendsDistribution.connect(addr1).claimDividend(0)).to.be.revertedWith("Invalid dividend index");
    });

    it("Should fail if when claiming dividend, it is before the payout date", async function () {
        const amount = 1000;
        const dividendAmount = ethers.utils.parseEther("100");
        await sharesToken.connect(owner).addToWhitelist(addr1.address);
        await sharesToken.connect(owner).issueByPartition(partition, addr1.address, amount)
        const checkBlock = (await ethers.provider.getBlock()).timestamp;
        await payoutToken.connect(owner).mint(owner.address, dividendAmount);
        await payoutToken.approve(dividendsDistribution.address, dividendAmount);
        await dividendsDistribution.connect(owner).depositDividend(checkBlock, 1, 1, payoutDate, dividendAmount, payoutToken.address, partition);
        await expect(dividendsDistribution.connect(addr1).claimDividend(0)).to.be.revertedWith("Cannot claim dividend before payout date");
    });

    it("Should fail if when claiming dividend, the sender does not hold any shares", async function () {
        const amount = 1000;
        const dividendAmount = ethers.utils.parseEther("100");
        await sharesToken.connect(owner).addToWhitelist(addr2.address);
        await sharesToken.connect(owner).issueByPartition(partition, addr2.address, amount)
        const checkBlock = (await ethers.provider.getBlock()).timestamp;
        await payoutToken.connect(owner).mint(owner.address, dividendAmount);
        await payoutToken.approve(dividendsDistribution.address, dividendAmount);
        await dividendsDistribution.connect(owner).depositDividend(checkBlock, 1, 1, payoutDate, dividendAmount, payoutToken.address, partition);
        // wait for payout date before claiming
        await ethers.provider.send("evm_setNextBlockTimestamp", [payoutDate]);
        await ethers.provider.send("evm_mine");

        await expect(dividendsDistribution.connect(addr1).claimDividend(0)).to.be.revertedWith("Sender does not hold any shares");
    });

    it("Should fail if when claiming dividend, the dividend has been recycled", async function () {
        const amount = 1000;
        const dividendAmount = ethers.utils.parseEther("100");
        await sharesToken.connect(owner).addToWhitelist(addr1.address);
        await payoutToken.connect(owner).mint(owner.address, dividendAmount);
        await payoutToken.approve(dividendsDistribution.address, dividendAmount);
        await sharesToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await dividendsDistribution.connect(owner).depositDividend(dividendBlock, 1, 1, payoutDate, dividendAmount, payoutToken.address, partition);
        // wait for reclaim time before recycling
        await ethers.provider.send("evm_setNextBlockTimestamp", [reclaimTime]);
        await ethers.provider.send("evm_mine");

        await dividendsDistribution.connect(owner).reclaimDividend(0);
        await expect(dividendsDistribution.connect(addr1).claimDividend(0)).to.be.revertedWith("Dividend has been recycled");
    });

    it("Should fail if when claiming dividend, dividend is already claimed by the sender", async function () {
        const amount = 1000;
        const dividendAmount = ethers.utils.parseEther("100");
        await sharesToken.connect(owner).addToWhitelist(addr1.address);
        await sharesToken.connect(owner).issueByPartition(partition, addr1.address, amount)
        const checkBlock = (await ethers.provider.getBlock()).timestamp;
        await payoutToken.connect(owner).mint(owner.address, dividendAmount);
        await payoutToken.approve(dividendsDistribution.address, dividendAmount);
        await dividendsDistribution.connect(owner).depositDividend(checkBlock, 1, 1, payoutDate, dividendAmount, payoutToken.address, partition);
        // wait for payout date before claiming
        await ethers.provider.send("evm_setNextBlockTimestamp", [payoutDate]);
        await ethers.provider.send("evm_mine");

        await dividendsDistribution.connect(addr1).claimDividend(0);
        await expect(dividendsDistribution.connect(addr1).claimDividend(0)).to.be.revertedWith("Dividend already claimed by the sender");
    });

    it("Should allow 3 investors claim proportionate amounts of dividends successfully", async function () {
        const amount = 1200;
        const dividendAmount = ethers.utils.parseEther("1200");
        await sharesToken.connect(owner).addToWhitelist(addr1.address);
        await sharesToken.connect(owner).addToWhitelist(addr2.address);
        await sharesToken.connect(owner).addToWhitelist(addr3.address);
        await sharesToken.connect(owner).issueByPartition(partition, addr1.address, amount / 2)
        await sharesToken.connect(owner).issueByPartition(partition, addr2.address, amount / 4)
        await sharesToken.connect(owner).issueByPartition(partition, addr3.address, amount / 6)

        await payoutToken.connect(owner).mint(owner.address, dividendAmount);
        await payoutToken.approve(dividendsDistribution.address, dividendAmount);
        const checkBlock = (await ethers.provider.getBlock()).timestamp;
        await dividendsDistribution.connect(owner).depositDividend(checkBlock, 1, 1, payoutDate + 20, dividendAmount, payoutToken.address, partition);
        // wait for payout date before claiming
        await ethers.provider.send("evm_setNextBlockTimestamp", [payoutDate + 20]);
        await ethers.provider.send("evm_mine");

        // check that each investor has 0 payout token balance
        let balance1 = await payoutToken.balanceOf(addr1.address);
        let balance2 = await payoutToken.balanceOf(addr2.address);
        let balance3 = await payoutToken.balanceOf(addr3.address);
        expect(balance1).to.equal(0);
        expect(balance2).to.equal(0);
        expect(balance3).to.equal(0);

        // get claimable amounts
        let claimable1 = await dividendsDistribution.getClaimableAmount(addr1.address, 0);
        let claimable2 = await dividendsDistribution.getClaimableAmount(addr2.address, 0);
        let claimable3 = await dividendsDistribution.getClaimableAmount(addr3.address, 0);

        expect(claimable1).to.greaterThanOrEqual(ethers.utils.parseEther("570"));
        expect(claimable1).to.lessThanOrEqual(ethers.utils.parseEther("660"));
        expect(claimable2).to.greaterThanOrEqual(ethers.utils.parseEther("285"));
        expect(claimable2).to.lessThanOrEqual(ethers.utils.parseEther("330"));
        expect(claimable3).to.greaterThanOrEqual(ethers.utils.parseEther("190"));
        expect(claimable3).to.lessThanOrEqual(ethers.utils.parseEther("220"));

        // claim dividends
        await dividendsDistribution.connect(addr1).claimDividend(0);
        expect(await dividendsDistribution.hasClaimedDividend(addr1.address, 0)).to.be.true;
        await dividendsDistribution.connect(addr2).claimDividend(0);
        expect(await dividendsDistribution.hasClaimedDividend(addr2.address, 0)).to.be.true;
        await dividendsDistribution.connect(addr3).claimDividend(0);
        expect(await dividendsDistribution.hasClaimedDividend(addr3.address, 0)).to.be.true;


        // check that the correct amount was transferred to each investor
        expect(await payoutToken.balanceOf(addr1.address)).to.greaterThanOrEqual(ethers.utils.parseEther("570"));
        expect(await payoutToken.balanceOf(addr1.address)).to.lessThanOrEqual(ethers.utils.parseEther("660"));
        expect(await payoutToken.balanceOf(addr2.address)).to.greaterThanOrEqual(ethers.utils.parseEther("285"));
        expect(await payoutToken.balanceOf(addr2.address)).to.lessThanOrEqual(ethers.utils.parseEther("330"));
        expect(await payoutToken.balanceOf(addr3.address)).to.greaterThanOrEqual(ethers.utils.parseEther("190"));
        expect(await payoutToken.balanceOf(addr3.address)).to.lessThanOrEqual(ethers.utils.parseEther("220"));

        // get claimable amount for each investor
        claimable1 = await dividendsDistribution.getClaimableAmount(addr1.address, 0);
        claimable2 = await dividendsDistribution.getClaimableAmount(addr2.address, 0);
        claimable3 = await dividendsDistribution.getClaimableAmount(addr3.address, 0);
        expect(claimable1).to.equal(0);
        expect(claimable2).to.equal(0);
        expect(claimable3).to.equal(0);

        // check that the correct amount was transferred to each investor
        expect(await payoutToken.balanceOf(addr1.address)).to.greaterThanOrEqual(ethers.utils.parseEther("570"));
        expect(await payoutToken.balanceOf(addr1.address)).to.lessThanOrEqual(ethers.utils.parseEther("660"));
        expect(await payoutToken.balanceOf(addr2.address)).to.greaterThanOrEqual(ethers.utils.parseEther("285"));
        expect(await payoutToken.balanceOf(addr2.address)).to.lessThanOrEqual(ethers.utils.parseEther("330"));
        expect(await payoutToken.balanceOf(addr3.address)).to.greaterThanOrEqual(ethers.utils.parseEther("190"));
        expect(await payoutToken.balanceOf(addr3.address)).to.lessThanOrEqual(ethers.utils.parseEther("220"));

    });

    it("Should allow 3 investors claim past dividends after being zeroed out", async function () {
        const amount = 1200;
        const dividendAmount = ethers.utils.parseEther("1200");
        await sharesToken.connect(owner).addToWhitelist(addr1.address);
        await sharesToken.connect(owner).addToWhitelist(addr2.address);
        await sharesToken.connect(owner).addToWhitelist(addr3.address);
        await sharesToken.connect(owner).issueByPartition(partition, addr1.address, amount / 2)
        await sharesToken.connect(owner).issueByPartition(partition, addr2.address, amount / 4)
        await sharesToken.connect(owner).issueByPartition(partition, addr3.address, amount / 6)

        await payoutToken.connect(owner).mint(owner.address, dividendAmount);
        await payoutToken.approve(dividendsDistribution.address, dividendAmount);
        const checkBlock = (await ethers.provider.getBlock()).number;

        // deposit dividends
        await dividendsDistribution.connect(owner).depositDividend(checkBlock, 1, 1, payoutDate + 20, dividendAmount, payoutToken.address, partition);
        // wait for payout date before claiming
        await ethers.provider.send("evm_setNextBlockTimestamp", [payoutDate + 20]);
        await ethers.provider.send("evm_mine");

        // check that each investor has 0 payout token balance
        let balance1 = await payoutToken.balanceOf(addr1.address);
        let balance2 = await payoutToken.balanceOf(addr2.address);
        let balance3 = await payoutToken.balanceOf(addr3.address);
        expect(balance1).to.equal(0);
        expect(balance2).to.equal(0);
        expect(balance3).to.equal(0);

        // make owner an operator
        await sharesToken.connect(owner).authorizeOperator(owner.address);
        // transfer all shares back to owner
        await sharesToken.connect(owner).operatorTransferByPartition(partition, addr1.address, owner.address, amount / 2);
        await sharesToken.connect(owner).operatorTransferByPartition(partition, addr2.address, owner.address, amount / 4);
        await sharesToken.connect(owner).operatorTransferByPartition(partition, addr3.address, owner.address, amount / 6);

        // get claimable amounts
        let claimable1 = await dividendsDistribution.getClaimableAmount(addr1.address, 0);
        let claimable2 = await dividendsDistribution.getClaimableAmount(addr2.address, 0);
        let claimable3 = await dividendsDistribution.getClaimableAmount(addr3.address, 0);

        expect(claimable1).to.greaterThanOrEqual(ethers.utils.parseEther("570"));
        expect(claimable1).to.lessThanOrEqual(ethers.utils.parseEther("660"));
        expect(claimable2).to.greaterThanOrEqual(ethers.utils.parseEther("285"));
        expect(claimable2).to.lessThanOrEqual(ethers.utils.parseEther("330"));
        expect(claimable3).to.greaterThanOrEqual(ethers.utils.parseEther("190"));
        expect(claimable3).to.lessThanOrEqual(ethers.utils.parseEther("220"));

        // claim dividends
        await dividendsDistribution.connect(addr1).claimDividend(0);
        expect(await dividendsDistribution.hasClaimedDividend(addr1.address, 0)).to.be.true;
        await dividendsDistribution.connect(addr2).claimDividend(0);
        expect(await dividendsDistribution.hasClaimedDividend(addr2.address, 0)).to.be.true;
        await dividendsDistribution.connect(addr3).claimDividend(0);
        expect(await dividendsDistribution.hasClaimedDividend(addr3.address, 0)).to.be.true;


        // check that the correct amount was transferred to each investor
        expect(await payoutToken.balanceOf(addr1.address)).to.greaterThanOrEqual(ethers.utils.parseEther("570"));
        expect(await payoutToken.balanceOf(addr1.address)).to.lessThanOrEqual(ethers.utils.parseEther("660"));
        expect(await payoutToken.balanceOf(addr2.address)).to.greaterThanOrEqual(ethers.utils.parseEther("285"));
        expect(await payoutToken.balanceOf(addr2.address)).to.lessThanOrEqual(ethers.utils.parseEther("330"));
        expect(await payoutToken.balanceOf(addr3.address)).to.greaterThanOrEqual(ethers.utils.parseEther("190"));
        expect(await payoutToken.balanceOf(addr3.address)).to.lessThanOrEqual(ethers.utils.parseEther("220"));

        // get claimable amount for each investor
        claimable1 = await dividendsDistribution.getClaimableAmount(addr1.address, 0);
        claimable2 = await dividendsDistribution.getClaimableAmount(addr2.address, 0);
        claimable3 = await dividendsDistribution.getClaimableAmount(addr3.address, 0);
        expect(claimable1).to.equal(0);
        expect(claimable2).to.equal(0);
        expect(claimable3).to.equal(0);

        // check that the correct amount was transferred to each investor
        expect(await payoutToken.balanceOf(addr1.address)).to.greaterThanOrEqual(ethers.utils.parseEther("570"));
        expect(await payoutToken.balanceOf(addr1.address)).to.lessThanOrEqual(ethers.utils.parseEther("660"));
        expect(await payoutToken.balanceOf(addr2.address)).to.greaterThanOrEqual(ethers.utils.parseEther("285"));
        expect(await payoutToken.balanceOf(addr2.address)).to.lessThanOrEqual(ethers.utils.parseEther("330"));
        expect(await payoutToken.balanceOf(addr3.address)).to.greaterThanOrEqual(ethers.utils.parseEther("190"));
        expect(await payoutToken.balanceOf(addr3.address)).to.lessThanOrEqual(ethers.utils.parseEther("220"));

    });
});
