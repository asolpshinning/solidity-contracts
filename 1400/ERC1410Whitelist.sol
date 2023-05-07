// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "./Ownable.sol";

abstract contract ERC1410Whitelist is Ownable {
    // Mapping to store the whitelist status of addresses
    mapping(address => bool) private _whitelist;

    // Event to notify when an address is added to the whitelist
    event AddressAddedToWhitelist(address indexed account);

    // Event to notify when an address is removed from the whitelist
    event AddressRemovedFromWhitelist(address indexed account);

    /**
     * @dev Add an address to the whitelist.
     * @param account The address to be added to the whitelist.
     */
    function addToWhitelist(address account) public virtual onlyOwner {
        require(account != address(0), "ERC1410WhiteList: invalid address");
        require(
            !_whitelist[account],
            "ERC1410WhiteList: address already whitelisted"
        );
        _whitelist[account] = true;
        emit AddressAddedToWhitelist(account);
    }

    /**
     * @dev Remove an address from the whitelist.
     * @param account The address to be removed from the whitelist.
     */
    function removeFromWhitelist(address account) public virtual onlyOwner {
        require(account != address(0), "ERC1410WhiteList: invalid address");
        require(
            _whitelist[account],
            "ERC1410WhiteList: address not whitelisted"
        );
        _whitelist[account] = false;
        emit AddressRemovedFromWhitelist(account);
    }

    /**
     * @dev Check if an address is whitelisted.
     * @param account The address to check.
     * @return True if the address is whitelisted, false otherwise.
     */
    function isWhitelisted(address account) public view virtual returns (bool) {
        return _whitelist[account];
    }

    /**
     * @dev Require that the given address is whitelisted.
     * @param account The address to check.
     */
    modifier onlyWhitelisted(address account) {
        require(
            isWhitelisted(account),
            "ERC1410WhiteList: address not whitelisted"
        );
        _;
    }
}
