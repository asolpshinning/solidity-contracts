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

    modifier onlyOperatorForPartition(
        bytes32 _partition,
        address _tokenHolder
    ) {
        require(
            operatorForThisPartition[_tokenHolder][_partition][msg.sender] ||
                operatorForAllPartitions[_tokenHolder][msg.sender],
            "Not an operator for this partition"
        );
        _;
    }

    ///////////////////////
    /// Operator Management
    ///////////////////////

    /// @notice Authorises an operator for all partitions of `msg.sender`
    /// @param _operator An address which is being authorised
    function authorizeOperator(
        address _operator,
        address tokenHolder
    ) external onlyOwner {
        operatorForAllPartitions[tokenHolder][_operator] = true;
        emit AuthorizedOperator(_operator, tokenHolder);
    }

    /// @notice Revokes authorisation of an operator previously given for all partitions of `msg.sender`
    /// @param _operator An address which is being de-authorised
    function revokeOperator(
        address _operator,
        address tokenHolder
    ) external onlyOwner {
        operatorForAllPartitions[tokenHolder][_operator] = false;
        emit RevokedOperator(_operator, tokenHolder);
    }

    /// @notice Authorises an operator for a given partition of `tokenHolder`
    /// @param _partition The partition to which the operator is authorised
    /// @param _operator An address which is being authorised
    function authorizeOperatorByPartition(
        bytes32 _partition,
        address _operator,
        address tokenHolder
    ) external onlyOwner {
        operatorForThisPartition[tokenHolder][_partition][_operator] = true;
        emit AuthorizedOperatorByPartition(_partition, _operator, tokenHolder);
    }

    /// @notice Revokes authorisation of an operator previously given for a specified partition of `tokenHolder`
    /// @param _partition The partition to which the operator is de-authorised
    /// @param _operator An address which is being de-authorised
    function revokeOperatorByPartition(
        bytes32 _partition,
        address _operator,
        address tokenHolder
    ) external onlyOwner {
        operatorForThisPartition[tokenHolder][_partition][_operator] = false;
        emit RevokedOperatorByPartition(_partition, _operator, tokenHolder);
    }
}
