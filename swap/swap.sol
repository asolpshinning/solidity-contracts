// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "../1400/IERC1410.sol";
import "../1400/erc20/IERC20.sol";

contract SwapContract {
    struct Order {
        address initiator;
        bytes32 partition;
        uint256 amount;
        uint256 price;
        uint256 filledAmount;
        address approvingSeller;
        orderType orderType;
        orderStatus orderStatus;
    }

    struct orderStatus {
        bool isApproved;
        bool isDisapproved;
        bool isCancelled;
        bool sellerAccepted;
    }

    struct orderType {
        bool isShareIssuance;
        bool isSellOrder;
        bool isErc20Payment;
    }

    struct Proceeds {
        uint256 ethProceeds;
        uint256 tokenProceeds;
    }

    IERC1410 public shareToken;
    IERC20 public paymentToken;
    mapping(uint256 => Order) public orders;
    uint256 public nextOrderId = 0;
    mapping(address => Proceeds) public unclaimedProceeds;

    modifier onlyOwnerOrManager() {
        require(
            shareToken.isOwner(msg.sender) || shareToken.isManager(msg.sender),
            "Sender is not the owner or manager"
        );
        _;
    }

    modifier onlyWhitelisted() {
        require(
            shareToken.isWhitelisted(msg.sender),
            "Sender is not whitelisted"
        );
        _;
    }

    constructor(IERC1410 _shareToken, IERC20 _paymentToken) {
        shareToken = _shareToken;
        paymentToken = _paymentToken;
    }

    function initiateOrder(
        bytes32 partition,
        uint256 amount,
        uint256 price,
        bool isSellOrder,
        bool isShareIssuance,
        bool isErc20Payment
    ) public onlyWhitelisted returns (uint256) {
        require(
            isSellOrder
                ? shareToken.balanceOfByPartition(partition, msg.sender) >=
                    amount
                : paymentToken.balanceOf(msg.sender) >= amount * price,
            "Insufficient balance"
        );
        address approvingSeller = isSellOrder ? msg.sender : address(0);
        Order memory newOrder = Order(
            msg.sender,
            partition,
            amount,
            price,
            0,
            approvingSeller,
            orderType(isShareIssuance, isSellOrder, isErc20Payment),
            orderStatus(false, false, false, false)
        );
        orders[nextOrderId] = newOrder;
        return nextOrderId++;
    }

    function approveOrder(uint256 orderId) public onlyOwnerOrManager {
        require(
            !orders[orderId].orderStatus.isDisapproved,
            "Order already disapproved"
        );
        require(
            !orders[orderId].orderStatus.isCancelled,
            "Order already cancelled"
        );
        orders[orderId].orderStatus.isApproved = true;
        if (orders[orderId].orderType.isShareIssuance) {
            orders[orderId].orderStatus.sellerAccepted = true;
            orders[orderId].approvingSeller = shareToken.owner();
        }
    }

    function disapproveOrder(uint256 orderId) public onlyOwnerOrManager {
        require(
            !orders[orderId].orderStatus.isApproved,
            "Order already approved"
        );
        require(
            !orders[orderId].orderStatus.isCancelled,
            "Order already cancelled"
        );
        orders[orderId].orderStatus.isDisapproved = true;
    }

    function sellerAcceptPurchase(uint256 orderId) public onlyWhitelisted {
        require(
            !orders[orderId].orderType.isShareIssuance,
            "This is a share issuance"
        );
        require(
            !orders[orderId].orderStatus.isCancelled,
            "Order already cancelled"
        );
        require(
            orders[orderId].orderStatus.isApproved,
            "Order not approved by manager"
        );
        require(
            !orders[orderId].orderType.isSellOrder,
            "Only purchase orders can be accepted by seller"
        );
        require(
            orders[orderId].filledAmount < orders[orderId].amount,
            "Order already fully filled"
        );
        orders[orderId].orderStatus.sellerAccepted = true;
        orders[orderId].approvingSeller = msg.sender;
    }

    function fillSale(uint256 orderId, uint256 amount) public payable {
        require(
            orders[orderId].orderStatus.isApproved,
            "Order not approved by manager"
        );
        require(
            orders[orderId].orderType.isSellOrder,
            "This is not a sell order"
        );
        require(!orders[orderId].orderStatus.isCancelled, "Order cancelled");
        require(
            orders[orderId].filledAmount + amount <= orders[orderId].amount,
            "Order can't be overfilled"
        );

        Proceeds memory proceeds = unclaimedProceeds[orders[orderId].initiator];

        if (orders[orderId].orderType.isErc20Payment) {
            require(
                paymentToken.transferFrom(
                    msg.sender,
                    address(this),
                    orders[orderId].price * amount
                ),
                "Transfer of PaymentToken from buyer failed"
            );
            proceeds.tokenProceeds += orders[orderId].price * amount;
        } else {
            require(
                msg.value == orders[orderId].price * amount,
                "Incorrect Ether amount sent"
            );
            proceeds.ethProceeds += orders[orderId].price * amount;
        }

        shareToken.operatorTransferByPartition(
            orders[orderId].partition,
            orders[orderId].initiator,
            msg.sender,
            amount
        );

        orders[orderId].filledAmount += amount;
        unclaimedProceeds[orders[orderId].initiator] = proceeds;
    }

    function completePurchaseOrder(uint256 orderId) public payable {
        require(
            !orders[orderId].orderType.isShareIssuance,
            "Cannot complete a share issuance order"
        );
        require(
            orders[orderId].orderStatus.sellerAccepted,
            "Seller has not accepted the purchase order"
        );
        require(!orders[orderId].orderStatus.isCancelled, "Order cancelled");
        require(
            orders[orderId].filledAmount < orders[orderId].amount,
            "Order fully filled"
        );

        Proceeds memory proceeds = unclaimedProceeds[
            orders[orderId].approvingSeller
        ];

        if (orders[orderId].orderType.isErc20Payment) {
            require(
                paymentToken.transferFrom(
                    msg.sender,
                    address(this),
                    orders[orderId].price * orders[orderId].amount
                ),
                "Transfer of PaymentToken from buyer failed"
            );
            proceeds.tokenProceeds +=
                orders[orderId].price *
                orders[orderId].amount;
        } else {
            require(
                msg.value >= orders[orderId].price * orders[orderId].amount,
                "Incorrect Ether amount sent"
            );
            proceeds.ethProceeds +=
                orders[orderId].price *
                orders[orderId].amount;
        }

        shareToken.operatorTransferByPartition(
            orders[orderId].partition,
            orders[orderId].approvingSeller,
            msg.sender,
            orders[orderId].amount
        );

        orders[orderId].filledAmount = orders[orderId].amount;
        unclaimedProceeds[orders[orderId].approvingSeller] = proceeds;
    }

    function completeShareIssuance(uint256 orderId) public payable {
        require(
            orders[orderId].orderType.isShareIssuance,
            "This is not a share issuance"
        );
        require(!orders[orderId].orderStatus.isCancelled, "Order cancelled");
        require(
            orders[orderId].filledAmount < orders[orderId].amount,
            "Order fully filled"
        );

        Proceeds memory proceeds = unclaimedProceeds[
            orders[orderId].approvingSeller
        ];

        if (orders[orderId].orderType.isErc20Payment) {
            require(
                paymentToken.transferFrom(
                    msg.sender,
                    address(this),
                    orders[orderId].price * orders[orderId].amount
                ),
                "Transfer of PaymentToken from buyer failed"
            );
            proceeds.tokenProceeds +=
                orders[orderId].price *
                orders[orderId].amount;
        } else {
            require(
                msg.value >= orders[orderId].price * orders[orderId].amount,
                "Incorrect Ether amount sent"
            );
            proceeds.ethProceeds +=
                orders[orderId].price *
                orders[orderId].amount;
        }

        shareToken.operatorIssueByPartition(
            orders[orderId].partition,
            msg.sender,
            orders[orderId].amount
        );

        orders[orderId].filledAmount = orders[orderId].amount;
        unclaimedProceeds[orders[orderId].approvingSeller] = proceeds;
    }

    function cancelOrder(uint256 orderId) public {
        require(
            msg.sender == orders[orderId].initiator,
            "Only initiator can cancel"
        );
        require(
            !orders[orderId].orderStatus.isDisapproved,
            "Order already disapproved"
        );
        require(
            !orders[orderId].orderStatus.isCancelled,
            "Order already cancelled"
        );
        require(
            orders[orderId].filledAmount < orders[orderId].amount,
            "Order already fully filled"
        );
        orders[orderId].orderStatus.isCancelled = true;
        orders[orderId].orderStatus.isApproved = false;
        orders[orderId].orderStatus.sellerAccepted = false;
    }

    function getOrderDetails(
        uint256 orderId
    ) public view returns (Order memory) {
        return orders[orderId];
    }

    function claimProceeds() public {
        Proceeds storage proceeds = unclaimedProceeds[msg.sender];
        require(
            proceeds.ethProceeds > 0 || proceeds.tokenProceeds > 0,
            "No unclaimed proceeds"
        );

        if (proceeds.ethProceeds > 0) {
            payable(msg.sender).transfer(proceeds.ethProceeds);
            proceeds.ethProceeds = 0;
        }

        if (proceeds.tokenProceeds > 0) {
            require(
                paymentToken.transfer(msg.sender, proceeds.tokenProceeds),
                "ERC20 transfer failed"
            );
            proceeds.tokenProceeds = 0;
        }
    }

    function getUnclaimedProceeds(
        address user
    ) public view returns (Proceeds memory) {
        return unclaimedProceeds[user];
    }

    function getBalanceETH() public view returns (uint256) {
        return address(this).balance;
    }

    function getBalanceERC20() public view returns (uint256) {
        return paymentToken.balanceOf(address(this));
    }
}
