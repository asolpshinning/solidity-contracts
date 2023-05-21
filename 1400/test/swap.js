const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Order Functions Testing", function () {

    async function setupOrderTesting() {
        const [owner, addr1, addr2] = await ethers.getSigners();

        const ShareToken = await ethers.getContractFactory("ERC1410Standard");
        const shareToken = await ShareToken.deploy();

        const PaymentToken = await ethers.getContractFactory("ERC20");
        const paymentToken = await PaymentToken.deploy("PaymentToken", "PTK");

        const SwapContract = await ethers.getContractFactory("SwapContract");
        const swapContract = await SwapContract.deploy(shareToken.address, paymentToken.address);

        return { owner, addr1, addr2, shareToken, paymentToken, swapContract };
    }

    it("Should allow an AskOrder from whitelisted address with sufficient balance", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, false);

        const order = await swapContract.orders(0);
        expect(order.initiator).to.equal(addr1.address);
        expect(order.partition).to.equal(partition);
        expect(order.amount).to.equal(amount);
        expect(order.price).to.equal(price);
        expect(order.orderType.isAskOrder).to.equal(true);
    });

    it("Should allow a BidOrder from whitelisted address with sufficient balance", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const amount = 100;
        const price = 1;
        const partition = ethers.utils.formatBytes32String("partition1");

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await paymentToken.connect(owner).mint(addr1.address, amount * price);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, false, false, false);

        const order = await swapContract.orders(0);
        expect(order.initiator).to.equal(addr1.address);
        expect(order.amount).to.equal(amount);
        expect(order.price).to.equal(price);
        expect(order.orderType.isAskOrder).to.equal(false);
    });

    it("Should fail when an AskOrder has insufficient balance", async function () {
        const { owner, addr1, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount - 10);

        await expect(
            swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, false)
        ).to.be.revertedWith("Insufficient balance");
    });

    it("Should fail when a BidOrder has insufficient balance", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const amount = 100;
        const price = 1;
        const partition = ethers.utils.formatBytes32String("partition1");

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await paymentToken.connect(owner).mint(addr1.address, amount * price - 10);

        await expect(
            swapContract.connect(addr1).initiateOrder(partition, amount, price, false, false, false)
        ).to.be.revertedWith("Insufficient balance");
    });

    it("Should fail when a non-whitelisted address tries to place an AskOrder or a BidOrder", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const amount = 100;
        const price = 1;
        const partition = ethers.utils.formatBytes32String("partition1");

        await paymentToken.connect(owner).mint(addr1.address, amount * price);
        await paymentToken.connect(owner).mint(addr2.address, amount * price);

        await expect(
            swapContract.connect(addr1).initiateOrder(partition, amount, price, false, false, false)
        ).to.be.revertedWith("Sender is not whitelisted");
        await expect(
            swapContract.connect(addr2).initiateOrder(partition, amount, price, true, false, false)
        ).to.be.revertedWith("Sender is not whitelisted");
    });

    it("Should allow different kinds of BidOrders by changing the isShareIssuance and isErc20Payment flags", async function () {
        const { owner, addr1, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        // Set up balances
        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await paymentToken.connect(owner).mint(addr1.address, amount * price);

        // Issue a Share Issuance order
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, false, true, false);
        let order = await swapContract.orders(0);
        expect(order.orderType.isAskOrder).to.equal(false);
        expect(order.orderType.isShareIssuance).to.equal(true);
        expect(order.orderType.isErc20Payment).to.equal(false);

        // Issue an ERC20 Payment order
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, false, false, true);
        order = await swapContract.orders(1);
        expect(order.orderType.isAskOrder).to.equal(false);
        expect(order.orderType.isShareIssuance).to.equal(false);
        expect(order.orderType.isErc20Payment).to.equal(true);

        // Issue an order that is both a Share Issuance and ERC20 Payment
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, false, true, true);
        order = await swapContract.orders(2);
        expect(order.orderType.isAskOrder).to.equal(false);
        expect(order.orderType.isShareIssuance).to.equal(true);
        expect(order.orderType.isErc20Payment).to.equal(true);
    });

    it("Should fail when a non-owner and non-manager tries to create share issuance as an AskOrder", async function () {
        const { owner, addr1, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await expect(
            swapContract.connect(addr1).initiateOrder(partition, amount, price, true, true, false)
        ).to.be.revertedWith("Only owner or manager can create share issuance ask orders");
    });

    it("Should allow an AskOrder from owner when it is share issuance", async function () {
        const { owner, addr1, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).issueByPartition(partition, owner.address, amount);
        await swapContract.connect(owner).initiateOrder(partition, amount, price, true, true, false);

        const order = await swapContract.orders(0);
        expect(order.initiator).to.equal(owner.address);
        expect(order.orderType.isShareIssuance).to.equal(true);
    });

    it("Should allow an AskOrder from manager when it is share issuance", async function () {
        const { owner, addr1, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).addManager(addr1.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, true, false);

        const order = await swapContract.orders(0);
        expect(order.initiator).to.equal(addr1.address);
        expect(order.orderType.isShareIssuance).to.equal(true);
    });

    it("should not allow banned addresses to place BidOrders", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const amount = 100;
        const price = 1;
        const partition = ethers.utils.formatBytes32String("partition1");

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).addToWhitelist(addr2.address);
        await swapContract.connect(owner).banAddress(addr1.address);
        await swapContract.connect(owner).banAddress(addr2.address);

        await paymentToken.connect(owner).mint(addr1.address, amount * price);
        await paymentToken.connect(owner).mint(addr2.address, amount * price);

        await expect(swapContract.connect(addr2).initiateOrder(partition, amount, price, false, false, false)).to.be.revertedWith("Cannot purchase from this address");
        await expect(swapContract.connect(addr2).initiateOrder(partition, amount, price, false, true, false)).to.be.revertedWith("Cannot purchase from this address");
    });

    // Similarly, write the rest of the test cases
});


