// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "./ERC1410Standard.sol";
import "./ERC1410Whitelist.sol";
import "./openzeppelin/utils/Arrays.sol";
import "./openzeppelin/utils/Counters.sol";

contract ERC1410Snapshot is ERC1410Standard, ERC1410Whitelist {
    using Arrays for uint256[];
    using Counters for Counters.Counter;

    // Snapshotted values have arrays of ids and the value corresponding to that id.
    struct Snapshots {
        uint256[] ids;
        uint256[] values;
    }

    // Mapping from (account, partition) to snapshots
    mapping(address => mapping(bytes32 => Snapshots))
        private _accountBalanceSnapshots;

    Snapshots private _totalSupplySnapshots;

    // Snapshot ids increase monotonically, with the first value being 1. An id of 0 is invalid.
    Counters.Counter private _currentSnapshotId;

    event Snapshot(uint256 id);

    function _snapshot() internal virtual returns (uint256) {
        _currentSnapshotId.increment();

        uint256 currentId = _getCurrentSnapshotId();
        emit Snapshot(currentId);
        return currentId;
    }

    function _getCurrentSnapshotId() internal view virtual returns (uint256) {
        return _currentSnapshotId.current();
    }

    /**
     * @dev Retrieves the balance of `account` at the time `snapshotId` was created.
     */
    function balanceOfAt(
        address account,
        bytes32 partition,
        uint256 snapshotId
    ) public view virtual returns (uint256) {
        (bool snapshotted, uint256 value) = _valueAt(
            snapshotId,
            _accountBalanceSnapshots[account][partition]
        );

        return snapshotted ? value : _balanceOfByPartition(partition, account);
    }

    function totalSupplyAt(
        uint256 snapshotId
    ) public view virtual returns (uint256) {
        (bool snapshotted, uint256 value) = _valueAt(
            snapshotId,
            _totalSupplySnapshots
        );

        return snapshotted ? value : _totalSupply;
    }

    function _valueAt(
        uint256 snapshotId,
        Snapshots storage snapshots
    ) private view returns (bool, uint256) {
        require(snapshotId > 0, "ERC1410Snapshot: id is 0");
        require(
            snapshotId <= _getCurrentSnapshotId(),
            "ERC1410Snapshot: nonexistent id"
        );
        uint256 index = snapshots.ids.findUpperBound(snapshotId);
        if (index == snapshots.ids.length) {
            return (false, 0);
        } else {
            return (true, snapshots.values[index]);
        }
    }

    function _updateAccountSnapshot(
        address account,
        bytes32 partition
    ) private {
        _updateSnapshot(
            _accountBalanceSnapshots[account][partition],
            _balanceOfByPartition(partition, account)
        );
    }

    function _updateTotalSupplySnapshot() private {
        _updateSnapshot(_totalSupplySnapshots, _totalSupply);
    }

    function _updateSnapshot(
        Snapshots storage snapshots,
        uint256 currentValue
    ) private {
        uint256 currentId = _getCurrentSnapshotId();
        if (_lastSnapshotId(snapshots.ids) < currentId) {
            snapshots.ids.push(currentId);
            snapshots.values.push(currentValue);
        }
    }

    function _lastSnapshotId(
        uint256[] storage ids
    ) private view returns (uint256) {
        if (ids.length == 0) {
            return 0;
        } else {
            return ids[ids.length - 1];
        }
    }
}
