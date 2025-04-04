// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title ITicketNFT
 * @notice Interface for the Lottery Ticket NFT contract
 * @dev Defines the NFT minting and management API
 */
interface ITicketNFT {
    // -----------------------------
    // Structures
    // -----------------------------

    /// @notice Ticket metadata structure
    /// @param rarity 0 = normal, 1 = golden
    /// @param drawId Draw ID the ticket belongs to
    /// @param mintTimestamp Block timestamp of minting
    struct TicketTraits {
        uint256 rarity;
        uint256 drawId;
        uint256 mintTimestamp;
    }

    // -----------------------------
    // Events
    // -----------------------------

    /// @notice Emitted when golden ticket status is awarded
    /// @param tokenId NFT token ID
    /// @param recipient Current owner address
    event GoldenTicketAwarded(
        uint256 indexed tokenId,
        address indexed recipient
    );

    // -----------------------------
    // Errors
    // -----------------------------

    /// @dev Reverts when minting exceeds batch limit
    error ExceedsMaxBatchSize();

    /// @dev Reverts when unauthorized account tries to mint
    error InvalidMinter();

    // -----------------------------
    // Core Functions
    // -----------------------------

    /**
     * @notice Batch mint tickets to a single recipient
     * @param to Recipient address
     * @param quantity Number of tickets to mint
     * @param drawId Associated draw ID
     * @return tokenIds Array of minted token IDs
     * @dev Restricted to MINTER_ROLE holders
     */
    function mintBatch(
        address to,
        uint256 quantity,
        uint256 drawId
    ) external returns (uint256[] memory tokenIds);

    /**
     * @notice Upgrade a ticket to golden status
     * @param tokenId NFT token ID to upgrade
     * @dev Restricted to lottery manager contract
     */
    function setGoldenTicket(uint256 tokenId) external;

    // -----------------------------
    // View Functions
    // -----------------------------

    /**
     * @notice Get ticket metadata
     * @param tokenId NFT token ID
     * @return traits Structured ticket metadata
     */
    function getTicketTraits(
        uint256 tokenId
    ) external view returns (TicketTraits memory traits);

    /**
     * @notice Check golden ticket status
     * @param tokenId NFT token ID
     * @return True if ticket has golden status
     */
    function isGoldenTicket(uint256 tokenId) external view returns (bool);
}
