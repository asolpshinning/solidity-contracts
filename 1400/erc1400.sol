/* SPDX-License-Identifier: MIT */

pragma solidity ^0.8.18;

import "./IERC1594.sol";
import "./ERC20Token.sol";
import "./openzeppelin/KindMath.sol";
import "./Ownable.sol";

contract ERC1594 is IERC1594, ERC20Token, Ownable {
    bool internal issuance = true;

    // 1. Add a data structure to maintain the whitelist of addresses
    mapping(address => bool) internal whitelist;

    constructor() public {}

    // 2. Create a function to add or remove addresses from the whitelist
    function setWhitelistStatus(
        address _address,
        bool _status
    ) external onlyOwner {
        whitelist[_address] = _status;
    }

    // 3. Create a function to check if both parties are in the whitelist
    function isWhitelisted(
        address _from,
        address _to
    ) internal view returns (bool) {
        return whitelist[_from] && whitelist[_to];
    }

    function transferWithData(
        address _to,
        uint256 _value,
        bytes calldata _data
    ) external {
        // Add a function to validate the `_data` parameter
        require(
            isWhitelisted(msg.sender, _to),
            "Both parties must be whitelisted"
        );
        _transfer(msg.sender, _to, _value);
    }

    function transferFromWithData(
        address _from,
        address _to,
        uint256 _value,
        bytes calldata _data
    ) external {
        // Add a function to validate the `_data` parameter
        require(isWhitelisted(_from, _to), "Both parties must be whitelisted");
        _transferFrom(msg.sender, _from, _to, _value);
    }

    function isIssuable() external view returns (bool) {
        return issuance;
    }

    function issue(
        address _tokenHolder,
        uint256 _value,
        bytes calldata _data
    ) external onlyOwner {
        // Add a function to validate the `_data` parameter
        require(issuance, "Issuance is closed");
        require(whitelist[_tokenHolder], "Token holder must be whitelisted");
        _mint(_tokenHolder, _value);
        emit Issued(msg.sender, _tokenHolder, _value, _data);
    }

    function redeem(uint256 _value, bytes calldata _data) external {
        // Add a function to validate the `_data` parameter
        require(whitelist[msg.sender], "Token holder must be whitelisted");
        _burn(msg.sender, _value);
        emit Redeemed(address(0), msg.sender, _value, _data);
    }

    function redeemFrom(
        address _tokenHolder,
        uint256 _value,
        bytes calldata _data
    ) external {
        // Add a function to validate the `_data` parameter
        require(whitelist[_tokenHolder], "Token holder must be whitelisted");
        _burnFrom(_tokenHolder, _value);
        emit Redeemed(msg.sender, _tokenHolder, _value, _data);
    }

    function canTransfer(
        address _to,
        uint256 _value,
        bytes calldata _data
    ) external view returns (bool, bytes1, bytes32) {
        // Add a function to validate the `_data` parameter
        if (_balances[msg.sender] < _value) return (false, 0x52, bytes32(0));
        else if (_to == address(0)) return (false, 0x57, bytes32(0));
        else if (!KindMath.checkAdd(_balances[_to], _value))
            return (false, 0x50, bytes32(0));
        else if (!isWhitelisted(msg.sender, _to))
            return (false, 0x54, bytes32(0)); // 0x54: not whitelisted

        return (true, 0x51, bytes32(0));
    }

    function canTransferFrom(
        address _from,
        address _to,
        uint256 _value,
        bytes calldata _data
    ) external view returns (bool, bytes1, bytes32) {
        // Add a function to validate the `_data` parameter
        if (_value > _allowed[_from][msg.sender])
            return (false, 0x53, bytes32(0));
        else if (_balances[_from] < _value) return (false, 0x52, bytes32(0));
        else if (_to == address(0)) return (false, 0x57, bytes32(0));
        else if (!KindMath.checkAdd(_balances[_to], _value))
            return (false, 0x50, bytes32(0));
        else if (!isWhitelisted(_from, _to)) return (false, 0x54, bytes32(0)); // 0x54: not whitelisted

        return (true, 0x51, bytes32(0));
    }
}
