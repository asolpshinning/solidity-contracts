// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "../IERC1410.sol"; // Interface for the ERC1410 token contract
import "../openzeppelin/IERC20.sol"; // Interface for the ERC20 token contract
import "../openzeppelin/SafeMath.sol";

contract DividendsDistribution {
    using SafeMath for uint256;

    struct Dividend {
        bytes32 partition;
        uint256 blockNumber;
        uint256 exDividendDate;
        uint256 recordDate;
        uint256 payoutDate;
        uint256 amount;
        uint256 totalSupplyOfShares;
        address payoutToken;
        bool isERC20Payout;
        uint256 amountRemaining;
        bool recycled;
        mapping(address => bool) claimed;
    }

    string public contractVersion = "0.1.3";
    IERC1410 public sharesToken;
    uint256 public reclaimTime;
    mapping(address => uint256) public totalDistributedOf;
    mapping(address => mapping(uint256 => uint256)) public claimedAmount;
    Dividend[] public dividendDetails;

    event DividendDeposited(
        address indexed depositor,
        uint256 dividendIndex,
        uint256 blockNumber,
        uint256 amount,
        bytes32 partition,
        bool isERC20
    );
    event DividendClaimed(
        address indexed claimer,
        uint256 dividendIndex,
        uint256 amount,
        bool isERC20
    );
    event DividendReclaimed(
        address indexed reclaimer,
        uint256 dividendIndex,
        uint256 amount
    );

    modifier onlyOwnerOrManager() {
        require(
            sharesToken.isOwner(msg.sender) ||
                sharesToken.isManager(msg.sender),
            "Sender is not the owner or manager"
        );
        _;
    }

    constructor(IERC1410 _sharesToken, uint256 _reclaimTime) {
        sharesToken = _sharesToken;
        reclaimTime = _reclaimTime;
    }

    function depositDividend(
        uint256 _blockNumber,
        uint256 _exDividendDate,
        uint256 _recordDate,
        uint256 _payoutDate,
        uint256 _amount,
        address _payoutToken,
        bytes32 _partition
    ) external onlyOwnerOrManager returns (uint256) {
        require(_amount > 0, "Amount must be greater than zero");
        require(
            _payoutDate > block.timestamp,
            "Payout date must be in the future"
        );

        uint256 totalSupplyOfShares = sharesToken.totalSupplyAt(
            _partition,
            _blockNumber
        );
        require(
            totalSupplyOfShares > 0,
            "Total supply of shares must be greater than zero"
        );

        // Transfer the ERC20 tokens to this contract
        IERC20(_payoutToken).transferFrom(msg.sender, address(this), _amount);

        totalDistributedOf[_payoutToken] = totalDistributedOf[_payoutToken].add(
            _amount
        );

        uint256 dividendIndex = dividendDetails.length;

        dividendDetails.push();
        Dividend storage newDividend = dividendDetails[dividendIndex];
        newDividend.blockNumber = _blockNumber;
        newDividend.partition = _partition;
        newDividend.exDividendDate = _exDividendDate;
        newDividend.recordDate = _recordDate;
        newDividend.payoutDate = _payoutDate;
        newDividend.amount = _amount;
        newDividend.totalSupplyOfShares = totalSupplyOfShares;
        newDividend.payoutToken = _payoutToken;
        newDividend.isERC20Payout = (_payoutToken != address(0));
        newDividend.amountRemaining = _amount;
        newDividend.recycled = false;

        emit DividendDeposited(
            msg.sender,
            dividendIndex,
            _blockNumber,
            _amount,
            _partition,
            _payoutToken != address(0)
        );

        return dividendIndex;
    }

    function claimDividend(uint256 _dividendIndex) external {
        require(
            _dividendIndex < dividendDetails.length && _dividendIndex >= 0,
            "Invalid dividend index"
        );

        Dividend storage dividend = dividendDetails[_dividendIndex];
        require(
            block.timestamp >= dividend.payoutDate,
            "Cannot claim dividend before payout date"
        );
        require(
            !dividend.claimed[msg.sender],
            "Dividend already claimed by the sender"
        );
        require(!dividend.recycled, "Dividend has been recycled");

        uint256 shareBalance = sharesToken.balanceOfAtByPartition(
            dividend.partition,
            msg.sender,
            dividend.blockNumber
        );
        require(shareBalance > 0, "Sender does not hold any shares");

        uint256 claimAmount = dividend.amount.mul(shareBalance).div(
            dividend.totalSupplyOfShares
        );
        require(
            claimAmount <= dividend.amountRemaining,
            "Insufficient remaining dividend amount"
        );

        if (dividend.isERC20Payout) {
            require(
                dividend.payoutToken != address(0),
                "Invalid payout token address"
            );
            IERC20(dividend.payoutToken).transfer(msg.sender, claimAmount);
        } else {
            payable(msg.sender).transfer(claimAmount);
        }

        dividend.claimed[msg.sender] = true;
        dividend.amountRemaining = dividend.amountRemaining.sub(claimAmount);
        claimedAmount[msg.sender][_dividendIndex] = claimedAmount[msg.sender][
            _dividendIndex
        ].add(claimAmount);

        emit DividendClaimed(
            msg.sender,
            _dividendIndex,
            claimAmount,
            dividend.isERC20Payout
        );
    }

    function reclaimDividend(uint256 _dividendIndex) external {
        require(
            sharesToken.isOwner(msg.sender),
            "Only owner can reclaim dividend"
        );
        require(
            _dividendIndex < dividendDetails.length,
            "Invalid dividend index"
        );

        Dividend storage dividend = dividendDetails[_dividendIndex];
        require(!dividend.recycled, "Dividend has already been recycled");
        require(
            block.timestamp >= dividend.payoutDate.add(reclaimTime),
            "Cannot recycle dividend before reclaim time"
        );

        uint256 remainingAmount = dividend.amountRemaining;
        require(remainingAmount > 0, "No remaining dividend amount to recycle");

        dividend.recycled = true;
        totalDistributedOf[dividend.payoutToken] = totalDistributedOf[
            dividend.payoutToken
        ].sub(remainingAmount);
        dividend.amountRemaining = 0;

        if (dividend.isERC20Payout) {
            require(
                dividend.payoutToken != address(0),
                "Invalid payout token address"
            );
            IERC20(dividend.payoutToken).transfer(msg.sender, remainingAmount);
        } else {
            payable(msg.sender).transfer(remainingAmount);
        }

        emit DividendReclaimed(msg.sender, _dividendIndex, remainingAmount);
    }

    function getClaimableAmount(
        address _address,
        uint256 _dividendIndex
    ) external view returns (uint256) {
        require(
            _dividendIndex < dividendDetails.length,
            "Invalid dividend index"
        );
        Dividend storage dividend = dividendDetails[_dividendIndex];
        if (block.timestamp < dividend.payoutDate) {
            return 0;
        }
        if (
            dividend.claimed[_address] ||
            dividend.recycled ||
            dividend.amountRemaining == 0
        ) {
            return 0;
        }

        uint256 shareBalance = sharesToken.balanceOfAtByPartition(
            dividend.partition,
            _address,
            dividend.blockNumber
        );
        uint256 claimAmount = dividend.amount.mul(shareBalance).div(
            dividend.totalSupplyOfShares
        );
        return claimAmount;
    }

    function hasClaimedDividend(
        address _address,
        uint256 _dividendIndex
    ) external view returns (bool) {
        require(
            _dividendIndex < dividendDetails.length,
            "Invalid dividend index"
        );
        Dividend storage dividend = dividendDetails[_dividendIndex];
        return dividend.claimed[_address];
    }
}
