// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

interface IERC1410 {
    // Token Information
    function balanceOf(address _tokenHolder) external view returns (uint256);

    function balanceOfAt(
        bytes32 partition,
        address _owner,
        uint256 _blockNumber
    ) external view returns (uint256);

    function totalSupplyAt(
        bytes32 partition,
        uint256 _blockNumber
    ) external view returns (uint256);

    function balanceOfByPartition(
        bytes32 _partition,
        address _tokenHolder
    ) external view returns (uint256);

    function partitionsOf(
        address _tokenHolder
    ) external view returns (bytes32[] memory);

    function totalSupply() external view returns (uint256);

    // Token Issue
    function operatorIssueByPartition(
        bytes32 _partition,
        address _tokenHolder,
        uint256 _value
    ) external;

    function operatorTransferByPartition(
        bytes32 _partition,
        address _from,
        address _to,
        uint256 _value
    ) external returns (bytes32);

    function canTransferByPartition(
        address _from,
        address _to,
        bytes32 _partition,
        uint256 _value
    ) external view returns (bytes1, bytes32, bytes32);

    // Owner / Manager Information
    function isOwner(address _account) external view returns (bool);

    function isManager(address _manager) external view returns (bool);

    function owner() external view returns (address);

    // Shareholder Information
    function isWhitelisted(address _tokenHolder) external view returns (bool);

    // Operator Information
    function isOperator(address _operator) external view returns (bool);

    function isOperatorForPartition(
        bytes32 _partition,
        address _operator
    ) external view returns (bool);

    // Operator Management
    function authorizeOperator(address _operator) external;

    function revokeOperator(address _operator) external;

    function authorizeOperatorByPartition(
        bytes32 _partition,
        address _operator
    ) external;

    function revokeOperatorByPartition(
        bytes32 _partition,
        address _operator
    ) external;

    // Issuance / Redemption
    function issueByPartition(
        bytes32 _partition,
        address _tokenHolder,
        uint256 _value
    ) external;

    function redeemByPartition(bytes32 _partition, uint256 _value) external;

    function operatorRedeemByPartition(
        bytes32 _partition,
        address _tokenHolder,
        uint256 _value
    ) external;

    // Transfer Events
    event TransferByPartition(
        bytes32 indexed _fromPartition,
        address _operator,
        address indexed _from,
        address indexed _to,
        uint256 _value,
        bytes _data,
        bytes _operatorData
    );

    // Operator Events
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

    // Issuance / Redemption Events
    event IssuedByPartition(
        bytes32 indexed partition,
        address indexed to,
        uint256 value
    );
    event RedeemedByPartition(
        bytes32 indexed partition,
        address indexed operator,
        address indexed from,
        uint256 value
    );
}
