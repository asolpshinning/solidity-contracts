/* SPDX-License-Identifier: UNLICENSED */

pragma solidity ^0.8.19;

import "./ERC1410Basic.sol";
import "./Ownable.sol";

abstract contract ERC1410Operator is ERC1410Basic, Ownable {
    // Mapping from (investor, partition, operator) to approved status
    mapping(address => mapping(bytes32 => mapping(address => bool))) operatorForThisPartition;

    // Mapping from (investor, operator) to approved status (can be used against any partition)
    mapping(address => mapping(address => bool)) operatorForAllPartitions;

    event AuthorizedOperator(
        address indexed operator,
        address indexed tokenHolder
    );
    event RevokedOperator(
        address indexed operator,
        address indexed tokenHolder
    );

    event AuthorizedOperatorByPartition(
        bytes32 indexed partition,
        address indexed operator,
        address indexed tokenHolder
    );
    event RevokedOperatorByPartition(
        bytes32 indexed partition,
        address indexed operator,
        address indexed tokenHolder
    );

    /// @notice Determines whether `_operator` is an operator for all partitions of `_tokenHolder`
    /// @param _operator The operator to check
    /// @param _tokenHolder The token holder to check
    /// @return Whether the `_operator` is an operator for all partitions of `_tokenHolder`
    function isOperator(
        address _operator,
        address _tokenHolder
    ) public view returns (bool) {
        return operatorForAllPartitions[_tokenHolder][_operator];
    }

    /// @notice Determines whether `_operator` is an operator for a specified partition of `_tokenHolder`
    /// @param _partition The partition to check
    /// @param _operator The operator to check
    /// @param _tokenHolder The token holder to check
    /// @return Whether the `_operator` is an operator for a specified partition of `_tokenHolder`
    function isOperatorForPartition(
        bytes32 _partition,
        address _operator,
        address _tokenHolder
    ) public view returns (bool) {
        return operatorForThisPartition[_tokenHolder][_partition][_operator];
    }

    ///////////////////////
    /// Operator Management
    ///////////////////////

    /// @notice Authorises an operator for all partitions of `msg.sender`
    /// @param _operator An address which is being authorised
    function authorizeOperator(address _operator) external onlyOwner {
        operatorForAllPartitions[msg.sender][_operator] = true;
        emit AuthorizedOperator(_operator, msg.sender);
    }

    /// @notice Revokes authorisation of an operator previously given for all partitions of `msg.sender`
    /// @param _operator An address which is being de-authorised
    function revokeOperator(address _operator) external onlyOwner {
        operatorForAllPartitions[msg.sender][_operator] = false;
        emit RevokedOperator(_operator, msg.sender);
    }

    /// @notice Authorises an operator for a given partition of `msg.sender`
    /// @param _partition The partition to which the operator is authorised
    /// @param _operator An address which is being authorised
    function authorizeOperatorByPartition(
        bytes32 _partition,
        address _operator
    ) external onlyOwner {
        operatorForThisPartition[msg.sender][_partition][_operator] = true;
        emit AuthorizedOperatorByPartition(_partition, _operator, msg.sender);
    }

    /// @notice Revokes authorisation of an operator previously given for a specified partition of `msg.sender`
    /// @param _partition The partition to which the operator is de-authorised
    /// @param _operator An address which is being de-authorised
    function revokeOperatorByPartition(
        bytes32 _partition,
        address _operator
    ) external onlyOwner {
        operatorForThisPartition[msg.sender][_partition][_operator] = false;
        emit RevokedOperatorByPartition(_partition, _operator, msg.sender);
    }

    /// @notice Transfers the ownership of tokens from a specified partition from one address to another address
    /// @param _partition The partition from which to transfer tokens
    /// @param _from The address from which to transfer tokens from
    /// @param _to The address to which to transfer tokens to
    /// @param _value The amount of tokens to transfer from `_partition`
    /// @return The partition to which the transferred tokens were allocated for the _to address
    function operatorTransferByPartition(
        bytes32 _partition,
        address _from,
        address _to,
        uint256 _value
    ) external returns (bytes32) {
        // TODO: Add a functionality of verifying the `_operatorData`
        // TODO: Add a functionality of verifying the `_data`
        require(
            isOperator(msg.sender, _from) ||
                isOperatorForPartition(_partition, msg.sender, _from),
            "Not authorised"
        );
        _transferByPartition(_from, _to, _value, _partition);
        return _partition;
    }
}
