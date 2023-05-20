// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "./Ownable.sol";

abstract contract ERC1410Whitelist is Ownable {
    // Mapping to store the whitelist status of addresses
    mapping(address => bool) private _whitelist;

    // Event to notify when an address is added to the whitelist
    event AddressAddedToWhitelist(address indexed account);

    // Event to notify when an address is removed from the whitelist
    event AddressRemovedFromWhitelist(address indexed account);

    /**
     * @dev Modifier to make a function callable only when the caller is whitelisted.
     */
    modifier onlyWhitelisted() {
        require(
            _whitelist[msg.sender],
            "ERC1410WhiteList: caller is not whitelisted"
        );
        _;
    }

    /**
     * @dev Require that the given address is whitelisted.
     * @param account The address to check.
     */
    modifier whitelisted(address account) {
        require(
            _isWhitelisted(account),
            "ERC1410WhiteList: address not whitelisted"
        );
        _;
    }

    constructor() {
        // add owner to whitelist
        _addToWhitelist(msg.sender);
    }

    /**
     * @dev Add an address to the whitelist.
     * @param account The address to be added to the whitelist.
     */
    function _addToWhitelist(address account) internal onlyOwnerOrManager {
        require(account != address(0), "ERC1410WhiteList: invalid address");
        require(
            !_whitelist[account],
            "ERC1410WhiteList: address already whitelisted"
        );
        _whitelist[account] = true;
        emit AddressAddedToWhitelist(account);
    }

    function addToWhitelist(address account) public virtual onlyOwnerOrManager {
        _addToWhitelist(account);
    }

    /**
     * @dev Remove an address from the whitelist.
     * @param account The address to be removed from the whitelist.
     */
    function _removeFromWhitelist(address account) internal {
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
    function _isWhitelisted(address account) internal view returns (bool) {
        return _whitelist[account];
    }
}
