/* SPDX-License-Identifier: UNLICENSED */

pragma solidity ^0.8.19;

import "./openzeppelin/SafeMath.sol";
import "./ERC1410Operator.sol";
import "./IERC1410.sol";
import "./Ownable.sol";

abstract contract ERC1410Standard is ERC1410Operator {
    using SafeMath for uint256;

    // Declare the RedeemedByPartition event
    event RedeemedByPartition(
        bytes32 indexed partition,
        address indexed operator,
        address indexed from,
        uint256 value
    );

    // Declare the IssuedByPartition event
    event IssuedByPartition(
        bytes32 indexed partition,
        address indexed to,
        uint256 value
    );

    /// @notice Increases totalSupply and the corresponding amount of the specified owners partition
    /// @param _partition The partition to allocate the increase in balance
    /// @param _tokenHolder The token holder whose balance should be increased
    /// @param _value The amount by which to increase the balance
    function issueByPartition(
        bytes32 _partition,
        address _tokenHolder,
        uint256 _value
    ) external onlyOwner {
        // Add the function to validate the `_data` parameter
        _validateParams(_partition, _value);
        require(_tokenHolder != address(0), "Invalid token receiver");
        uint256 index = partitionToIndex[_tokenHolder][_partition];
        if (index == 0) {
            partitions[_tokenHolder].push(Partition(_value, _partition));
            partitionToIndex[_tokenHolder][_partition] = partitions[
                _tokenHolder
            ].length;
        } else {
            partitions[_tokenHolder][index - 1].amount = partitions[
                _tokenHolder
            ][index - 1].amount.add(_value);
        }
        _totalSupply = _totalSupply.add(_value);
        balances[_tokenHolder] = balances[_tokenHolder].add(_value);
        emit IssuedByPartition(_partition, _tokenHolder, _value);
    }

    /// @notice Decreases totalSupply and the corresponding amount of the specified partition of msg.sender
    /// @param _partition The partition to allocate the decrease in balance
    /// @param _value The amount by which to decrease the balance
    function redeemByPartition(bytes32 _partition, uint256 _value) external {
        // Add the function to validate the `_data` parameter
        _redeemByPartition(_partition, msg.sender, address(0), _value);
    }

    /// @notice Decreases totalSupply and the corresponding amount of the specified partition of tokenHolder
    /// @dev This function can only be called by the authorised operator.
    /// @param _partition The partition to allocate the decrease in balance.
    /// @param _tokenHolder The token holder whose balance should be decreased
    /// @param _value The amount by which to decrease the balance
    function operatorRedeemByPartition(
        bytes32 _partition,
        address _tokenHolder,
        uint256 _value
    ) external {
        // Add the function to validate the `_data` parameter
        // TODO: Add a functionality of verifying the `_operatorData`
        require(_tokenHolder != address(0), "Invalid from address");
        require(
            isOperator(msg.sender, _tokenHolder) ||
                isOperatorForPartition(_partition, msg.sender, _tokenHolder),
            "Not authorised"
        );
        _redeemByPartition(_partition, _tokenHolder, msg.sender, _value);
    }

    function _redeemByPartition(
        bytes32 _partition,
        address _from,
        address _operator,
        uint256 _value
    ) internal {
        // Add the function to validate the `_data` parameter
        _validateParams(_partition, _value);
        require(_validPartition(_partition, _from), "Invalid partition");
        uint256 index = partitionToIndex[_from][_partition] - 1;
        require(
            partitions[_from][index].amount >= _value,
            "Insufficient value"
        );
        if (partitions[_from][index].amount == _value) {
            _deletePartitionForHolder(_from, _partition, index);
        } else {
            partitions[_from][index].amount = partitions[_from][index]
                .amount
                .sub(_value);
        }
        balances[_from] = balances[_from].sub(_value);
        _totalSupply = _totalSupply.sub(_value);
        emit RedeemedByPartition(_partition, _operator, _from, _value);
    }

    function _deletePartitionForHolder(
        address _holder,
        bytes32 _partition,
        uint256 index
    ) internal {
        uint256 lastIndex = partitions[_holder].length - 1;
        if (index != lastIndex) {
            partitions[_holder][index] = partitions[_holder][lastIndex];
            partitionToIndex[_holder][partitions[_holder][index].partition] =
                index +
                1;
        }
        delete partitionToIndex[_holder][_partition];
        partitions[_holder].pop();
    }

    function _validateParams(bytes32 _partition, uint256 _value) internal pure {
        require(_value != uint256(0), "Zero value not allowed");
        require(_partition != bytes32(0), "Invalid partition");
    }
}
