// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "../1400/IERC1410.sol"; // Interface for the ERC1410 token contract
import "../1400/openzeppelin/IERC20.sol"; // Interface for the ERC20 token contract

contract DividendsDistribution {
    IERC1410 public sharesToken; // ERC1410 shares token contract
    address public dividendToken; // Address of the ERC20 token used for dividends (0x0 for ETH)

    struct Distribution {
        uint256 totalDividends;
        uint256 totalSupply;
        mapping(address => uint256) claimedDividends;
    }

    Distribution[] public distributions;

    event DividendsDistributed(
        uint256 indexed distributionIndex,
        uint256 amount
    );
    event DividendsClaimed(
        address indexed account,
        uint256 indexed distributionIndex,
        uint256 amount
    );

    constructor(IERC1410 _sharesToken, address _dividendToken) {
        sharesToken = _sharesToken;
        dividendToken = _dividendToken;
    }

    // Distribute dividends to all token holders
    function distributeDividends() external payable {
        uint256 amount = (dividendToken == address(0))
            ? msg.value
            : IERC20(dividendToken).balanceOf(address(this));
        require(amount > 0, "No dividends to distribute");
        uint256 totalSupply = sharesToken.totalSupply();

        // Create a new distribution entry without initializing the mapping
        distributions.push();
        uint256 distributionIndex = distributions.length - 1;

        // Set the values for the other fields of the struct
        distributions[distributionIndex].totalDividends = amount;
        distributions[distributionIndex].totalSupply = totalSupply;

        emit DividendsDistributed(distributionIndex, amount);
    }

    // Claim dividends for the caller from a specific distribution
    function claimDividends(uint256 distributionIndex) external {
        require(
            distributionIndex < distributions.length,
            "Invalid distribution index"
        );
        Distribution storage distribution = distributions[distributionIndex];
        uint256 claimableAmount = getClaimableDividends(
            msg.sender,
            distributionIndex
        );
        require(claimableAmount > 0, "No dividends to claim");
        distribution.claimedDividends[msg.sender] += claimableAmount;
        if (dividendToken == address(0)) {
            payable(msg.sender).transfer(claimableAmount);
        } else {
            IERC20(dividendToken).transfer(msg.sender, claimableAmount);
        }
        emit DividendsClaimed(msg.sender, distributionIndex, claimableAmount);
    }

    // Get the claimable dividends for an account from a specific distribution
    function getClaimableDividends(
        address account,
        uint256 distributionIndex
    ) public view returns (uint256) {
        require(
            distributionIndex < distributions.length,
            "Invalid distribution index"
        );
        Distribution storage distribution = distributions[distributionIndex];
        uint256 balance = sharesToken.balanceOf(account);
        uint256 totalClaimed = distribution.claimedDividends[account];
        return
            ((distribution.totalDividends * balance) /
                distribution.totalSupply) - totalClaimed;
    }

    // Check if an account has claimed dividends from a specific distribution
    function hasClaimedDividends(
        address account,
        uint256 distributionIndex
    ) public view returns (bool) {
        require(
            distributionIndex < distributions.length,
            "Invalid distribution index"
        );
        Distribution storage distribution = distributions[distributionIndex];
        uint256 totalClaimed = distribution.claimedDividends[account];
        uint256 claimableAmount = ((distribution.totalDividends *
            sharesToken.balanceOf(account)) / distribution.totalSupply);
        return totalClaimed >= claimableAmount;
    }
}
