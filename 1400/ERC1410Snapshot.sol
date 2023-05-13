// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./openzeppelin/SafeMath.sol";

abstract contract ERC1410Snapshot {
    using SafeMath for uint256;

    /**
     * @dev `Snapshot` is the structure that attaches a block number to a
     * given value. The block number attached is the one that last changed the value.
     */
    struct Snapshot {
        uint256 blockNum; // `blockNum` is the block number at which the value was generated from
        uint256 value; // `value` is the amount of tokens at a specific block number
    }

    // `_snapshotBalances` maps from partition to owner to snapshot array.
    mapping(bytes32 => mapping(address => Snapshot[]))
        private _snapshotBalances;

    // Tracks the history of the `totalSupply` of each partition of the token
    mapping(bytes32 => Snapshot[]) private _snapshotTotalSupply;

    /**
     * @dev Queries the balance of `_owner` at a specific `_blockNumber` for a given partition.
     * @param partition The partition from which the balance will be retrieved
     * @param _owner The address from which the balance will be retrieved
     * @param _blockNumber The block number when the balance is queried
     * @return The balance at `_blockNumber`
     */
    function balanceOfAt(
        bytes32 partition,
        address _owner,
        uint256 _blockNumber
    ) public view returns (uint256) {
        return _getValueAt(_snapshotBalances[partition][_owner], _blockNumber);
    }

    /**
     * @dev Total amount of tokens from a specific partition at a specific `_blockNumber`.
     * @param partition The partition from which to retrieve the total supply
     * @param _blockNumber The block number when the totalSupply is queried
     * @return The total amount of tokens from `partition` at `_blockNumber`
     */
    function totalSupplyAt(
        bytes32 partition,
        uint256 _blockNumber
    ) public view returns (uint256) {
        return _getValueAt(_snapshotTotalSupply[partition], _blockNumber);
    }

    /**
     * @dev `updateValueAtNow` used to update the `_snapshotBalances` map and the `_snapshotTotalSupply`
     * @param partition The partition from which to update the total supply
     * @param pastSnapshots The history of snapshots being updated
     * @param _value The new number of tokens
     */
    function _updateValueAtNow(
        Snapshot[] storage pastSnapshots,
        bytes32 partition,
        uint256 _value
    ) internal {
        if (
            (pastSnapshots.length == 0) ||
            (pastSnapshots[pastSnapshots.length.sub(1)].blockNum < block.number)
        ) {
            pastSnapshots.push(Snapshot(block.number, _value));
        } else {
            pastSnapshots[pastSnapshots.length.sub(1)].value = _value;
        }
        _snapshotTotalSupply[partition] = pastSnapshots;
    }

    /**
     * @dev `getValueAt` retrieves the number of tokens at a given block number
     * @param pastShots The history of snapshot values being queried
     * @param _blockNum The block number to retrieve the value at
     * @return The number of tokens being queried
     */
    function _getValueAt(
        Snapshot[] storage pastShots,
        uint256 _blockNum
    ) internal view returns (uint256) {
        if (pastShots.length == 0) return 0;

        // Shortcut for the actual value
        if (_blockNum >= pastShots[pastShots.length.sub(1)].blockNum) {
            return pastShots[pastShots.length.sub(1)].value;
        }

        if (_blockNum < pastShots[0].blockNum) {
            return 0;
        }

        // Binary search of the value in the array
        uint256 min;
        uint256 max = pastShots.length.sub(1);

        while (max > min) {
            uint256 mid = (max.add(min).add(1)).div(2);
            if (pastShots[mid].blockNum <= _blockNum) {
                min = mid;
            } else {
                max = mid.sub(1);
            }
        }

        return pastShots[min].value;
    }
}
