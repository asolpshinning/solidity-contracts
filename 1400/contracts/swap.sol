// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "../IERC1410.sol";
import "../erc20/IERC20.sol";

/// @title SwapContract
/// @dev This contract allows for swapping (buying and selling) of ERC1410 shares where a specified ERC20 token is the payment token.
contract SwapContract {
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
        bool isDisapproved; /// Indicates if the order has been disapproved manager.
        bool isCancelled; /// Indicates if the order has been cancelled.
        bool proposalAccepted; /// Indicates if the proposal has been accepted.
    }

    /// @notice Represents the type of an Order in the swap contract.
    /// @dev Holds all the type details related to a specific order.
    struct orderType {
        bool isShareIssuance; /// Indicates if the order is of type share issuance.
        bool isSellOrder; /// Indicates if the order is a sell order.
        bool isErc20Payment; /// Indicates if the order involves an ERC20 payment.
    }

    /// @notice Represents the proceeds to be claimed by a user in the swap contract.
    /// @dev Holds all the proceeds details related to a specific user.
    struct Proceeds {
        uint256 ethProceeds; /// The amount of Ether to be claimed by the user.
        uint256 tokenProceeds; /// The amount of tokens to be claimed by the user.
    }

    IERC1410 public shareToken;
    IERC20 public paymentToken;
    uint256 public nextOrderId = 0;
    bool public swapApprovalsEnabled = true;
    bool public txnApprovalsEnabled = false;
    mapping(uint256 => Order) public orders;
    mapping(address => Proceeds) public unclaimedProceeds;

    /// @notice Event emitted when proceeds are withdrawn from the contract
    /// @param recipient The address receiving the tokens
    /// @param ethAmount The amount of Ether withdrawn
    /// @param tokenAmount The amount of tokens withdrawn
    event ProceedsWithdrawn(
        address indexed recipient,
        uint256 ethAmount,
        uint256 tokenAmount
    );

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
    /// @dev Checks if the user has sufficient balance to create the order. Creates a new order and adds it to the orders mapping.
    /// @param partition The partition of the token to trade
    /// @param amount The amount of tokens to trade
    /// @param price The price per token of the trade
    /// @param isSellOrder Whether the order is a sell order
    /// @param isShareIssuance Whether the order is a share issuance
    /// @param isErc20Payment Whether the order is an ERC20 payment
    /// @return The ID of the created order
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
        address filler = address(0);
        Order memory newOrder = Order(
            msg.sender,
            partition,
            amount,
            price,
            0,
            filler,
            orderType(isShareIssuance, isSellOrder, isErc20Payment),
            status(false, false, false, false)
        );
        orders[nextOrderId] = newOrder;
        return nextOrderId++;
    }

    /// @notice Approves a given order
    /// @dev Only an owner or manager can call this function. Checks that the order has not already been disapproved, approved or cancelled.
    ///      Also checks whether approvals are enabled. If transaction approvals are enabled, it checks that the proposal has been accepted.
    ///      Finally, if the order is a share issuance, it sets the proposal as accepted and the filler to the owner of the shareToken.
    /// @param orderId The id of the order to approve
    function approveOrder(uint256 orderId) public onlyOwnerOrManager {
        require(
            !orders[orderId].status.isDisapproved,
            "Order already disapproved"
        );
        require(!orders[orderId].status.isApproved, "Order already approved");
        require(!orders[orderId].status.isCancelled, "Order already cancelled");
        require(
            swapApprovalsEnabled || txnApprovalsEnabled,
            "Approvals toggled off, no approval required"
        );
        require(
            (txnApprovalsEnabled && orders[orderId].status.proposalAccepted) ||
                !txnApprovalsEnabled,
            "Proposal must be accepted before approval (if txn approvals are enabled)"
        );
        orders[orderId].status.isApproved = true;
        if (orders[orderId].orderType.isShareIssuance) {
            orders[orderId].status.proposalAccepted = true;
            orders[orderId].filler = shareToken.owner();
        }
    }

    /// @notice Disapproves a given order
    /// @dev Only an owner or manager can call this function. Checks that the order has not already been disapproved or cancelled.
    ///      Also checks whether approvals are enabled, and checks that the order has not been filled yet.
    ///      Finally, it marks the order as disapproved.
    /// @param orderId The id of the order to disapprove
    function disapproveOrder(uint256 orderId) public onlyOwnerOrManager {
        require(
            !orders[orderId].status.isDisapproved,
            "Order already disapproved"
        );
        require(!orders[orderId].status.isCancelled, "Order already cancelled");
        require(
            swapApprovalsEnabled || txnApprovalsEnabled,
            "Approvals toggled off"
        );
        require(
            orders[orderId].filledAmount == 0,
            "Order already partially or fully filled"
        );
        orders[orderId].status.isDisapproved = true;
    }

    /// @notice Accepts a given order
    /// @dev Only a whitelisted address can call this function. Checks that the order is not both a share issuance and purchase order.
    ///      Also checks that the order has not been cancelled and that it has not already been fully filled.
    ///      Finally, it marks the proposal as accepted and sets the filler to the message sender.
    /// @param orderId The id of the order to accept
    function acceptOrder(uint256 orderId) public onlyWhitelisted {
        require(
            !orders[orderId].orderType.isShareIssuance &&
                !orders[orderId].orderType.isSellOrder,
            "This is order is share issuance type"
        );
        require(!orders[orderId].status.isCancelled, "Order already cancelled");
        require(
            orders[orderId].filledAmount < orders[orderId].amount,
            "Order already fully filled"
        );
        orders[orderId].status.proposalAccepted = true;
        orders[orderId].filler = msg.sender;
    }

    /// @notice Checks whether a given order can be filled with a specific amount
    /// @dev Checks if the order has not been cancelled, that it has been approved and that it won't be overfilled by filling it with the specified amount.
    ///      Also checks that if the order is a purchase order, the message sender is the initiator of the order.
    ///      If the order is a sell order, it checks that the message sender is the filler of the order (address that accepted the order).
    ///      Finally, if approvals are enabled, it checks that the order has been approved by the manager.
    ///      Returns true if all checks pass.
    /// @param orderId The id of the order to check
    /// @param amount The amount to fill the order with
    /// @return Returns true if the order can be filled, false otherwise
    function canFillOrder(
        uint256 orderId,
        uint256 amount
    ) public view returns (bool) {
        require(!orders[orderId].status.isCancelled, "Order already cancelled");
        require(
            ((orders[orderId].status.isApproved &&
                (swapApprovalsEnabled || txnApprovalsEnabled)) ||
                (!swapApprovalsEnabled && !txnApprovalsEnabled)),
            "Order must be approved by manager (approvals are toggled on)"
        );
        require(
            !orders[orderId].orderType.isSellOrder &&
                msg.sender == orders[orderId].initiator,
            "Only initiator can fill purchase orders"
        );
        require(
            orders[orderId].orderType.isSellOrder &&
                msg.sender == orders[orderId].filler,
            "Only filler who accepted order can fill sell orders"
        );
        require(
            orders[orderId].filledAmount + amount <= orders[orderId].amount,
            "Order can't be overfilled"
        );
        return true;
    }

    /// @notice Fills a given order with a specific amount
    /// @dev Checks if the order is a sell order and fills it using `_fillSale`, otherwise it fills it using `_fillPurchase`.
    /// @param orderId The id of the order to fill
    /// @param amount The amount to fill the order with
    function fillOrder(uint256 orderId, uint256 amount) public payable {
        if (orders[orderId].orderType.isSellOrder) {
            _fillSale(orderId, amount);
        } else {
            _fillPurchase(orderId, amount);
        }
    }

    /// @notice Fills a sale order
    /// @dev This internal function can only be called by the contract itself. Checks if the order can be filled and transfers
    ///      the payment (in either ERC20 tokens or ETH) from the buyer to the contract. If the order is a share issuance,
    ///      it issues new shares to the filler, otherwise it transfers shares from the initiator to the filler.
    /// @param orderId The id of the order to fill
    /// @param amount The amount to fill the order with
    function _fillSale(uint256 orderId, uint256 amount) internal {
        require(canFillOrder(orderId, amount), "Order cannot be filled");

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

        if (orders[orderId].orderType.isShareIssuance) {
            shareToken.operatorIssueByPartition(
                orders[orderId].partition,
                orders[orderId].filler,
                amount
            );
        } else {
            shareToken.operatorTransferByPartition(
                orders[orderId].partition,
                orders[orderId].initiator,
                orders[orderId].filler,
                amount
            );
        }
        orders[orderId].filledAmount += amount;
        unclaimedProceeds[orders[orderId].initiator] = proceeds;
    }

    /// @notice Fills a purchase order
    /// @dev This internal function can only be called by the contract itself. Checks if the order can be filled and transfers
    ///      the payment (in either ERC20 tokens or ETH) from the buyer to the contract. If the order is a share issuance,
    ///      it issues new shares to the initiator, otherwise it transfers shares from the filler (address who accepted order) to the initiator.
    /// @param orderId The id of the order to fill
    /// @param amount The amount to fill the order with
    function _fillPurchase(uint256 orderId, uint256 amount) internal {
        require(canFillOrder(orderId, amount), "Order cannot be filled");
        Proceeds memory proceeds = unclaimedProceeds[orders[orderId].filler];

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

        if (orders[orderId].orderType.isShareIssuance) {
            shareToken.operatorIssueByPartition(
                orders[orderId].partition,
                orders[orderId].initiator,
                orders[orderId].amount
            );
        } else {
            shareToken.operatorTransferByPartition(
                orders[orderId].partition,
                orders[orderId].filler,
                orders[orderId].initiator,
                orders[orderId].amount
            );
        }
        orders[orderId].filledAmount += orders[orderId].amount;
        unclaimedProceeds[orders[orderId].filler] = proceeds;
    }

    /// @notice Cancels an order
    /// @dev This function can only be called by the initiator of the order.
    ///      It requires the order to not be fully filled, disapproved or cancelled.
    /// @param orderId The id of the order to cancel
    function cancelOrder(uint256 orderId) public {
        require(
            msg.sender == orders[orderId].initiator,
            "Only initiator can cancel"
        );
        require(
            !orders[orderId].status.isDisapproved,
            "Order already disapproved"
        );
        require(!orders[orderId].status.isCancelled, "Order already cancelled");
        require(
            orders[orderId].filledAmount < orders[orderId].amount,
            "Order already fully filled"
        );
        orders[orderId].status.isCancelled = true;
        orders[orderId].status.isApproved = false;
        orders[orderId].status.proposalAccepted = false;
    }

    /// @notice Allows a user to claim their unclaimed proceeds
    /// @dev Transfers ETH and ERC20 token proceeds to the caller, if any exist.
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
    function UnsafeWithdrawAllProceeds()
        public
        onlyOwnerOrManager
        returns (bool success)
    {
        uint256 ethAmount = address(this).balance;
        uint256 tokenAmount = paymentToken.balanceOf(address(this));

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

    /// @notice Returns the current status of swap approvals
    /// @dev This function doesn't modify state and can be freely called.
    /// @return The current status of swap approvals
    function isSwapApprovalEnabled() external view returns (bool) {
        return swapApprovalsEnabled;
    }

    /// @notice Returns the current status of transaction approvals
    /// @dev This function doesn't modify state and can be freely called.
    /// @return The current status of transaction approvals
    function isTxnApprovalEnabled() external view returns (bool) {
        return txnApprovalsEnabled;
    }

    /// @notice Fetches details of an order
    /// @param orderId The id of the order whose details are to be fetched
    /// @return The Order struct of the specified order
    function getOrderDetails(
        uint256 orderId
    ) public view returns (Order memory) {
        return orders[orderId];
    }

    /// @notice Fetches the unclaimed proceeds of a user
    /// @param user The address of the user whose unclaimed proceeds are to be fetched
    /// @return The Proceeds struct of the specified user
    function getUnclaimedProceeds(
        address user
    ) public view returns (Proceeds memory) {
        return unclaimedProceeds[user];
    }

    /// @notice Fetches the balance of ETH held by the contract
    /// @return The amount of ETH (in wei) held by the contract
    function getBalanceETH() public view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Fetches the balance of the payment token held by the contract
    /// @return The amount of the payment token held by the contract
    function getBalanceERC20() public view returns (uint256) {
        return paymentToken.balanceOf(address(this));
    }
}
