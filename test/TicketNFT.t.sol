// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {TicketNFT} from "../src/core/TicketNFT.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol"; // Add this import

contract TicketNFTTest is Test {
    using Strings for uint256; // Add this line to use the Strings library

    TicketNFT public ticketNFT;

    address public owner = address(0x1);
    address public manager = address(0x2);
    address public minter = address(0x3);
    address public user1 = address(0x4);
    address public user2 = address(0x5);

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    uint256 public constant DRAW_ID = 123;
    string public constant NAME = "dFortune Lottery Ticket";
    string public constant SYMBOL = "DFLT";
    string public constant BASE_URI = "https://api.dfortune.lottery/tickets/";

    event BatchMinted(address indexed to, uint256[] tokenIds);
    event GoldenTicketAwarded(
        uint256 indexed tokenId,
        address indexed recipient
    );
    event MetadataLocked();

    function setUp() public {
        vm.startPrank(owner);
        ticketNFT = new TicketNFT(NAME, SYMBOL, BASE_URI, manager, owner);
        vm.stopPrank();

        // Grant minter role to the minter address
        vm.prank(owner);
        ticketNFT.grantRole(MINTER_ROLE, minter);
    }

    // -----------------------------
    // Constructor Tests
    // -----------------------------

    function test_Constructor() public {
        assertEq(ticketNFT.name(), NAME);
        assertEq(ticketNFT.symbol(), SYMBOL);
        assertEq(ticketNFT.lotteryManager(), manager);
        assertEq(ticketNFT.owner(), owner);
        assertTrue(ticketNFT.hasRole(DEFAULT_ADMIN_ROLE, owner));
        assertTrue(ticketNFT.hasRole(MINTER_ROLE, manager));

        // Test for baseURI by checking token URI format
        vm.startPrank(minter);
        uint256[] memory tokenIds = ticketNFT.mintBatch(user1, 1, DRAW_ID);
        vm.stopPrank();

        assertEq(
            ticketNFT.tokenURI(tokenIds[0]),
            string(abi.encodePacked(BASE_URI, tokenIds[0].toString()))
        );
    }

    // -----------------------------
    // Role Tests
    // -----------------------------

    function test_RoleAdmin() public {
        // Verify DEFAULT_ADMIN_ROLE is admin of MINTER_ROLE
        assertEq(ticketNFT.getRoleAdmin(MINTER_ROLE), DEFAULT_ADMIN_ROLE);

        // Test admin can grant roles
        vm.prank(owner);
        ticketNFT.grantRole(MINTER_ROLE, user1);
        assertTrue(ticketNFT.hasRole(MINTER_ROLE, user1));

        // Test admin can revoke roles
        vm.prank(owner);
        ticketNFT.revokeRole(MINTER_ROLE, user1);
        assertFalse(ticketNFT.hasRole(MINTER_ROLE, user1));
    }

    // -----------------------------
    // Minting Tests
    // -----------------------------

    function test_MintBatch() public {
        uint256 quantity = 5;

        vm.startPrank(minter);
        vm.expectEmit(true, false, false, true);
        emit BatchMinted(user1, getTokenIdsArray(1, quantity));
        uint256[] memory tokenIds = ticketNFT.mintBatch(
            user1,
            quantity,
            DRAW_ID
        );
        vm.stopPrank();

        assertEq(tokenIds.length, quantity);
        assertEq(ticketNFT.totalSupply(), quantity);

        for (uint256 i = 0; i < quantity; i++) {
            assertEq(ticketNFT.ownerOf(tokenIds[i]), user1);

            TicketNFT.TicketTraits memory traits = ticketNFT.getTicketTraits(
                tokenIds[i]
            );
            assertEq(traits.rarity, 0); // Normal rarity
            assertEq(traits.drawId, DRAW_ID);
            assertEq(traits.mintTimestamp, block.timestamp);

            assertFalse(ticketNFT.isGoldenTicket(tokenIds[i]));
        }
    }

    function test_MintBatchReverts_WhenNotMinter() public {
        vm.prank(user1);
        vm.expectRevert(TicketNFT.InvalidMinter.selector);
        ticketNFT.mintBatch(user1, 1, DRAW_ID);
    }

    function test_MintBatchReverts_WhenExceedsMaxBatchSize() public {
        uint256 maxSize = ticketNFT.MAX_BATCH_MINT();

        vm.prank(minter);
        vm.expectRevert(TicketNFT.ExceedsMaxBatchSize.selector);
        ticketNFT.mintBatch(user1, maxSize + 1, DRAW_ID);
    }

    // -----------------------------
    // Golden Ticket Tests
    // -----------------------------

    function test_SetGoldenTicket() public {
        // First mint a ticket
        vm.prank(minter);
        uint256[] memory tokenIds = ticketNFT.mintBatch(user1, 1, DRAW_ID);
        uint256 tokenId = tokenIds[0];

        // Make it golden
        vm.prank(manager);
        vm.expectEmit(true, true, false, true);
        emit GoldenTicketAwarded(tokenId, user1);
        ticketNFT.setGoldenTicket(tokenId);

        // Verify it's now golden
        assertTrue(ticketNFT.isGoldenTicket(tokenId));
        assertEq(ticketNFT.goldenTicketCount(user1), 1);

        TicketNFT.TicketTraits memory traits = ticketNFT.getTicketTraits(
            tokenId
        );
        assertEq(traits.rarity, ticketNFT.GOLDEN_TICKET_RARITY());
    }

    function test_SetGoldenTicketReverts_WhenNotManager() public {
        // First mint a ticket
        vm.prank(minter);
        uint256[] memory tokenIds = ticketNFT.mintBatch(user1, 1, DRAW_ID);
        uint256 tokenId = tokenIds[0];

        // Try to make it golden as non-manager
        vm.prank(user1);
        vm.expectRevert(TicketNFT.InvalidMinter.selector);
        ticketNFT.setGoldenTicket(tokenId);
    }

    function test_SetGoldenTicketReverts_WhenInvalidTokenId() public {
        uint256 nonExistentTokenId = 9999;

        vm.prank(manager);
        vm.expectRevert(TicketNFT.InvalidTokenId.selector);
        ticketNFT.setGoldenTicket(nonExistentTokenId);
    }

    function test_GoldenTicketCountTracking_AfterTransfer() public {
        // First mint a ticket
        vm.prank(minter);
        uint256[] memory tokenIds = ticketNFT.mintBatch(user1, 1, DRAW_ID);
        uint256 tokenId = tokenIds[0];

        // Make it golden
        vm.prank(manager);
        ticketNFT.setGoldenTicket(tokenId);
        assertEq(ticketNFT.goldenTicketCount(user1), 1);

        // Transfer to another user
        vm.prank(user1);
        ticketNFT.transferFrom(user1, user2, tokenId);

        // Golden count should still be 1 for user1 (count is not automatically updated on transfer)
        assertEq(ticketNFT.goldenTicketCount(user1), 1);
        assertEq(ticketNFT.goldenTicketCount(user2), 0);
    }

    // -----------------------------
    // Metadata Tests
    // -----------------------------

    function test_SetBaseURI() public {
        string memory newBaseURI = "https://new.api.dfortune.lottery/tickets/";

        vm.prank(owner);
        ticketNFT.setBaseURI(newBaseURI);

        // Mint a token to test the new URI
        vm.prank(minter);
        uint256[] memory tokenIds = ticketNFT.mintBatch(user1, 1, DRAW_ID);
        uint256 tokenId = tokenIds[0];

        assertEq(
            ticketNFT.tokenURI(tokenId),
            string(abi.encodePacked(newBaseURI, tokenId.toString()))
        );
    }

    function test_SetBaseURIReverts_WhenNotOwner() public {
        string memory newBaseURI = "https://new.api.dfortune.lottery/tickets/";

        vm.prank(user1);
        // Updated to match the new Ownable error format
        vm.expectRevert(
            abi.encodeWithSignature(
                "OwnableUnauthorizedAccount(address)",
                user1
            )
        );
        ticketNFT.setBaseURI(newBaseURI);
    }

    function test_SetBaseURIReverts_WhenMetadataLocked() public {
        string memory newBaseURI = "https://new.api.dfortune.lottery/tickets/";

        // Lock metadata
        vm.prank(owner);
        ticketNFT.lockMetadata();

        // Try to change base URI
        vm.prank(owner);
        vm.expectRevert(TicketNFT.MetadataPermanentlyLocked.selector);
        ticketNFT.setBaseURI(newBaseURI);
    }

    function test_SetTokenURI() public {
        // Mint a token
        vm.prank(minter);
        uint256[] memory tokenIds = ticketNFT.mintBatch(user1, 1, DRAW_ID);
        uint256 tokenId = tokenIds[0];

        string memory customURI = "ipfs://QmCustomMetadataHash";

        // Set custom token URI
        vm.prank(owner);
        ticketNFT.setTokenURI(tokenId, customURI);

        // Verify custom URI
        assertEq(ticketNFT.tokenURI(tokenId), customURI);
    }

    function test_SetTokenURIReverts_WhenMetadataLocked() public {
        // Mint a token
        vm.prank(minter);
        uint256[] memory tokenIds = ticketNFT.mintBatch(user1, 1, DRAW_ID);
        uint256 tokenId = tokenIds[0];

        string memory customURI = "ipfs://QmCustomMetadataHash";

        // Lock metadata
        vm.prank(owner);
        ticketNFT.lockMetadata();

        // Try to set custom token URI
        vm.prank(owner);
        vm.expectRevert(TicketNFT.MetadataPermanentlyLocked.selector);
        ticketNFT.setTokenURI(tokenId, customURI);
    }

    function test_SetTokenURIReverts_WhenInvalidTokenId() public {
        uint256 nonExistentTokenId = 9999;
        string memory customURI = "ipfs://QmCustomMetadataHash";

        vm.prank(owner);
        vm.expectRevert(TicketNFT.InvalidTokenId.selector);
        ticketNFT.setTokenURI(nonExistentTokenId, customURI);
    }

    function test_LockMetadata() public {
        assertFalse(ticketNFT.metadataLocked());

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit MetadataLocked();
        ticketNFT.lockMetadata();

        assertTrue(ticketNFT.metadataLocked());
    }

    function test_LockMetadataReverts_WhenNotOwner() public {
        vm.prank(user1);
        // Updated to match the new Ownable error format
        vm.expectRevert(
            abi.encodeWithSignature(
                "OwnableUnauthorizedAccount(address)",
                user1
            )
        );
        ticketNFT.lockMetadata();
    }

    // -----------------------------
    // Burning Tests
    // -----------------------------

    function test_Burn() public {
        // First mint a token
        vm.prank(minter);
        uint256[] memory tokenIds = ticketNFT.mintBatch(user1, 1, DRAW_ID);
        uint256 tokenId = tokenIds[0];

        // Make it golden
        vm.prank(manager);
        ticketNFT.setGoldenTicket(tokenId);

        // Burn it
        vm.prank(user1);
        ticketNFT.burn(tokenId);

        // Verify it's burned
        vm.expectRevert();
        ticketNFT.ownerOf(tokenId);

        vm.expectRevert(TicketNFT.InvalidTokenId.selector);
        ticketNFT.getTicketTraits(tokenId);
    }

    function test_BurnReverts_WhenNotOwnerOrApproved() public {
        // First mint a token
        vm.prank(minter);
        uint256[] memory tokenIds = ticketNFT.mintBatch(user1, 1, DRAW_ID);
        uint256 tokenId = tokenIds[0];

        // Try to burn it as non-owner
        vm.prank(user2);
        vm.expectRevert();
        ticketNFT.burn(tokenId);
    }

    // -----------------------------
    // Interface Tests
    // -----------------------------

    function test_SupportsInterface() public {
        // ERC721 interface
        bytes4 erc721InterfaceId = 0x80ac58cd;
        assertTrue(ticketNFT.supportsInterface(erc721InterfaceId));

        // ERC721Metadata interface
        bytes4 erc721MetadataInterfaceId = 0x5b5e139f;
        assertTrue(ticketNFT.supportsInterface(erc721MetadataInterfaceId));

        // ERC721Enumerable interface
        bytes4 erc721EnumerableInterfaceId = 0x780e9d63;
        assertTrue(ticketNFT.supportsInterface(erc721EnumerableInterfaceId));

        // AccessControl interface
        bytes4 accessControlInterfaceId = 0x7965db0b;
        assertTrue(ticketNFT.supportsInterface(accessControlInterfaceId));
    }

    // -----------------------------
    // Enumeration Tests
    // -----------------------------

    function test_Enumeration() public {
        uint256 quantity = 5;

        // Mint tokens to user1
        vm.prank(minter);
        uint256[] memory tokenIds = ticketNFT.mintBatch(
            user1,
            quantity,
            DRAW_ID
        );

        // Test totalSupply
        assertEq(ticketNFT.totalSupply(), quantity);

        // Test tokenByIndex
        for (uint256 i = 0; i < quantity; i++) {
            assertEq(ticketNFT.tokenByIndex(i), tokenIds[i]);
        }

        // Test tokenOfOwnerByIndex
        for (uint256 i = 0; i < quantity; i++) {
            assertEq(ticketNFT.tokenOfOwnerByIndex(user1, i), tokenIds[i]);
        }

        // Test balanceOf
        assertEq(ticketNFT.balanceOf(user1), quantity);
    }

    // -----------------------------
    // Manager Tests
    // -----------------------------

    function test_UpdateLotteryManagerReverts() public {
        vm.prank(owner);
        vm.expectRevert(TicketNFT.ManagerImmutable.selector);
        ticketNFT.updateLotteryManager(user1);
    }

    // -----------------------------
    // Helper Functions
    // -----------------------------

    function getTokenIdsArray(
        uint256 start,
        uint256 count
    ) private pure returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            ids[i] = start + i;
        }
        return ids;
    }
}
