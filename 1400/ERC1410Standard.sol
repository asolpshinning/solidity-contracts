// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "./openzeppelin/SafeMath.sol";
import "./ERC1410Operator.sol";

contract ERC1410Standard is ERC1410Operator {
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

    string public contractVersion = "0.1.2"; /// The version of the contract.

    /**
     * @return true if `msg.sender` is the owner of the contract.
     */
    function isOwner(address _account) external view returns (bool) {
        if (owner() == _account) {
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Checks if the address is a manager
     * @param _manager The address to check
     */
    function isManager(address _manager) external view returns (bool) {
        return _isManager(_manager);
    }

    /// @notice Increases totalSupply and the corresponding amount of the specified owners partition
    /// @param _partition The partition to allocate the increase in balance
    /// @param _tokenHolder The token holder whose balance should be increased
    /// @param _value The amount by which to increase the balance
    function _issueByPartition(
        bytes32 _partition,
        address _tokenHolder,
        uint256 _value
    ) internal whitelisted(_tokenHolder) {
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
        _increaseTotalSupplyByPartition(_partition, _value);
        emit IssuedByPartition(_partition, _tokenHolder, _value);
    }

    function issueByPartition(
        bytes32 _partition,
        address _tokenHolder,
        uint256 _value
    ) external onlyOwnerOrManager {
        _issueByPartition(_partition, _tokenHolder, _value);
        // take snapshot of the partition balance of the holder
        _takeSnapshot(
            _partition,
            _balanceOfByPartition(_partition, _tokenHolder),
            _tokenHolder
        );
        // take snapshot of total supply
        _takeSnapshot(
            _partition,
            _totalSupplyByPartition(_partition),
            address(0)
        );
    }

    function operatorIssueByPartition(
        bytes32 _partition,
        address _tokenHolder,
        uint256 _value
    ) external onlyOperatorForPartition(_partition, _tokenHolder) {
        _issueByPartition(_partition, _tokenHolder, _value);
        // take snapshot of the partition balance of the holder
        _takeSnapshot(
            _partition,
            _balanceOfByPartition(_partition, _tokenHolder),
            _tokenHolder
        );
        // take snapshot of total supply
        _takeSnapshot(
            _partition,
            _totalSupplyByPartition(_partition),
            address(0)
        );
    }

    /// @notice Decreases totalSupply and the corresponding amount of the specified partition of msg.sender
    /// @param _partition The partition to allocate the decrease in balance
    /// @param _value The amount by which to decrease the balance
    function redeemByPartition(
        bytes32 _partition,
        uint256 _value
    ) external onlyWhitelisted {
        // Add the function to validate the `_data` parameter
        _redeemByPartition(_partition, msg.sender, address(0), _value);
        // take snapshot of the partition balance of the holder
        _takeSnapshot(
            _partition,
            _balanceOfByPartition(_partition, msg.sender),
            msg.sender
        );
        // take snapshot of total supply
        _takeSnapshot(
            _partition,
            _totalSupplyByPartition(_partition),
            address(0)
        );
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
    ) external whitelisted(_tokenHolder) {
        require(_tokenHolder != address(0), "Invalid from address");
        require(
            isOperator(msg.sender) ||
                isOperatorForPartition(_partition, msg.sender),
            "Not authorized"
        );
        _redeemByPartition(_partition, _tokenHolder, msg.sender, _value);
        // take snapshot of the partition balance of the holder
        _takeSnapshot(
            _partition,
            _balanceOfByPartition(_partition, _tokenHolder),
            _tokenHolder
        );
        // take snapshot of total supply
        _takeSnapshot(
            _partition,
            _totalSupplyByPartition(_partition),
            address(0)
        );
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
        _takeSnapshot(
            _partition,
            _balanceOfByPartition(_partition, _from),
            _from
        );
        _takeSnapshot(
            _partition,
            _totalSupplyByPartition(_partition),
            address(0)
        );
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

        // take snapshot of the partition balance of the holder
        _takeSnapshot(
            _partition,
            _balanceOfByPartition(_partition, _holder),
            _holder
        );
        // take snapshot of total supply
        _takeSnapshot(
            _partition,
            _totalSupplyByPartition(_partition),
            address(0)
        );
    }

    /// @notice Transfers the ownership of tokens from a specified partition from one address to another address
    /// @param _partition The partition from which to transfer tokens
    /// @param _to The address to which to transfer tokens to
    /// @param _value The amount of tokens to transfer from `_partition`
    /// @return The partition to which the transferred tokens were allocated for the _to address
    function operatorTransferByPartition(
        bytes32 _partition,
        address _from,
        address _to,
        uint256 _value
    )
        external
        onlyOperatorForPartition(_partition, _from)
        whitelisted(_from)
        whitelisted(_to)
        returns (bytes32)
    {
        _transferByPartition(_from, _to, _value, _partition);
        // take snapshot of the partition balance of _from
        _takeSnapshot(
            _partition,
            _balanceOfByPartition(_partition, _from),
            _from
        );
        // take snapshot of the partition balance of _to
        _takeSnapshot(_partition, _balanceOfByPartition(_partition, _to), _to);
        // take snapshot of total supply
        _takeSnapshot(
            _partition,
            _totalSupplyByPartition(_partition),
            address(0)
        );
        return _partition;
    }

    function addManager(address _manager) public onlyOwner {
        _addManager(_manager);
        if (!_isWhitelisted(_manager)) {
            _addToWhitelist(_manager);
        }
    }

    function removeManager(address _manager) public onlyOwner {
        _removeManager(_manager);
        if (_isWhitelisted(_manager)) {
            _removeFromWhitelist(_manager);
        }
    }

    /**
     * @dev Removes an address from the whitelist.
     * @param account The address to be removed from the whitelist.
     */
    function removeFromWhitelist(
        address account
    ) public virtual onlyOwnerOrManager {
        // require the balance of the address is zero
        require(_balanceOf(account) == 0, "Balance not zero");
        _removeFromWhitelist(account);
    }

    function isWhitelisted(address _address) external view returns (bool) {
        return _isWhitelisted(_address);
    }

    function totalSupplyByPartition(
        bytes32 _partition
    ) external view returns (uint256) {
        return _totalSupplyByPartition(_partition);
    }

    function _validateParams(bytes32 _partition, uint256 _value) internal pure {
        require(_value != uint256(0), "Zero value not allowed");
        require(_partition != bytes32(0), "Invalid partition");
    }
}
