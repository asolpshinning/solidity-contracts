// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "../1400/IERC1410.sol"; // Interface for the ERC1410 token contract
import "../1400/openzeppelin/IERC20.sol"; // Interface for the ERC20 token contract
import "../1400/openzeppelin/SafeMath.sol";

contract DividendsDistribution {
    using SafeMath for uint256;

    struct Dividend {
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

    IERC1410 public sharesToken;
    address public issuer;
    uint256 public reclaim_time;
    mapping(address => uint256) public balances;
    Dividend[] public dividends;

    event DividendDeposited(
        address indexed depositor,
        uint256 dividendIndex,
        uint256 blockNumber,
        uint256 amount,
        bool isERC20
    );
    event DividendClaimed(
        address indexed claimer,
        uint256 dividendIndex,
        uint256 amount,
        bool isERC20
    );
    event DividendRecycled(
        address indexed recycler,
        uint256 dividendIndex,
        uint256 amount
    );

    modifier onlyIssuer() {
        require(msg.sender == issuer, "Sender is not the issuer");
        _;
    }

    constructor(IERC1410 _sharesToken, address _issuer, uint256 _reclaim_time) {
        sharesToken = _sharesToken;
        issuer = _issuer;
        reclaim_time = _reclaim_time;
    }

    function depositDividend(
        uint256 _blockNumber,
        uint256 _exDividendDate,
        uint256 _recordDate,
        uint256 _payoutDate,
        uint256 _amount,
        address _payoutToken
    ) external onlyIssuer {
        require(_amount > 0, "Amount must be greater than zero");
        require(
            _payoutDate > block.timestamp,
            "Payout date must be in the future"
        );

        uint256 totalSupplyOfShares = sharesToken.totalSupply();
        require(
            totalSupplyOfShares > 0,
            "Total supply of shares must be greater than zero"
        );

        uint256 balance = sharesToken.balanceOf(address(this));
        require(
            balance >= totalSupplyOfShares,
            "Contract must hold all shares"
        );

        balances[_payoutToken] = balances[_payoutToken].add(_amount);

        uint256 dividendIndex = dividends.length;

        dividends.push();
        Dividend storage newDividend = dividends[dividendIndex];
        newDividend.blockNumber = _blockNumber;
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
            _payoutToken != address(0)
        );
    }

    function claimDividend(uint256 _dividendIndex) external {
        require(_dividendIndex < dividends.length, "Invalid dividend index");

        Dividend storage dividend = dividends[_dividendIndex];
        require(
            block.timestamp >= dividend.payoutDate,
            "Cannot claim dividend before payout date"
        );
        require(
            !dividend.claimed[msg.sender],
            "Dividend already claimed by the sender"
        );
        require(!dividend.recycled, "Dividend has been recycled");

        uint256 shareBalance = sharesToken.balanceOf(msg.sender);
        require(shareBalance > 0, "Sender does not hold any shares");

        uint256 claimAmount = dividend.amount.mul(shareBalance).div(
            dividend.totalSupplyOfShares
        );
        require(
            claimAmount <= dividend.amountRemaining,
            "Insufficient remaining dividend amount"
        );

        dividend.claimed[msg.sender] = true;
        dividend.amountRemaining = dividend.amountRemaining.sub(claimAmount);
        if (dividend.isERC20Payout) {
            require(
                dividend.payoutToken != address(0),
                "Invalid payout token address"
            );
            IERC20(dividend.payoutToken).transfer(msg.sender, claimAmount);
        } else {
            payable(msg.sender).transfer(claimAmount);
        }

        emit DividendClaimed(
            msg.sender,
            _dividendIndex,
            claimAmount,
            dividend.isERC20Payout
        );
    }

    function recycleDividend(uint256 _dividendIndex) external onlyIssuer {
        require(_dividendIndex < dividends.length, "Invalid dividend index");

        Dividend storage dividend = dividends[_dividendIndex];
        require(!dividend.recycled, "Dividend has already been recycled");
        require(
            block.timestamp >= dividend.payoutDate.add(reclaim_time),
            "Cannot recycle dividend before reclaim time"
        );

        uint256 remainingAmount = dividend.amountRemaining;
        require(remainingAmount > 0, "No remaining dividend amount to recycle");

        dividend.recycled = true;
        balances[dividend.payoutToken] = balances[dividend.payoutToken].sub(
            remainingAmount
        );
        dividend.amountRemaining = 0;

        if (dividend.isERC20Payout) {
            require(
                dividend.payoutToken != address(0),
                "Invalid payout token address"
            );
            IERC20(dividend.payoutToken).transfer(issuer, remainingAmount);
        } else {
            payable(issuer).transfer(remainingAmount);
        }

        emit DividendRecycled(msg.sender, _dividendIndex, remainingAmount);
    }

    function getDividend(
        uint256 _dividendIndex
    )
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            address,
            bool,
            uint256,
            bool
        )
    {
        require(_dividendIndex < dividends.length, "Invalid dividend index");

        Dividend storage dividend = dividends[_dividendIndex];
        return (
            dividend.blockNumber,
            dividend.exDividendDate,
            dividend.recordDate,
            dividend.payoutDate,
            dividend.amount,
            dividend.totalSupplyOfShares,
            dividend.payoutToken,
            dividend.isERC20Payout,
            dividend.amountRemaining,
            dividend.recycled
        );
    }

    function getClaimableAmount(
        address _address,
        uint256 _dividendIndex
    ) external view returns (uint256) {
        require(_dividendIndex < dividends.length, "Invalid dividend index");
        Dividend storage dividend = dividends[_dividendIndex];
        if (block.timestamp < dividend.payoutDate) {
            return 0;
        }
        if (
            dividend.claimed[_address] ||
            dividend.recycled ||
            dividend.amountRemaining == 0 ||
            sharesToken.balanceOf(_address) == 0
        ) {
            return 0;
        }

        uint256 shareBalance = sharesToken.balanceOf(_address);
        uint256 claimAmount = dividend.amount.mul(shareBalance).div(
            dividend.totalSupplyOfShares
        );
        return claimAmount;
    }

    function hasClaimedDividend(
        address _address,
        uint256 _dividendIndex
    ) external view returns (bool) {
        require(_dividendIndex < dividends.length, "Invalid dividend index");
        Dividend storage dividend = dividends[_dividendIndex];
        return dividend.claimed[_address];
    }
}
