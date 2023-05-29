// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "./ERC1410Basic.sol";
import "./ERC1643.sol";

abstract contract ERC1410Operator is ERC1410Basic, ERC1643 {
    // Mapping from ( partition, operator) to approved status
    mapping(bytes32 => mapping(address => bool)) operatorForThisPartition;

    // Mapping from ( operator) to approved status (can be used against any partition)
    mapping(address => bool) operatorForAllPartitions;

    event AuthorizedOperator(address indexed operator);
    event RevokedOperator(address indexed operator);

    event AuthorizedOperatorByPartition(
        bytes32 indexed partition,
        address indexed operator
    );
    event RevokedOperatorByPartition(
        bytes32 indexed partition,
        address indexed operator
    );

    /// @notice Determines whether `_operator` is an operator for all partitions of `_tokenHolder`
    /// @param _operator The operator to check
    /// @return Whether the `_operator` is an operator for all partitions of `_tokenHolder`
    function isOperator(address _operator) public view returns (bool) {
        return operatorForAllPartitions[_operator];
    }

    /// @notice Determines whether `_operator` is an operator for a specified partition of `_tokenHolder`
    /// @param _partition The partition to check
    /// @param _operator The operator to check
    /// @return Whether the `_operator` is an operator for a specified partition of `_tokenHolder`
    function isOperatorForPartition(
        bytes32 _partition,
        address _operator
    ) public view returns (bool) {
        return operatorForThisPartition[_partition][_operator];
    }

    modifier onlyOperatorForPartition(
        bytes32 _partition,
        address _tokenHolder
    ) {
        require(
            isOperatorForPartition(_partition, msg.sender) ||
                isOperator(msg.sender),
            "Not an operator for this partition"
        );
        _;
    }

    ///////////////////////
    /// Operator Management
    ///////////////////////

    /// @notice Authorises an operator for all partitions of `msg.sender`
    /// @param _operator An address which is being authorised
    function authorizeOperator(address _operator) external onlyOwnerOrManager {
        operatorForAllPartitions[_operator] = true;
        emit AuthorizedOperator(_operator);
    }

    /// @notice Revokes authorisation of an operator previously given for all partitions of `msg.sender`
    /// @param _operator An address which is being de-authorised
    function revokeOperator(address _operator) external onlyOwnerOrManager {
        operatorForAllPartitions[_operator] = false;
        emit RevokedOperator(_operator);
    }

    /// @notice Authorises an operator for a given partition of `tokenHolder`
    /// @param _partition The partition to which the operator is authorised
    /// @param _operator An address which is being authorised
    function authorizeOperatorByPartition(
        bytes32 _partition,
        address _operator
    ) external onlyOwnerOrManager {
        operatorForThisPartition[_partition][_operator] = true;
        emit AuthorizedOperatorByPartition(_partition, _operator);
    }

    /// @notice Revokes authorisation of an operator previously given for a specified partition of `tokenHolder`
    /// @param _partition The partition to which the operator is de-authorised
    /// @param _operator An address which is being de-authorised
    function revokeOperatorByPartition(
        bytes32 _partition,
        address _operator
    ) external onlyOwnerOrManager {
        operatorForThisPartition[_partition][_operator] = false;
        emit RevokedOperatorByPartition(_partition, _operator);
    }
}
