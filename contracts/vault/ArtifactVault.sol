// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title ArtifactVault
 * @author Artifact Virtual
 * @notice On-chain enterprise snapshot manifest — each snapshot is an NFT
 *
 * Every daily snapshot of the Artifact Virtual enterprise workspace
 * gets encrypted, pinned to IPFS via our own Kubo node, and registered
 * here as a soulbound NFT. The tokenURI points to an IPFS metadata JSON
 * containing the archive CID, SHA-256 hash, file count, and timestamp.
 *
 * Non-transferable by design — these are attestations, not assets.
 * Only the deployer (Singularity pipeline) can mint.
 * Anyone can read the on-chain history.
 *
 *   "If it computes, it will work."
 */
contract ArtifactVault is ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIds;

    /// @notice Snapshot metadata stored on-chain (compact, critical fields only)
    struct Snapshot {
        string  archiveCid;     // IPFS CID of the encrypted archive
        string  metadataCid;    // IPFS CID of the JSON metadata
        bytes32 archiveHash;    // SHA-256 of the encrypted archive
        uint64  timestamp;      // Unix timestamp of snapshot creation
        uint64  fileCount;      // Number of files in snapshot
        uint64  sizeBytes;      // Compressed archive size in bytes
        bool    valid;          // Can be invalidated if corruption detected post-mint
    }

    /// @notice tokenId → Snapshot
    mapping(uint256 => Snapshot) public snapshots;

    /// @notice Latest snapshot tokenId for quick lookup
    uint256 public latestSnapshotId;

    /// @notice Total snapshots ever minted (including invalidated)
    uint256 public totalSnapshots;

    // ─── Events ──────────────────────────────────────────────

    event SnapshotMinted(
        uint256 indexed tokenId,
        string  archiveCid,
        bytes32 archiveHash,
        uint64  timestamp,
        uint64  fileCount,
        uint64  sizeBytes
    );

    event SnapshotInvalidated(uint256 indexed tokenId, string reason);

    // ─── Errors ──────────────────────────────────────────────

    error TransferDisabled();
    error SnapshotNotFound(uint256 tokenId);
    error AlreadyInvalidated(uint256 tokenId);

    // ─── Constructor ─────────────────────────────────────────

    constructor() ERC721("Artifact Vault", "VAULT") {
        // Deployer is owner — Singularity pipeline wallet
    }

    // ─── Core ────────────────────────────────────────────────

    /**
     * @notice Mint a new snapshot NFT
     * @param archiveCid    IPFS CID of the encrypted archive
     * @param metadataCid   IPFS CID of the metadata JSON (becomes tokenURI)
     * @param archiveHash   SHA-256 digest of the encrypted archive
     * @param fileCount     Number of files archived
     * @param sizeBytes     Compressed archive size
     * @return tokenId      The minted token ID
     */
    function mintSnapshot(
        string calldata archiveCid,
        string calldata metadataCid,
        bytes32 archiveHash,
        uint64  fileCount,
        uint64  sizeBytes
    ) external onlyOwner returns (uint256) {
        _tokenIds.increment();
        uint256 tokenId = _tokenIds.current();

        _safeMint(owner(), tokenId);
        _setTokenURI(tokenId, string.concat("ipfs://", metadataCid));

        snapshots[tokenId] = Snapshot({
            archiveCid:  archiveCid,
            metadataCid: metadataCid,
            archiveHash: archiveHash,
            timestamp:   uint64(block.timestamp),
            fileCount:   fileCount,
            sizeBytes:   sizeBytes,
            valid:       true
        });

        latestSnapshotId = tokenId;
        totalSnapshots++;

        emit SnapshotMinted(
            tokenId,
            archiveCid,
            archiveHash,
            uint64(block.timestamp),
            fileCount,
            sizeBytes
        );

        return tokenId;
    }

    /**
     * @notice Invalidate a snapshot (corruption detected post-mint)
     * @param tokenId  Token to invalidate
     * @param reason   Human-readable reason
     */
    function invalidateSnapshot(uint256 tokenId, string calldata reason)
        external
        onlyOwner
    {
        if (!_exists(tokenId)) revert SnapshotNotFound(tokenId);
        if (!snapshots[tokenId].valid) revert AlreadyInvalidated(tokenId);

        snapshots[tokenId].valid = false;
        emit SnapshotInvalidated(tokenId, reason);
    }

    // ─── Views ───────────────────────────────────────────────

    /**
     * @notice Get the latest valid snapshot
     * @return snapshot  The most recent valid Snapshot struct
     */
    function latestSnapshot() external view returns (Snapshot memory) {
        return snapshots[latestSnapshotId];
    }

    /**
     * @notice Get snapshot history (paginated)
     * @param offset  Start tokenId (1-based)
     * @param limit   Max results
     * @return result  Array of Snapshot structs
     */
    function getSnapshots(uint256 offset, uint256 limit)
        external
        view
        returns (Snapshot[] memory)
    {
        uint256 total = _tokenIds.current();
        if (offset > total || offset == 0) return new Snapshot[](0);

        uint256 end = offset + limit;
        if (end > total + 1) end = total + 1;
        uint256 count = end - offset;

        Snapshot[] memory result = new Snapshot[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = snapshots[offset + i];
        }
        return result;
    }

    // ─── Soulbound (non-transferable) ────────────────────────

    /**
     * @dev Override to prevent all transfers. Snapshots are attestations.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal virtual override {
        // Allow minting (from == address(0)) and burning (to == address(0))
        if (from != address(0) && to != address(0)) {
            revert TransferDisabled();
        }
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    // ─── Metadata ────────────────────────────────────────────

    function contractURI() external pure returns (string memory) {
        return "ipfs://artifact-vault-collection-metadata";
    }
}
