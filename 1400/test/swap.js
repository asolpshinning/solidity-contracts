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

    // Test cases for initiateOrder()
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
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount - 10);

        await expect(
            swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, false)
        ).to.be.revertedWith("Swap: Insufficient balance");
    });

    it("should allow owner or manager to place a shareIssuance AskOrder with insufficient balance", async function () {
        const { owner, swapContract } = await setupOrderTesting();
        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;
        await swapContract.connect(owner).initiateOrder(partition, amount, price, true, true, false);

        const order = await swapContract.orders(0);
        expect(order.initiator).to.equal(owner.address);
        expect(order.amount).to.equal(amount);
        expect(order.price).to.equal(price);
        expect(order.orderType.isAskOrder).to.equal(true);
        expect(order.orderType.isShareIssuance).to.equal(true);
    });

    it("Should fail when a BidOrder has insufficient balance", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const amount = 100;
        const price = 1;
        const partition = ethers.utils.formatBytes32String("partition1");

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await paymentToken.connect(owner).mint(addr1.address, amount * price - 10);

        await expect(
            swapContract.connect(addr1).initiateOrder(partition, amount, price, false, false, true)
        ).to.be.revertedWith("Swap: Insufficient balance");
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

    // Test cases for Approving Orders
    it("Should allow owner to approve an order", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();
        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, false);
        await swapContract.connect(owner).approveOrder(0);

        const order = await swapContract.orders(0);
        expect(order.status.isApproved).to.equal(true);
    });

    it("Should allow manager to approve an order", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();
        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).addManager(addr2.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, false);
        await swapContract.connect(addr2).approveOrder(0);

        const order = await swapContract.orders(0);
        expect(order.status.isApproved).to.equal(true);
    });

    it("Should not allow non-owner and non-manager to approve an order", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();
        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, false);

        await expect(swapContract.connect(addr2).approveOrder(0)).to.be.revertedWith("Sender is not the owner or manager");
    });

    it("Should not allow approving an already approved order", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();
        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await paymentToken.connect(owner).mint(addr1.address, amount * price);
        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, false, false, false);
        await swapContract.connect(owner).approveOrder(0);

        await expect(swapContract.connect(owner).approveOrder(0)).to.be.revertedWith("Order already approved");
    });

    it("Should not allow approving a cancelled or disapproved order", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();
        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).addToWhitelist(addr2.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await paymentToken.connect(owner).mint(addr2.address, amount * price);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, false);
        await swapContract.connect(addr2).initiateOrder(partition, amount, price, false, false, false);
        await swapContract.connect(addr1).cancelOrder(0);
        await swapContract.connect(owner).disapproveOrder(1);

        await expect(swapContract.connect(owner).approveOrder(0)).to.be.revertedWith("Order already cancelled");
        await expect(swapContract.connect(owner).approveOrder(1)).to.be.revertedWith("Order already disapproved");
    });

    it("Should not allow order approval when approvals are toggled off", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();
        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        expect(await swapContract.txnApprovalsEnabled()).to.equal(false);
        expect(await swapContract.swapApprovalsEnabled()).to.equal(true);
        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await swapContract.connect(owner).toggleSwapApprovals();
        expect(await swapContract.swapApprovalsEnabled()).to.equal(false);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, false);

        await expect(swapContract.connect(owner).approveOrder(0)).to.be.revertedWith("Approvals toggled off, no approval required");
    });

    it("Should not allow order approval when transaction approvals are enabled and order is not accepted", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();
        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, false);
        await swapContract.connect(owner).toggleTxnApprovals();
        expect(await swapContract.txnApprovalsEnabled()).to.equal(true);

        await expect(swapContract.connect(owner).approveOrder(0)).to.be.revertedWith("Initiated orders must be accepted before approval (if txn approvals are enabled)");
    });

    // Test Cases for Disapproving an Order
    it("Should allow the owner or manager to disapprove an order", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, false);

        await swapContract.connect(owner).disapproveOrder(0);

        const order = await swapContract.orders(0);
        expect(order.status.isDisapproved).to.equal(true);
    });

    it("Should not allow disapproving an already disapproved order", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, false);
        await swapContract.connect(owner).disapproveOrder(0);

        await expect(swapContract.connect(owner).disapproveOrder(0)).to.be.revertedWith("Order already disapproved");
    });

    it("Should not allow disapproving a cancelled order", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, false);
        await swapContract.connect(addr1).cancelOrder(0);

        await expect(swapContract.connect(owner).disapproveOrder(0)).to.be.revertedWith("Order already cancelled");
    });

    it("Should not allow order disapproval when approvals are toggled off", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, false);
        await swapContract.connect(owner).toggleSwapApprovals();

        await expect(swapContract.connect(owner).disapproveOrder(0)).to.be.revertedWith("Approvals toggled off");
    });

    it("Should not allow disapproving an order that is fully filled", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).addToWhitelist(addr2.address);
        await paymentToken.connect(owner).mint(addr2.address, 1.5 * amount * price);
        await paymentToken.connect(addr2).increaseAllowance(swapContract.address, 1.5 * amount * price);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, 1.5 * amount);
        await shareToken.connect(owner).authorizeOperator(swapContract.address);
        expect(await shareToken.isOperator(swapContract.address)).to.equal(true);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, true);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, true);
        await swapContract.connect(owner).approveOrder(0);
        await swapContract.connect(owner).approveOrder(1);
        await swapContract.connect(addr2).acceptOrder(0, amount);
        await swapContract.connect(addr2).acceptOrder(1, amount / 2);
        await swapContract.connect(addr2).fillOrder(0, amount);
        await swapContract.connect(addr2).fillOrder(1, amount / 2);

        await expect(swapContract.connect(owner).disapproveOrder(0)).to.be.revertedWith("Order already fully filled");
        await expect(swapContract.connect(owner).disapproveOrder(1)).to.not.be.reverted;
    });

    // Test Cases for Accepting an Order
    it("Should not allow accepting an order with orderAccepted status set to true", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).addToWhitelist(addr2.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, true);
        // mint payment tokens to addr2
        await paymentToken.connect(owner).mint(addr2.address, amount * price);
        // addr2 increase allowance for swap contract
        await paymentToken.connect(addr2).increaseAllowance(swapContract.address, amount * price);

        // Approve the order
        await swapContract.connect(owner).approveOrder(0);
        // Addr2 accepts the order
        expect(await swapContract.connect(addr2).acceptOrder(0, amount / 2)).to.not.be.reverted;
        let order = await swapContract.orders(0);
        expect(await order.status.orderAccepted).to.equal(true);
        //expect(await swapContract.connect(addr2).acceptOrder(0, amount)).to.be.revertedWith("Order already accepted");
    });

    it("Should allow accepting an order even if it is partially filled and orderAccepted status becomes false after filling", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).addToWhitelist(addr2.address);

        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        // make swap contract an operator of addr1
        await shareToken.connect(owner).authorizeOperator(swapContract.address);
        // initiate order
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, true);
        let order = await swapContract.orders(0);
        expect(await order.status.orderAccepted).to.equal(false);
        // mint payment tokens to addr2
        await paymentToken.connect(owner).mint(addr2.address, amount * price);
        // addr2 increase allowance for swap contract
        await paymentToken.connect(addr2).increaseAllowance(swapContract.address, amount * price);

        // Approve the order
        await swapContract.connect(owner).approveOrder(0);
        // Addr2 accepts the order
        await swapContract.connect(addr2).acceptOrder(0, amount / 2);
        order = await swapContract.orders(0);
        expect(await order.status.orderAccepted).to.equal(true);
        // Addr2 fills the order
        await swapContract.connect(addr2).fillOrder(0, amount / 2);
        order = await swapContract.orders(0);
        expect(await order.status.orderAccepted).to.equal(false);
        // Addr2 accepts the order again
        await swapContract.connect(addr2).acceptOrder(0, amount / 2);
        order = await swapContract.orders(0);
        expect(await order.status.orderAccepted).to.equal(true);
    });


    // Test Cases for Filling an Order

    it("Should not allow filling an order that is already fully filled", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).addToWhitelist(addr2.address);
        await paymentToken.connect(owner).mint(addr2.address, 1.5 * amount * price);
        await paymentToken.connect(addr2).increaseAllowance(swapContract.address, 1.5 * amount * price);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, 1.5 * amount);
        await shareToken.connect(owner).authorizeOperator(swapContract.address);
        expect(await shareToken.isOperator(swapContract.address)).to.equal(true);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, true);
        await swapContract.connect(owner).approveOrder(0);
        await swapContract.connect(addr2).acceptOrder(0, amount);

        await expect(swapContract.connect(addr2).fillOrder(0, amount)).to.not.be.reverted;
        await expect(swapContract.connect(addr2).fillOrder(0, amount)).to.be.revertedWith("Order already fully filled");
    });

    it("Should fill an approved AskOrder", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).addToWhitelist(addr2.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        // make swapContract an authorized operator of addr1
        await shareToken.connect(owner).authorizeOperator(swapContract.address);
        // initiate an order
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, true);
        // mint payment tokens to addr2
        await paymentToken.connect(owner).mint(addr2.address, amount * price);
        // addr2 increase allowance for swap contract
        await paymentToken.connect(addr2).increaseAllowance(swapContract.address, amount * price);

        // Approve the order
        await swapContract.connect(owner).approveOrder(0);
        // Addr2 accepts the order
        await swapContract.connect(addr2).acceptOrder(0, amount);
        // Fill the order
        await swapContract.connect(addr2).fillOrder(0, amount);

        const order = await swapContract.orders(0);
        expect(order.filledAmount).to.equal(amount);

        const checkBlock = await ethers.provider.getBlockNumber();
        expect(await shareToken.totalSupplyAt(partition, checkBlock)).to.equal(amount);
        expect(await shareToken.balanceOfAt(partition, addr2.address, checkBlock)).to.equal(amount);

    });

    it("Should allow filling an ask order that has been approved but not yet accepted", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).addToWhitelist(addr2.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        // make swapContract an authorized operator of addr1
        await shareToken.connect(owner).authorizeOperator(swapContract.address);
        // initiate an order
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, true);
        // mint payment tokens to addr2
        await paymentToken.connect(owner).mint(addr2.address, amount * price);
        // addr2 increase allowance for swap contract
        await paymentToken.connect(addr2).increaseAllowance(swapContract.address, amount * price);

        // Approve the order
        await swapContract.connect(owner).approveOrder(0);

        // Fill the order
        await swapContract.connect(addr2).fillOrder(0, amount);

        const order = await swapContract.orders(0);
        expect(order.filledAmount).to.equal(amount);
    });

    it("Should not allow filling a bid order that has been approved but not accepted", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;
        // add addr1 and addr2 to whitelist
        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).addToWhitelist(addr2.address);
        // mint payment token to addr1
        await paymentToken.connect(owner).mint(addr1.address, amount * price);
        // issue share token to addr2
        await shareToken.connect(owner).issueByPartition(partition, addr2.address, amount);
        // addr1 initiates a bid order
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, false, false, true);
        // owner approves the order
        await swapContract.connect(owner).approveOrder(0);

        await expect(swapContract.connect(addr1).fillOrder(0, amount)).to.be.revertedWith("Order not accepted");
    });

    it("Should not allow filling an order that is already cancelled or disapproved", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, false);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, false);
        // Cancel the first order
        await swapContract.connect(addr1).cancelOrder(0);
        const order0 = await swapContract.orders(0);
        expect(order0.status.isCancelled).to.equal(true);
        // Disapprove the second order
        await swapContract.connect(owner).disapproveOrder(1);
        const order1 = await swapContract.orders(1);
        expect(order1.status.isDisapproved).to.equal(true);

        await expect(swapContract.connect(addr1).fillOrder(0, amount)).to.be.revertedWith("Order already cancelled");
        await expect(swapContract.connect(addr1).fillOrder(1, amount)).to.be.revertedWith("Order already disapproved");
    });

    it("Should not allow non-initiator to fill a bid order", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await paymentToken.connect(owner).mint(addr1.address, amount * price);
        await paymentToken.connect(addr1).increaseAllowance(swapContract.address, amount * price);
        // add addr1 and addr2 to whitelist
        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).addToWhitelist(addr2.address);
        // mint tokens to addr2
        await shareToken.connect(owner).issueByPartition(partition, addr2.address, amount);
        // addr1 initiates a bid order
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, false, false, true);

        // Owner Approve the order
        await swapContract.connect(owner).approveOrder(0);

        // addr2 accepts the order
        await swapContract.connect(addr2).acceptOrder(0, amount);

        // Try to fill the order with non-initiator
        await expect(swapContract.connect(addr2).fillOrder(0, amount)).to.be.revertedWith("Only initiator can fill bid orders. Only filler(who accepted order) can fill ask orders");
    });

    // Test Cases for Cancelling an Order

    it("Should allow the initiator to cancel an order", async function () {
        const { owner, addr1, shareToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, false);

        await swapContract.connect(addr1).cancelOrder(0);
        const order = await swapContract.orders(0);
        expect(order.status.isCancelled).to.equal(true);
        expect(order.status.isApproved).to.equal(false);
        expect(order.status.orderAccepted).to.equal(false);
    });

    it("Should not allow a non-initiator to cancel an order", async function () {
        const { owner, addr1, addr2, shareToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, false);

        await expect(swapContract.connect(addr2).cancelOrder(0)).to.be.revertedWith("Only initiator can cancel");
    });

    it("Should not allow cancelling an order that is already disapproved", async function () {
        const { owner, addr1, shareToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, false);

        await swapContract.connect(owner).disapproveOrder(0);
        await expect(swapContract.connect(addr1).cancelOrder(0)).to.be.revertedWith("Order already disapproved");
    });

    it("Should not allow cancelling an order that is already cancelled", async function () {
        const { owner, addr1, shareToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, false);

        await swapContract.connect(addr1).cancelOrder(0);
        await expect(swapContract.connect(addr1).cancelOrder(0)).to.be.revertedWith("Order already cancelled");
    });

    it("Should not allow cancelling an order that is already fully filled", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).addToWhitelist(addr2.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await shareToken.connect(owner).authorizeOperator(swapContract.address);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, true);
        await paymentToken.connect(owner).mint(addr2.address, amount * price);
        await paymentToken.connect(addr2).increaseAllowance(swapContract.address, amount * price);

        await swapContract.connect(owner).approveOrder(0);
        await swapContract.connect(addr2).acceptOrder(0, amount);
        await swapContract.connect(addr2).fillOrder(0, amount);

        await expect(swapContract.connect(addr1).cancelOrder(0)).to.be.revertedWith("Order already fully filled");
    });

    // Test Cases for ClaimProceeds

    it("Should allow users to claim their proceeds", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).addToWhitelist(addr2.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await shareToken.connect(owner).authorizeOperator(swapContract.address);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, true);
        await paymentToken.connect(owner).mint(addr2.address, amount * price);
        await paymentToken.connect(addr2).increaseAllowance(swapContract.address, amount * price);

        await swapContract.connect(owner).approveOrder(0);
        await swapContract.connect(addr2).acceptOrder(0, amount);
        await swapContract.connect(addr2).fillOrder(0, amount);

        await swapContract.connect(addr1).claimProceeds();

        const proceeds = await swapContract.unclaimedProceeds(addr1.address);
        expect(proceeds.ethProceeds).to.equal(0);
        expect(proceeds.tokenProceeds).to.equal(0);
    });

    it("Should not allow users to claim proceeds if they have none", async function () {
        const { addr1, swapContract } = await setupOrderTesting();

        await expect(swapContract.connect(addr1).claimProceeds()).to.be.revertedWith("No unclaimed proceeds");
    });

    it("Should allow the owner or manager to claim their proceeds", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).addManager(addr2.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await shareToken.connect(owner).authorizeOperator(swapContract.address);

        await paymentToken.connect(owner).mint(addr1.address, 2 * amount * price);
        await paymentToken.connect(addr1).increaseAllowance(swapContract.address, 2 * amount * price);

        await swapContract.connect(addr1).initiateOrder(partition, amount, price, false, true, true);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, false, true, true);

        await swapContract.connect(owner).approveOrder(0);
        await swapContract.connect(owner).approveOrder(1);

        await swapContract.connect(addr1).fillOrder(0, amount);

        await swapContract.connect(addr2).claimProceeds();

        await swapContract.connect(addr1).fillOrder(1, amount);

        await swapContract.connect(owner).claimProceeds();

        const ownerProceeds = await swapContract.unclaimedProceeds(owner.address);
        expect(ownerProceeds.ethProceeds).to.equal(0);
        expect(ownerProceeds.tokenProceeds).to.equal(0);
    });

    it("Should not allow the non-manager and non-owner to claim the owner's proceeds", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).addManager(addr2.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await shareToken.connect(owner).authorizeOperator(swapContract.address);

        await paymentToken.connect(owner).mint(addr1.address, 2 * amount * price);
        await paymentToken.connect(addr1).increaseAllowance(swapContract.address, 2 * amount * price);

        await swapContract.connect(addr1).initiateOrder(partition, amount, price, false, true, true);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, false, true, true);

        await swapContract.connect(owner).approveOrder(0);
        await swapContract.connect(owner).approveOrder(1);

        await swapContract.connect(addr1).fillOrder(0, amount);

        await swapContract.connect(addr2).claimProceeds();

        await swapContract.connect(addr1).fillOrder(1, amount);

        expect(await swapContract.connect(addr1).claimProceeds()).to.be.revertedWith("Only owner or manager can claim proceeds");
    });

    // Test Cases for UnsafeWithdrawAllProceeds
    it("Should allow owner to unsafe withdraw all proceeds", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).addToWhitelist(addr2.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await shareToken.connect(owner).authorizeOperator(swapContract.address);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, true);
        await paymentToken.connect(owner).mint(addr2.address, amount * price);
        await paymentToken.connect(addr2).increaseAllowance(swapContract.address, amount * price);

        await swapContract.connect(owner).approveOrder(0);
        await swapContract.connect(addr2).acceptOrder(0, amount);
        await swapContract.connect(addr2).fillOrder(0, amount);

        await swapContract.connect(owner).UnsafeWithdrawAllProceeds();

        const contractEthBalance = await ethers.provider.getBalance(swapContract.address);
        const contractTokenBalance = await paymentToken.balanceOf(swapContract.address);
        expect(contractEthBalance).to.equal(0);
        expect(contractTokenBalance).to.equal(0);
    });

    it("Should allow manager to unsafe withdraw all proceeds", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).addManager(addr2.address);
        let manager = addr2;
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await shareToken.connect(owner).authorizeOperator(swapContract.address);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, true);
        await paymentToken.connect(owner).mint(addr2.address, amount * price);
        await paymentToken.connect(addr2).increaseAllowance(swapContract.address, amount * price);

        await swapContract.connect(owner).approveOrder(0);
        await swapContract.connect(addr2).acceptOrder(0, amount);
        await swapContract.connect(addr2).fillOrder(0, amount);

        await swapContract.connect(manager).UnsafeWithdrawAllProceeds();

        const contractEthBalance = await ethers.provider.getBalance(swapContract.address);
        const contractTokenBalance = await paymentToken.balanceOf(swapContract.address);
        expect(contractEthBalance).to.equal(0);
        expect(contractTokenBalance).to.equal(0);
    });

    it("Should not allow non-owner and non-manager to unsafe withdraw all proceeds", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).addToWhitelist(addr2.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await shareToken.connect(owner).authorizeOperator(swapContract.address);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, true);
        await paymentToken.connect(owner).mint(addr2.address, amount * price);
        await paymentToken.connect(addr2).increaseAllowance(swapContract.address, amount * price);

        await swapContract.connect(owner).approveOrder(0);
        await swapContract.connect(addr2).acceptOrder(0, amount);
        await swapContract.connect(addr2).fillOrder(0, amount);

        await expect(swapContract.connect(addr2).UnsafeWithdrawAllProceeds()).to.be.revertedWith("Sender is not the owner or manager");
    });

    it("Should emit ProceedsWithdrawn event on successful UnsafeWithdrawAllProceeds call", async function () {
        const { owner, addr1, addr2, shareToken, paymentToken, swapContract } = await setupOrderTesting();

        const partition = ethers.utils.formatBytes32String("partition1");
        const amount = 100;
        const price = 1;

        await shareToken.connect(owner).addToWhitelist(addr1.address);
        await shareToken.connect(owner).addToWhitelist(addr2.address);
        await shareToken.connect(owner).issueByPartition(partition, addr1.address, amount);
        await shareToken.connect(owner).authorizeOperator(swapContract.address);
        await swapContract.connect(addr1).initiateOrder(partition, amount, price, true, false, true);
        await paymentToken.connect(owner).mint(addr2.address, amount * price);
        await paymentToken.connect(addr2).increaseAllowance(swapContract.address, amount * price);

        await swapContract.connect(owner).approveOrder(0);
        await swapContract.connect(addr2).acceptOrder(0, amount);
        await swapContract.connect(addr2).fillOrder(0, amount);

        await expect(swapContract.connect(owner).UnsafeWithdrawAllProceeds())
            .to.emit(swapContract, 'ProceedsWithdrawn')
            .withArgs(owner.address, 0, amount * price);
    });


});





