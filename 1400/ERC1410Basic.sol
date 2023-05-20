/* SPDX-License-Identifier: MIT */

pragma solidity ^0.8.18;

import "./openzeppelin/SafeMath.sol";
import "./openzeppelin/KindMath.sol";
import "./ERC1410Snapshot.sol";

abstract contract ERC1410Basic is ERC1410Snapshot {
    using SafeMath for uint256;

    // Represents a fungible set of tokens.
    struct Partition {
        uint256 amount;
        bytes32 partition;
    }

    uint256 _totalSupply;

    // Publicly viewable list of all unique partitions
    bytes32[] public partitionList;

    // Mapping from investor to aggregated balance across all investor token sets
    mapping(address => uint256) balances;

    // Mapping from investor to their partitions
    mapping(address => Partition[]) partitions;

    // Mapping from partition to total supply
    mapping(bytes32 => uint256) partitionTotalSupply;

    // Mapping from (investor, partition) to index of corresponding partition in partitions
    // @dev Stored value is always greater by 1 to avoid the 0 value of every index
    mapping(address => mapping(bytes32 => uint256)) partitionToIndex;

    event TransferByPartition(
        bytes32 indexed _fromPartition,
        address indexed _from,
        address indexed _to,
        uint256 _value
    );

    /**
     * @dev Total number of tokens in existence
     */
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev Total number of tokens in existence of a given partition
     * @param _partition The partition for which to query the total supply
     * @return Total supply of a given partition
     */
    function _totalSupplyByPartition(
        bytes32 _partition
    ) internal view returns (uint256) {
        return partitionTotalSupply[_partition];
    }

    /// @notice Counts the sum of all partitions balances assigned to an owner
    /// @param _tokenHolder An address for whom to query the balance
    /// @return The number of tokens owned by `_tokenHolder`, possibly zero
    function _balanceOf(address _tokenHolder) internal view returns (uint256) {
        return balances[_tokenHolder];
    }

    function balanceOf(address _tokenHolder) external view returns (uint256) {
        return _balanceOf(_tokenHolder);
    }

    /// @notice Counts the balance associated with a specific partition assigned to an tokenHolder
    /// @param _partition The partition for which to query the balance
    /// @param _tokenHolder An address for whom to query the balance
    /// @return The number of tokens owned by `_tokenHolder` with the metadata associated with `_partition`, possibly zero
    function _balanceOfByPartition(
        bytes32 _partition,
        address _tokenHolder
    ) internal view returns (uint256) {
        if (_validPartition(_partition, _tokenHolder))
            return
                partitions[_tokenHolder][
                    partitionToIndex[_tokenHolder][_partition] - 1
                ].amount;
        else return 0;
    }

    function balanceOfByPartition(
        bytes32 _partition,
        address _tokenHolder
    ) external view returns (uint256) {
        return _balanceOfByPartition(_partition, _tokenHolder);
    }

    /// @notice Use to get the list of partitions `_tokenHolder` is associated with
    /// @param _tokenHolder An address corresponds whom partition list is queried
    /// @return List of partitions
    function partitionsOf(
        address _tokenHolder
    ) external view returns (bytes32[] memory) {
        bytes32[] memory partitionsList = new bytes32[](
            partitions[_tokenHolder].length
        );
        for (uint256 i = 0; i < partitions[_tokenHolder].length; i++) {
            partitionsList[i] = partitions[_tokenHolder][i].partition;
        }
        return partitionsList;
    }

    /// @notice The standard provides an on-chain function to determine whether a transfer will succeed,
    /// and return details indicating the reason if the transfer is not valid.
    /// @param _from The address from whom the tokens get transferred.
    /// @param _to The address to which to transfer tokens to.
    /// @param _partition The partition from which to transfer tokens
    /// @param _value The amount of tokens to transfer from `_partition`
    /// @return ESC (Ethereum Status Code) following the EIP-1066 standard
    /// @return Application specific reason codes with additional details
    /// @return The partition to which the transferred tokens were allocated for the _to address
    function canTransferByPartition(
        address _from,
        address _to,
        bytes32 _partition,
        uint256 _value
    ) external view returns (bytes1, bytes32, bytes32) {
        // TODO: Applied the check over the `_data` parameter
        if (!_validPartition(_partition, _from))
            return (0x50, "Partition not exists", bytes32(""));
        else if (
            partitions[_from][partitionToIndex[_from][_partition]].amount <
            _value
        ) return (0x52, "Insufficent balance", bytes32(""));
        else if (_to == address(0))
            return (0x57, "Invalid receiver", bytes32(""));
        else if (
            !KindMath.checkSub(balances[_from], _value) ||
            !KindMath.checkAdd(balances[_to], _value)
        ) return (0x50, "Overflow", bytes32(""));

        // Call function to get the receiver's partition. For current implementation returning the same as sender's
        return (0x51, "Success", _partition);
    }

    function _transferByPartition(
        address _from,
        address _to,
        uint256 _value,
        bytes32 _partition
    ) internal {
        require(_validPartition(_partition, _from), "Invalid partition");
        require(
            partitions[_from][partitionToIndex[_from][_partition] - 1].amount >=
                _value,
            "Insufficient balance"
        );
        require(_to != address(0), "0x address not allowed");
        uint256 _fromIndex = partitionToIndex[_from][_partition] - 1;

        if (!validPartitionForReceiver(_partition, _to)) {
            partitions[_to].push(Partition(0, _partition));
            partitionToIndex[_to][_partition] = partitions[_to].length;

            // Add new partition to the partitionList if it does not already exist
            // @note Partitions list should not get too long otherwise it will be impractical to use
            bool partitionExists = false;
            for (uint256 i = 0; i < partitionList.length; i++) {
                if (partitionList[i] == _partition) {
                    partitionExists = true;
                    break;
                }
            }
            if (!partitionExists) {
                partitionList.push(_partition);
            }
        }
        uint256 _toIndex = partitionToIndex[_to][_partition] - 1;

        // Changing the state values
        partitions[_from][_fromIndex].amount = partitions[_from][_fromIndex]
            .amount
            .sub(_value);
        balances[_from] = balances[_from].sub(_value);
        partitions[_to][_toIndex].amount = partitions[_to][_toIndex].amount.add(
            _value
        );
        balances[_to] = balances[_to].add(_value);

        // take snapshot of the state after transfer
        _takeSnapshot(
            _getHolderSnapshots(_partition, _from),
            _partition,
            _balanceOfByPartition(_partition, _from),
            true
        );
        _takeSnapshot(
            _getHolderSnapshots(_partition, _to),
            _partition,
            _balanceOfByPartition(_partition, _to),
            true
        );
        _takeSnapshot(
            _getTotalSupplySnapshots(_partition),
            _partition,
            _totalSupplyByPartition(_partition),
            false
        );

        // Emit transfer event.
        emit TransferByPartition(_partition, _from, _to, _value);
    }

    function _validPartition(
        bytes32 _partition,
        address _holder
    ) internal view returns (bool) {
        if (
            partitions[_holder].length <
            partitionToIndex[_holder][_partition] ||
            partitionToIndex[_holder][_partition] == 0
        ) return false;
        else return true;
    }

    function validPartitionForReceiver(
        bytes32 _partition,
        address _to
    ) public view returns (bool) {
        for (uint256 i = 0; i < partitions[_to].length; i++) {
            if (partitions[_to][i].partition == _partition) {
                return true;
            }
        }

        return false;
    }
}
