// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "./IERC1643.sol";
import "./ERC1410Whitelist.sol";

/**
 * @title Standard implementation of ERC1643 Document management
 */
abstract contract ERC1643 is IERC1643, ERC1410Whitelist {
    struct Document {
        bytes32 docHash; // Hash of the document
        uint256 lastModified; // Timestamp at which document details was last modified
        string uri; // URI of the document that exist off-chain
    }

    // mapping to store the documents details in the document
    mapping(bytes32 => Document) internal _documents;
    // mapping to store the document name indexes
    mapping(bytes32 => uint256) internal _docIndexes;
    // Array use to store all the document name present in the contracts
    bytes32[] _docNames;

    /**
     * @notice Used to attach a new document to the contract, or update the URI or hash of an existing attached document
     * @dev Can only be executed by the owner or manager of the contract.
     * @param _name Name of the document. It should be unique always
     * @param _uri Off-chain uri of the document from where it is accessible to investors/advisors to read.
     * @param _documentHash hash (of the contents) of the document.
     */
    function setDocument(
        bytes32 _name,
        string calldata _uri,
        bytes32 _documentHash
    ) external onlyOwnerOrManager {
        require(_name != bytes32(0), "Zero value is not allowed");
        require(bytes(_uri).length > 0, "Should not be a empty uri");
        if (_documents[_name].lastModified == uint256(0)) {
            _docNames.push(_name);
            _docIndexes[_name] = _docNames.length;
        }
        _documents[_name] = Document(_documentHash, block.timestamp, _uri);
        emit DocumentUpdated(_name, _uri, _documentHash);
    }

    /**
     * @notice Used to remove an existing document from the contract by giving the name of the document.
     * @dev Can only be executed by the owner or manager of the contract.
     * @param _name Name of the document. It should be unique always
     */
    function removeDocument(bytes32 _name) external onlyOwnerOrManager {
        require(
            _documents[_name].lastModified != uint256(0),
            "Document does not exist"
        );

        // Protect against underflow
        require(_docIndexes[_name] > 0, "Document index is not valid");

        uint256 index = _docIndexes[_name] - 1;

        if (_docNames.length > 0 && index != _docNames.length - 1) {
            // If the document is not the last one in the array, swap it with the last one
            _docNames[index] = _docNames[_docNames.length - 1];
            _docIndexes[_docNames[index]] = index + 1;
        }
        if (_docNames.length > 0) {
            // Reduce the length of the array by one
            _docNames.pop();
        }

        emit DocumentRemoved(
            _name,
            _documents[_name].uri,
            _documents[_name].docHash
        );

        // Delete the document from the mapping
        delete _documents[_name];
    }

    /**
     * @notice Used to return the details of a document with a known name (`bytes32`).
     * @param _name Name of the document
     * @return string The URI associated with the document.
     * @return bytes32 The hash (of the contents) of the document.
     * @return uint256 the timestamp at which the document was last modified.
     */
    function getDocument(
        bytes32 _name
    ) external view returns (string memory, bytes32, uint256) {
        return (
            _documents[_name].uri,
            _documents[_name].docHash,
            _documents[_name].lastModified
        );
    }

    /**
     * @notice Used to retrieve a full list of documents attached to the smart contract.
     * @return bytes32 List of all documents names present in the contract.
     */
    function getAllDocuments() external view returns (bytes32[] memory) {
        return _docNames;
    }
}
