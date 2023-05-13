/* SPDX-License-Identifier: UNLICENSED */

pragma solidity ^0.8.18;

/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 */
abstract contract Ownable {
    address private _owner;
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
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), _owner);
    }

    /**
     * @return the address of the owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(isOwner(), "Caller is not the owner");
        _;
    }

    /**
     * @dev Modifier for owner or manager
     */
    modifier onlyOwnerOrManager() {
        require(
            isOwner() || isManager(msg.sender),
            "Caller is not the owner or manager"
        );
        _;
    }

    /**
     * @return true if `msg.sender` is the owner of the contract.
     */
    function isOwner() public view returns (bool) {
        return msg.sender == _owner;
    }

    /**
     * @dev Checks if the address is a manager
     * @param _manager The address to check
     */
    function isManager(address _manager) public view returns (bool) {
        return _managers[_manager];
    }

    /**
     * @dev Allows the current owner to add a manager
     * @param _manager The address of the manager
     */
    function _addManager(address _manager) internal {
        require(_manager != address(0), "Cannot add zero address as manager");
        require(!isManager(_manager), "Address is already a manager");
        _managers[_manager] = true;
        emit ManagerAdded(_manager);
    }

    /**
     * @dev Allows the current owner to remove a manager
     * @param _manager The address of the manager
     */
    function _removeManager(address _manager) internal {
        require(isManager(_manager), "Address is not a manager");
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
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
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
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}
