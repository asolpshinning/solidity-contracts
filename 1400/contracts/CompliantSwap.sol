// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "../IERC1410.sol";
import "../erc20/IERC20.sol";

/// @title CompliantSwap
/// @dev This contract allows for swapping (using ask and bid orders) of ERC1410 shares where a specified ERC20 token or ETH is the payment token.
contract CompliantSwap {
    /// @notice Represents an Order in the swap contract.
    /// @dev Holds all the details related to a specific order.
    struct Order {
        address initiator; /// The address that initiated the order.
        bytes32 partition; /// The partition of the token to be swapped.
        uint256 amount; /// The amount of tokens to be swapped.
        uint256 price; /// The price per token for the swap.
        uint256 filledAmount; /// The amount of tokens already swapped.
        address filler; /// The address that fills the order.
        orderType orderType; /// The type of the order.
        status status; /// The status of the order.
    }

    /// @notice Represents the status of an Order in the swap contract.
    /// @dev Holds all the status details related to a specific order.
    struct status {
        bool isApproved; /// Indicates if the order has been approved by manager.
        bool isCancelled; /// Indicates if the order has been cancelled.
        bool orderAccepted; /// Indicates if the initiated order has been accepted.
    }

    /// @notice Represents the type of an Order in the swap contract.
    /// @dev Holds all the type details related to a specific order.
    struct orderType {
        bool isShareIssuance; /// Indicates if the order is of type share issuance.
        bool isAskOrder; /// Indicates if the order is an ask order.
        bool isErc20Payment; /// Indicates if the order involves an ERC20 payment.
    }

    /// @notice Represents the proceeds to be claimed by a user in the swap contract.
    /// @dev Holds all the proceeds details related to a specific user.
    struct Proceeds {
        uint256 ethProceeds; /// The amount of Ether to be claimed by the user.
        uint256 tokenProceeds; /// The amount of tokens to be claimed by the user.
    }

    string public contractVersion = "0.1.6"; /// The version of the contract.
    IERC1410 public shareToken; /// The ERC1410 token that the contract will interact with.
    IERC20 public paymentToken; /// The ERC20 token that the contract will interact with.
    uint256 public nextOrderId = 0; /// The id of the next order to be created.
    bool public swapApprovalsEnabled = true; /// Indicates if swap approvals are enabled.
    bool public txnApprovalsEnabled = true; /// Indicates if transaction approvals are enabled.
    mapping(uint256 => Order) public orderDetails; /// The mapping of order ids to orders.
    mapping(address => Proceeds) public unclaimedProceeds; /// The mapping of addresses to proceeds.
    mapping(address => bool) public cannotPurchase; /// The mapping of addresses to cannotPurchase status.
    // mapping of addresses to orderId and then mapped to uint256 to indicate order quantity accepted
    mapping(address => mapping(uint256 => uint256)) public acceptedOrderQty; /// The mapping of addresses to accepted orders.

    /// @notice Event emitted when proceeds are withdrawn from the contract
    /// @param recipient The address receiving the tokens
    /// @param ethAmount The amount of Ether withdrawn
    /// @param tokenAmount The amount of tokens withdrawn
    event ProceedsWithdrawn(
        address indexed recipient,
        uint256 ethAmount,
        uint256 tokenAmount
    );

    /// @notice Event emitted when an order is reset by owner or manager
    /// @param orderId The id of the order
    /// @param timestamp The timestamp of the reset
    event OrderReset(uint256 indexed orderId, uint256 timestamp);

    /// @notice Modifier to check if the sender is the owner or manager of the shares token contract
    modifier onlyOwnerOrManager() {
        require(
            shareToken.isOwner(msg.sender) || shareToken.isManager(msg.sender),
            "Sender is not the owner or manager"
        );
        _;
    }

    /// @notice Modifier to check if the sender is whitelisted on the shares token contract
    modifier onlyWhitelisted() {
        require(
            shareToken.isWhitelisted(msg.sender),
            "Sender is not whitelisted"
        );
        _;
    }

    /// @notice Constructor for the SwapContract.
    /// @dev Initializes the shareToken and paymentToken.
    /// @param _shareToken The share token that the contract will interact with.
    /// @param _paymentToken The payment token that the contract will interact with.
    constructor(IERC1410 _shareToken, IERC20 _paymentToken) {
        shareToken = _shareToken;
        paymentToken = _paymentToken;
    }

    /// @notice Initiate a new order
    /// @dev Checks if the user has sufficient balance to create the order.
    ///      Checks if the user is not in the cannotPurchase mapping, if the order is an ask order.
    ///      Checks if the user is the owner or manager of the share token, if the order is a share issuance ask order.
    ///      Creates a new order and adds it to the orders mapping.
    ///      Increments the nextOrderId. Returns the id of the created order.
    /// @param partition The partition of the token to trade
    /// @param amount The amount of tokens to trade
    /// @param price The price per token of the trade
    /// @param isAskOrder Whether the order is an ask order
    /// @param isShareIssuance Whether the order is a share issuance
    /// @param isErc20Payment Whether the order is an ERC20 payment
    /// @return The ID of the created order
    function initiateOrder(
        bytes32 partition,
        uint256 amount,
        uint256 price,
        bool isAskOrder,
        bool isShareIssuance,
        bool isErc20Payment
    ) public onlyWhitelisted returns (uint256) {
        require(
            (isAskOrder &&
                isShareIssuance &&
                (shareToken.isOwner(msg.sender) ||
                    shareToken.isManager(msg.sender))) ||
                (!isAskOrder && isShareIssuance) ||
                !isShareIssuance,
            "Only owner or manager can create share issuance ask orders"
        );
        if (isAskOrder) {
            if (!isShareIssuance) {
                require(
                    shareToken.balanceOfByPartition(partition, msg.sender) >=
                        amount,
                    "Swap: Insufficient balance"
                );
            }
        } else {
            if (isErc20Payment) {
                require(
                    paymentToken.balanceOf(msg.sender) >= amount * price,
                    "Swap: Insufficient balance"
                );
            } else {
                require(
                    msg.sender.balance >= amount * price,
                    "Swap: Insufficient balance"
                );
            }
        }
        require(
            (!cannotPurchase[msg.sender] && !isAskOrder) || isAskOrder,
            "Cannot purchase from this address"
        );
        address filler = address(0);
        Order memory newOrder = Order(
            msg.sender,
            partition,
            amount,
            price,
            0,
            filler,
            orderType(isShareIssuance, isAskOrder, isErc20Payment),
            status(false, false, false)
        );
        orderDetails[nextOrderId] = newOrder;
        return nextOrderId++;
    }

    /// @notice Approves a given order
    /// @dev Only an owner or manager can call this function. Checks that the order has not already been disapproved, approved or cancelled.
    ///      Also checks whether approvals are enabled. If transaction approvals are enabled, it checks that the initiated order has been accepted.
    ///      Finally, if the order is a share issuance and bid order, it sets the initiated order as accepted and the filler to the owner of the share token contract.
    /// @param orderId The id of the order to approve
    function approveOrder(uint256 orderId) public onlyOwnerOrManager {
        require(
            swapApprovalsEnabled || txnApprovalsEnabled,
            "Approvals toggled off, no approval required"
        );

        require(
            !orderDetails[orderId].status.isApproved,
            "Order already approved"
        );
        require(
            !orderDetails[orderId].status.isCancelled,
            "Order already cancelled"
        );
        require(
            (txnApprovalsEnabled &&
                orderDetails[orderId].status.orderAccepted &&
                orderDetails[orderId].orderType.isShareIssuance &&
                orderDetails[orderId].orderType.isAskOrder) ||
                (txnApprovalsEnabled &&
                    orderDetails[orderId].status.orderAccepted &&
                    !orderDetails[orderId].orderType.isShareIssuance) ||
                (orderDetails[orderId].orderType.isShareIssuance &&
                    !orderDetails[orderId].orderType.isAskOrder) ||
                !txnApprovalsEnabled,
            "Initiated orders must be accepted before approval (if txn approvals are enabled)"
        );
        orderDetails[orderId].status.isApproved = true;
        if (orderDetails[orderId].orderType.isShareIssuance) {
            orderDetails[orderId].status.orderAccepted = true;
            if (!orderDetails[orderId].orderType.isAskOrder) {
                orderDetails[orderId].filler = shareToken.owner();
                acceptedOrderQty[orderDetails[orderId].filler][
                    orderId
                ] = orderDetails[orderId].amount;
            }
        }
    }

    /// @notice Disapproves a given order
    /// @dev Only an owner or manager can call this function. Checks that the order has not already been cancelled.
    ///      Also checks that the order has not been fully filled yet.
    /// @param orderId The id of the order to reset
    function managerResetOrder(uint256 orderId) public onlyOwnerOrManager {
        require(
            !orderDetails[orderId].status.isCancelled,
            "Order already cancelled"
        );

        require(
            orderDetails[orderId].filledAmount < orderDetails[orderId].amount,
            "Order already fully filled"
        );
        orderDetails[orderId].status.isApproved = false;
        orderDetails[orderId].status.orderAccepted = false;
        acceptedOrderQty[orderDetails[orderId].filler][orderId] = 0;
        orderDetails[orderId].filler = address(0);

        // emit an event that the order has been reset
        emit OrderReset(orderId, block.timestamp);
    }

    /// @notice Accepts a given order
    /// @dev Only a whitelisted address can call this function. Checks that the order is not both a share issuance and bid order.
    ///      Also checks that the user is not in the cannotPurchase mapping, if the order is an ask order.
    ///      Also checks that the order has not been cancelled and that it has not already been fully filled.
    ///      Checks that the order has not already been accepted.
    ///      Finally, it marks the initiated order as accepted and sets the filler to the message sender.
    /// @param orderId The id of the order to accept
    /// @param amount The amount of order shares to accept to sell / buy
    function acceptOrder(
        uint256 orderId,
        uint256 amount
    ) public onlyWhitelisted {
        require(
            (orderDetails[orderId].orderType.isShareIssuance &&
                orderDetails[orderId].orderType.isAskOrder) ||
                !orderDetails[orderId].orderType.isShareIssuance,
            "Cannot accept a share issuance bid order"
        );
        require(
            (orderDetails[orderId].orderType.isAskOrder &&
                cannotPurchase[msg.sender] == false) ||
                !orderDetails[orderId].orderType.isAskOrder,
            "You cannot purchase shares at this time"
        );
        require(
            !orderDetails[orderId].status.isCancelled,
            "Order already cancelled"
        );
        require(
            !orderDetails[orderId].status.orderAccepted,
            "Order already accepted"
        );
        require(
            orderDetails[orderId].filledAmount < orderDetails[orderId].amount,
            "Order already fully filled"
        );
        require(
            amount <=
                orderDetails[orderId].amount -
                    orderDetails[orderId].filledAmount,
            "Cannot accept to overfill order"
        );
        orderDetails[orderId].status.orderAccepted = true;
        orderDetails[orderId].filler = msg.sender;
        acceptedOrderQty[msg.sender][orderId] = amount;
    }

    /// @notice Cancels the acceptance of a given order
    /// @dev Only a whitelisted address can call this function.
    ///      Checks that the order has been accepted and that the message sender is the filler of the order.
    ///      Finally, it marks the order as not accepted and sets the filler to address(0).
    /// @param orderId The id of the order to cancel acceptance of
    function cancelAcceptance(uint256 orderId) public onlyWhitelisted {
        require(
            orderDetails[orderId].status.orderAccepted,
            "Order not accepted"
        );
        require(
            orderDetails[orderId].filler == msg.sender,
            "Only filler can cancel acceptance"
        );
        orderDetails[orderId].status.orderAccepted = false;
        orderDetails[orderId].filler = address(0);
        acceptedOrderQty[msg.sender][orderId] = 0;
    }

    /// @notice Checks whether a given order can be filled with a specific amount
    /// @dev Checks if the order has not been cancelled, that it has been approved and that it won't be overfilled by filling it with the specified amount.
    ///      Also checks that if the order is a bid order, the message sender is the initiator of the order.
    ///      If the order is an ask order, it checks that the message sender is the filler of the order (address that accepted the order).
    ///      If transaction approvals are enabled, it checks that the order has been accepted by the other party.
    ///      If transaction approvals are disabled and it is a bid order, it checks that the order has been accepted by the other party.
    ///      Finally, if approvals are enabled, it checks that the order has been approved by the manager.
    ///      Returns true if all checks pass.
    /// @param orderId The id of the order to check
    /// @param amount The amount to fill the order with
    /// @return Returns true if the order can be filled, false otherwise
    function canFillOrder(
        uint256 orderId,
        uint256 amount
    ) public view returns (bool) {
        require(
            !orderDetails[orderId].status.isCancelled,
            "Order already cancelled"
        );
        if (
            (!orderDetails[orderId].orderType.isAskOrder &&
                !txnApprovalsEnabled) || txnApprovalsEnabled
        ) {
            require(
                orderDetails[orderId].status.orderAccepted,
                "Order not accepted"
            );
        }
        require(
            ((orderDetails[orderId].status.isApproved &&
                (swapApprovalsEnabled || txnApprovalsEnabled)) ||
                (!swapApprovalsEnabled && !txnApprovalsEnabled)),
            "Order must be approved by manager (approvals are toggled on)"
        );
        require(
            (!orderDetails[orderId].orderType.isAskOrder &&
                msg.sender == orderDetails[orderId].initiator) ||
                (orderDetails[orderId].orderType.isAskOrder &&
                    msg.sender == orderDetails[orderId].filler &&
                    txnApprovalsEnabled) ||
                (orderDetails[orderId].orderType.isAskOrder &&
                    !txnApprovalsEnabled),
            "Only initiator can fill bid orders. Only filler(who accepted order) can fill ask orders"
        );

        require(
            orderDetails[orderId].filledAmount + amount <=
                orderDetails[orderId].amount,
            "Order already fully filled"
        );
        return true;
    }

    /// @notice Fills a given order with a specific amount
    /// @dev Checks if the order is an ask order and fills it using `_fillAsk`, otherwise it fills it using `_fillBid`.
    /// @param orderId The id of the order to fill
    /// @param amt The amount to fill the order with if not already accepted (in the case of an ask order)
    function fillOrder(
        uint256 orderId,
        uint256 amt
    ) public payable onlyWhitelisted {
        if (orderDetails[orderId].orderType.isAskOrder) {
            _fillAsk(orderId, amt);
        } else {
            _fillBid(orderId);
        }
        if (txnApprovalsEnabled) {
            orderDetails[orderId].status.isApproved = false;
        }
    }

    /// @notice Fills a sale order
    /// @dev This internal function can only be called by the contract itself. Checks if the order can be filled and transfers
    ///      the payment (in either ERC20 tokens or ETH) from the buyer to the contract. If the order is a share issuance,
    ///      it issues new shares to the filler, otherwise it transfers shares from the initiator to the filler.
    ///      It updates the orderAccepted of the order to false, after the order has been partially or fully filled.
    ///      Finally, it updates the filled amount of the order and the unclaimed proceeds of the initiator.
    /// @param orderId The id of the order to fill
    function _fillAsk(uint256 orderId, uint256 amt) internal {
        uint256 amount = acceptedOrderQty[msg.sender][orderId];

        Proceeds memory proceeds = unclaimedProceeds[
            orderDetails[orderId].initiator
        ];

        if (
            orderDetails[orderId].orderType.isAskOrder && !txnApprovalsEnabled
        ) {
            amount = amt;
            orderDetails[orderId].filler = msg.sender;
        }

        require(canFillOrder(orderId, amount), "Order cannot be filled");

        if (orderDetails[orderId].orderType.isErc20Payment) {
            require(
                paymentToken.transferFrom(
                    msg.sender,
                    address(this),
                    orderDetails[orderId].price * amount
                ),
                "Transfer of PaymentToken from buyer failed"
            );
            proceeds.tokenProceeds += orderDetails[orderId].price * amount;
        } else {
            require(
                msg.value == orderDetails[orderId].price * amount,
                "Incorrect Ether amount sent to fill ask order"
            );
            proceeds.ethProceeds += orderDetails[orderId].price * amount;
        }

        if (orderDetails[orderId].orderType.isShareIssuance) {
            shareToken.operatorIssueByPartition(
                orderDetails[orderId].partition,
                orderDetails[orderId].filler,
                amount
            );
        } else {
            shareToken.operatorTransferByPartition(
                orderDetails[orderId].partition,
                orderDetails[orderId].initiator,
                orderDetails[orderId].filler,
                amount
            );
        }
        orderDetails[orderId].filledAmount += amount;
        orderDetails[orderId].status.orderAccepted = false;
        unclaimedProceeds[orderDetails[orderId].initiator] = proceeds;
    }

    /// @notice Fills a bid order
    /// @dev This internal function can only be called by the contract itself. Checks if the order can be filled and transfers
    ///      the payment (in either ERC20 tokens or ETH) from the buyer to the contract. If the order is a share issuance,
    ///      it issues new shares to the initiator, otherwise it transfers shares from the filler (address who accepted order) to the initiator.
    /// @param orderId The id of the order to fill
    function _fillBid(uint256 orderId) internal {
        uint256 amount = acceptedOrderQty[orderDetails[orderId].filler][
            orderId
        ];
        require(canFillOrder(orderId, amount), "Order cannot be filled");
        Proceeds memory proceeds = unclaimedProceeds[
            orderDetails[orderId].filler
        ];

        if (orderDetails[orderId].orderType.isErc20Payment) {
            require(
                paymentToken.transferFrom(
                    msg.sender,
                    address(this),
                    orderDetails[orderId].price * amount
                ),
                "Transfer of PaymentToken from buyer failed"
            );
            proceeds.tokenProceeds += orderDetails[orderId].price * amount;
        } else {
            require(
                msg.value >=
                    orderDetails[orderId].price * orderDetails[orderId].amount,
                "Incorrect Ether amount sent to fill bid order"
            );
            proceeds.ethProceeds += orderDetails[orderId].price * amount;
        }

        if (orderDetails[orderId].orderType.isShareIssuance) {
            shareToken.operatorIssueByPartition(
                orderDetails[orderId].partition,
                orderDetails[orderId].initiator,
                amount
            );
        } else {
            shareToken.operatorTransferByPartition(
                orderDetails[orderId].partition,
                orderDetails[orderId].filler,
                orderDetails[orderId].initiator,
                amount
            );
        }
        orderDetails[orderId].filledAmount += amount;
        orderDetails[orderId].status.orderAccepted = false;
        unclaimedProceeds[orderDetails[orderId].filler] = proceeds;
    }

    /// @notice Cancels an order
    /// @dev This function can only be called by the initiator of the order.
    ///      It requires the order to not be fully filled, disapproved or cancelled.
    /// @param orderId The id of the order to cancel
    function cancelOrder(uint256 orderId) public {
        require(
            msg.sender == orderDetails[orderId].initiator,
            "Only initiator can cancel"
        );
        require(
            !orderDetails[orderId].status.isCancelled,
            "Order already cancelled"
        );
        require(
            orderDetails[orderId].filledAmount < orderDetails[orderId].amount,
            "Order already fully filled"
        );
        orderDetails[orderId].status.isCancelled = true;
        orderDetails[orderId].status.isApproved = false;
        orderDetails[orderId].status.orderAccepted = false;
    }

    /// @notice Allows a user to claim their unclaimed proceeds
    /// @dev Transfers ETH and ERC20 token proceeds to the caller, if any exist.
    /// @dev Users may have unclaimed proceeds if they were the initiator or filler of an order.
    ///      Also, the owner or manager of the contract can claim the contract owner's proceeds.
    function claimProceeds() public {
        Proceeds storage proceeds = unclaimedProceeds[msg.sender];
        Proceeds storage ownerProceeds = unclaimedProceeds[shareToken.owner()];
        require(
            proceeds.ethProceeds > 0 ||
                proceeds.tokenProceeds > 0 ||
                ownerProceeds.ethProceeds > 0 ||
                ownerProceeds.tokenProceeds > 0,
            "No unclaimed proceeds"
        );

        if (proceeds.ethProceeds > 0) {
            payable(msg.sender).transfer(proceeds.ethProceeds);
            proceeds.ethProceeds = 0;
        }

        if (
            ownerProceeds.ethProceeds > 0 &&
            (msg.sender == shareToken.owner() ||
                shareToken.isManager(msg.sender))
        ) {
            payable(msg.sender).transfer(ownerProceeds.ethProceeds);
            ownerProceeds.ethProceeds = 0;
        }

        if (proceeds.tokenProceeds > 0) {
            require(
                paymentToken.transfer(msg.sender, proceeds.tokenProceeds),
                "ERC20 transfer failed"
            );
            proceeds.tokenProceeds = 0;
        }

        if (
            ownerProceeds.tokenProceeds > 0 &&
            (msg.sender == shareToken.owner() ||
                shareToken.isManager(msg.sender))
        ) {
            require(
                paymentToken.transfer(msg.sender, ownerProceeds.tokenProceeds),
                "ERC20 transfer failed"
            );
            ownerProceeds.tokenProceeds = 0;
        }
        emit ProceedsWithdrawn(
            msg.sender,
            proceeds.ethProceeds,
            proceeds.tokenProceeds
        );
    }

    /// @notice Withdraws all ERC20 payment tokens from the contract to the caller's address
    /// @dev This function can only be called by the owner or a manager
    ///      This function is unsafe as investors who have not claimed their proceeds will not be able to do so after this function is called
    /// @return success A boolean indicating whether the withdrawal was successful
    function UnsafeWithdrawAllProceeds() public returns (bool success) {
        uint256 ethAmount = address(this).balance;
        uint256 tokenAmount = paymentToken.balanceOf(address(this));

        // require only owner can withdraw
        require(msg.sender == shareToken.owner(), "Only owner can withdraw");

        // Ensuring the contract has ether balance before attempting transfer
        if (ethAmount > 0) {
            (bool okay, ) = msg.sender.call{value: ethAmount}("");
            require(okay, "Withdrawal of Ether failed");
        }

        // Ensuring the contract has token balance before attempting transfer
        if (tokenAmount > 0) {
            require(
                paymentToken.transfer(msg.sender, tokenAmount),
                "Withdrawal of PaymentToken failed"
            );
        }

        emit ProceedsWithdrawn(msg.sender, ethAmount, tokenAmount);
        return true;
    }

    /// @notice Toggles the swap approval functionality
    /// @dev Only callable by the owner or manager of the contract.
    function toggleSwapApprovals() external onlyOwnerOrManager {
        swapApprovalsEnabled = !swapApprovalsEnabled;
    }

    /// @notice Toggles the transaction approval functionality
    /// @dev Only callable by the owner or manager of the contract.
    function toggleTxnApprovals() external onlyOwnerOrManager {
        txnApprovalsEnabled = !txnApprovalsEnabled;
    }

    /// @notice Bans an address from initiating bid orders or accepting ask orders
    /// @dev This function can only be called by the contract owner or manager.
    /// @param _address The address to ban
    function banAddress(address _address) external onlyOwnerOrManager {
        cannotPurchase[_address] = true;
    }
}
