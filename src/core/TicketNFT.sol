// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title dFortune Lottery Ticket NFT
 * @notice ERC-721 contract representing lottery tickets with advanced features
 * @dev Combines ERC721Enumerable, ERC721URIStorage, and AccessControl for maximum functionality
 */
contract TicketNFT is
    ERC721Enumerable,
    ERC721URIStorage,
    Ownable2Step,
    ReentrancyGuard,
    AccessControl
{
    using Strings for uint256;

    // -----------------------------
    // Constants & Roles
    // -----------------------------
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 public constant GOLDEN_TICKET_RARITY = 1;
    uint256 public constant MAX_BATCH_MINT = 50;

    // -----------------------------
    // State Variables
    // -----------------------------
    string private _baseTokenURI;
    bool public metadataLocked;
    address public lotteryManager;

    struct TicketTraits {
        uint256 rarity; // 0 = normal, 1 = golden
        uint256 drawId;
        uint256 mintTimestamp;
    }

    mapping(uint256 => TicketTraits) private _ticketTraits;
    mapping(address => uint256) public goldenTicketCount;

    // -----------------------------
    // Events
    // -----------------------------
    event MetadataLocked();
    event GoldenTicketAwarded(
        uint256 indexed tokenId,
        address indexed recipient
    );
    event BatchMinted(address indexed to, uint256[] tokenIds);

    // -----------------------------
    // Errors
    // -----------------------------
    error MetadataPermanentlyLocked();
    error InvalidMinter();
    error ExceedsMaxBatchSize();
    error TransferRestricted();
    error InvalidTokenId();
    error ManagerImmutable();

    // -----------------------------
    // Modifiers
    // -----------------------------
    modifier onlyMinter() {
        if (!hasRole(MINTER_ROLE, msg.sender)) revert InvalidMinter();
        _;
    }

    modifier onlyManager() {
        if (msg.sender != lotteryManager) revert InvalidMinter();
        _;
    }

    // -----------------------------
    // Constructor
    // -----------------------------
    constructor(
        string memory name,
        string memory symbol,
        string memory baseURI,
        address manager
    ) ERC721(name, symbol) {
        _baseTokenURI = baseURI;
        lotteryManager = manager;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MINTER_ROLE, manager);

        _setRoleAdmin(MINTER_ROLE, DEFAULT_ADMIN_ROLE);
    }

    // -----------------------------
    // Core Functions
    // -----------------------------

    /**
     * @notice Batch mint tickets to a single recipient
     * @dev Restricted to MINTER_ROLE (LotteryManager)
     * @param to Recipient address
     * @param quantity Number of tickets to mint
     * @return tokenIds Array of minted token IDs
     */
    function mintBatch(
        address to,
        uint256 quantity,
        uint256 drawId
    ) external onlyMinter nonReentrant returns (uint256[] memory tokenIds) {
        if (quantity > MAX_BATCH_MINT) revert ExceedsMaxBatchSize();

        tokenIds = new uint256[](quantity);
        uint256 currentSupply = totalSupply();

        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = currentSupply + i + 1;
            _safeMint(to, tokenId);
            _ticketTraits[tokenId] = TicketTraits({
                rarity: 0, // Default normal
                drawId: drawId,
                mintTimestamp: block.timestamp
            });
            tokenIds[i] = tokenId;
        }

        emit BatchMinted(to, tokenIds);
        return tokenIds;
    }

    /**
     * @notice Award golden ticket status to a token
     * @dev Restricted to LotteryManager contract
     * @param tokenId NFT token ID to upgrade
     */
    function setGoldenTicket(uint256 tokenId) external onlyManager {
        if (!_exists(tokenId)) revert InvalidTokenId();

        _ticketTraits[tokenId].rarity = GOLDEN_TICKET_RARITY;
        goldenTicketCount[ownerOf(tokenId)]++;

        emit GoldenTicketAwarded(tokenId, ownerOf(tokenId));
    }

    // -----------------------------
    // Metadata Management
    // -----------------------------

    /**
     * @notice Lock metadata permanently
     * @dev Irreversible action, only owner
     */
    function lockMetadata() external onlyOwner {
        metadataLocked = true;
        emit MetadataLocked();
    }

    /**
     * @notice Set base URI for all tokens
     * @dev Only callable before metadata is locked
     */
    function setBaseURI(string memory newBaseURI) external onlyOwner {
        if (metadataLocked) revert MetadataPermanentlyLocked();
        _baseTokenURI = newBaseURI;
    }

    // -----------------------------
    // View Functions
    // -----------------------------

    /**
     * @notice Get ticket traits for a specific token
     * @param tokenId NFT token ID
     * @return traits Structured ticket metadata
     */
    function getTicketTraits(
        uint256 tokenId
    ) external view returns (TicketTraits memory traits) {
        if (!_exists(tokenId)) revert InvalidTokenId();
        return _ticketTraits[tokenId];
    }

    /**
     * @notice Check if a ticket is golden
     * @param tokenId NFT token ID
     * @return True if golden ticket
     */
    function isGoldenTicket(uint256 tokenId) external view returns (bool) {
        return _ticketTraits[tokenId].rarity == GOLDEN_TICKET_RARITY;
    }

    // -----------------------------
    // Security & Overrides
    // -----------------------------

    /// @dev Prevent token transfers during active draws
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    /// @dev Merge ERC721 and ERC721URIStorage
    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return string(abi.encodePacked(_baseTokenURI, tokenId.toString()));
    }

    /// @dev Support multiple inheritance
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(ERC721, ERC721Enumerable, ERC721URIStorage, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // -----------------------------
    // Admin Functions
    // -----------------------------

    /// @dev Prevent changing manager after deployment
    function updateLotteryManager(address) external pure {
        revert ManagerImmutable();
    }
}
