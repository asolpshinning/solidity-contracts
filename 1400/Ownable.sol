/* SPDX-License-Identifier: MIT */

pragma solidity ^0.8.18;

/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 */
abstract contract Ownable {
    address private _contractOwner;
    mapping(address => bool) private _managers;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    event ManagerAdded(address indexed manager);
    event ManagerRemoved(address indexed manager);

    /**
     * @dev The Ownable constructor sets the original `owner` of the contract to the sender
     * account.
     */
    constructor() {
        _contractOwner = msg.sender;
        emit OwnershipTransferred(address(0), _contractOwner);
    }

    /**
     * @return the address of the owner.
     */
    function _owner() internal view returns (address) {
        return _contractOwner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_isOwner(), "Caller is not the owner");
        _;
    }

    /**
     * @dev Modifier for owner or manager
     */
    modifier onlyOwnerOrManager() {
        require(
            _isOwner() || _isManager(msg.sender),
            "Caller is not the owner or manager"
        );
        _;
    }

    /**
     * @return true if `msg.sender` is the owner of the contract.
     */
    function _isOwner() internal view returns (bool) {
        return msg.sender == _contractOwner;
    }

    /**
     * @dev Checks if the address is a manager
     * @param _manager The address to check
     */
    function _isManager(address _manager) internal view returns (bool) {
        return _managers[_manager];
    }

    /**
     * @dev Allows the current owner to add a manager
     * @param _manager The address of the manager
     */
    function _addManager(address _manager) internal {
        require(_manager != address(0), "Cannot add zero address as manager");
        require(!_isManager(_manager), "Address is already a manager");
        _managers[_manager] = true;
        emit ManagerAdded(_manager);
    }

    /**
     * @dev Allows the current owner to remove a manager
     * @param _manager The address of the manager
     */
    function _removeManager(address _manager) internal {
        require(_isManager(_manager), "Address is not a manager");
        _managers[_manager] = false;
        emit ManagerRemoved(_manager);
    }

    /**
     * @dev Allows the current owner to relinquish control of the contract.
     * @notice Renouncing to ownership will leave the contract without an owner.
     * It will not be possible to call the functions with the `onlyOwner`
     * modifier anymore.
     */
    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_contractOwner, address(0));
        _contractOwner = address(0);
    }

    /**
     * @dev Allows the current owner to transfer control of the contract to a newOwner.
     * @param newOwner The address to transfer ownership to.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers control of the contract to a newOwner.
     * @param newOwner The address to transfer ownership to.
     */
    function _transferOwnership(address newOwner) internal {
        require(newOwner != address(0));
        emit OwnershipTransferred(_contractOwner, newOwner);
        _contractOwner = newOwner;
    }
}
