// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title dFortune Lottery Ticket NFT
 * @notice ERC721 contract representing lottery tickets with advanced features
 * @dev Uses ERC721Enumerable for enumeration and AccessControl for role management
 */
contract TicketNFT is
    ERC721,
    ERC721Enumerable,
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
    uint256 public constant SILVER_TICKET_RARITY = 2;
    uint256 public constant MAX_BATCH_MINT = 50;

    // -----------------------------
    // State Variables
    // -----------------------------
    string private _baseTokenURI;
    bool public metadataLocked;
    address public lotteryManager;
    // Custom token URI mapping to replace ERC721URIStorage
    mapping(uint256 => string) private _tokenURIs;

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
    event SilverTicketAwarded(
        uint256 indexed tokenId,
        address indexed recipient
    );

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
        address manager,
        address initialOwner
    ) Ownable(initialOwner) ERC721(name, symbol) {
        _baseTokenURI = baseURI;
        lotteryManager = manager;

        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(MINTER_ROLE, manager);

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

    function setSilverTicket(uint256 tokenId) external onlyManager {
        if (!_exists(tokenId)) revert InvalidTokenId();

        _ticketTraits[tokenId].rarity = SILVER_TICKET_RARITY;
        emit SilverTicketAwarded(tokenId, ownerOf(tokenId));
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

    /**
     * @notice Sets the token URI for a given token
     * @param tokenId The token ID to set the URI for
     * @param uri The URI to assign
     */
    function setTokenURI(
        uint256 tokenId,
        string memory uri
    ) external onlyOwner {
        if (metadataLocked) revert MetadataPermanentlyLocked();
        if (!_exists(tokenId)) revert InvalidTokenId();
        _tokenURIs[tokenId] = uri;
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

    /// @dev Override required by ERC721Enumerable and ERC721
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override(ERC721, ERC721Enumerable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    /// @dev Base URI for computing tokenURI
    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    /// @dev Check if token exists
    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        try this.ownerOf(tokenId) returns (address) {
            return true;
        } catch {
            return false;
        }
    }

    /// @dev Override required by ERC721Enumerable
    function _increaseBalance(
        address account,
        uint128 value
    ) internal virtual override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    /// @dev Custom burn implementation that cleans up metadata
    function burn(uint256 tokenId) public {
        // Check that the caller is approved or the owner
        _checkAuthorized(ownerOf(tokenId), _msgSender(), tokenId);

        // Call the internal burn function from ERC721
        _burn(tokenId);

        // Clean up our custom metadata
        delete _ticketTraits[tokenId];
        delete _tokenURIs[tokenId];
    }

    /// @dev Override tokenURI to provide custom URI logic
    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        _requireOwned(tokenId);

        string memory _tokenURI = _tokenURIs[tokenId];

        // If there is a specific URI set for this token, return it
        if (bytes(_tokenURI).length > 0) {
            return _tokenURI;
        }

        // Otherwise construct from the base
        return string(abi.encodePacked(_baseURI(), tokenId.toString()));
    }

    /// @dev Support multiple inheritance
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC721, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // -----------------------------
    // Admin Functions
    // -----------------------------

    /// @dev Prevent changing manager after deployment
    function updateLotteryManager(address _newManager) external onlyOwner {
        require(_newManager != address(0), "Invalid address");
        _revokeRole(MINTER_ROLE, lotteryManager);
        lotteryManager = _newManager;
        _grantRole(MINTER_ROLE, _newManager);
    }
}
