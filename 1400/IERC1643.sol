// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

// @title IERC1643 Document Management (part of the ERC1400 Security Token Standards)
/// @dev See https://github.com/SecurityTokenStandard/EIP-Spec

interface IERC1643 {
    // Document Management
    // Returns document's URI, document's hash, and timestamp of the document
    function getDocument(
        bytes32 _name
    ) external view returns (string memory, bytes32, uint256);

    // Sets a new document or updates an existing one
    function setDocument(
        bytes32 _name,
        string calldata _uri,
        bytes32 _documentHash
    ) external;

    // Removes a document
    function removeDocument(bytes32 _name) external;

    // Returns all document names
    function getAllDocuments() external view returns (bytes32[] memory);

    // Document Events
    event DocumentRemoved(
        bytes32 indexed _name,
        string _uri,
        bytes32 _documentHash
    );
    event DocumentUpdated(
        bytes32 indexed _name,
        string _uri,
        bytes32 _documentHash
    );
}
