// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {FORT} from "../src/core/FORT.sol"; // Adjust path as needed

/**
 * @title FORT Token Test Suite
 * @notice Comprehensive tests for the FORT governance token with 100% code coverage
 * @dev This test suite uses Foundry's testing framework to fully test:
 *  - Constructor functionality and initial state
 *  - Role-based access control
 *  - Minting operations and supply cap enforcement
 *  - Burning operations
 *  - ERC20 standard functionality
 *  - ERC20Permit functionality
 *  - Voting power tracking (ERC20Votes)
 *  - All custom error states
 */
contract FORTTest is Test {
    // Constants
    string constant TOKEN_NAME = "dFortune";
    string constant TOKEN_SYMBOL = "FORT";
    uint256 constant MAX_SUPPLY = 100_000_000 * 1e18; // 100 million tokens

    // Contract instance
    FORT public fort;

    // Role constants
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    // Test accounts
    address public admin;
    address public minter;
    address public user1;
    address public user2;

    /**
     * @notice Set up test environment before each test
     * @dev Deploys a new FORT token and sets up test accounts
     */
    function setUp() public {
        // Create test accounts with labels for better trace readability
        admin = makeAddr("admin");
        minter = makeAddr("minter");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy FORT token with admin as the initial admin
        fort = new FORT(admin);

        // Label contract address for better trace output
        vm.label(address(fort), "FORT");
    }

    /*//////////////////////////////////////////////////////////////
                    DEPLOYMENT AND INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tests that the token is initialized with correct name and symbol
     */
    function test_TokenMetadata() public {
        assertEq(fort.name(), TOKEN_NAME);
        assertEq(fort.symbol(), TOKEN_SYMBOL);
    }

    /**
     * @notice Tests that the max supply constant is set correctly
     */
    function test_MaxSupply() public {
        assertEq(fort.MAX_SUPPLY(), MAX_SUPPLY);
    }

    /**
     * @notice Tests that totalMinted is initialized to zero
     */
    function test_InitialTotalMinted() public {
        assertEq(fort.totalMinted(), 0);
    }

    /**
     * @notice Tests that admin roles are assigned correctly during deployment
     */
    function test_AdminRoleAssignment() public {
        assertTrue(fort.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(fort.hasRole(MINTER_ROLE, admin));
    }

    /**
     * @notice Tests that deployment reverts if admin is set to zero address
     */
    function test_RevertIf_ZeroAddressAdmin() public {
        vm.expectRevert(FORT.ZeroAddressProhibited.selector);
        new FORT(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        ROLE MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tests that admin can grant MINTER_ROLE
     */
    function test_AdminCanGrantMinterRole() public {
        vm.prank(admin);
        fort.grantRole(MINTER_ROLE, minter);

        assertTrue(fort.hasRole(MINTER_ROLE, minter));
    }

    /**
     * @notice Tests that admin can revoke MINTER_ROLE
     */
    function test_AdminCanRevokeMinterRole() public {
        // First grant the role
        vm.prank(admin);
        fort.grantRole(MINTER_ROLE, minter);
        assertTrue(fort.hasRole(MINTER_ROLE, minter));

        // Then revoke it
        vm.prank(admin);
        fort.revokeRole(MINTER_ROLE, minter);
        assertFalse(fort.hasRole(MINTER_ROLE, minter));
    }

    /**
     * @notice Tests that non-admin cannot grant roles
     */
    function test_RevertIf_NonAdminGrantsRole() public {
        bytes memory customError = abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            user1,
            DEFAULT_ADMIN_ROLE
        );

        vm.prank(user1);
        vm.expectRevert(customError);
        fort.grantRole(MINTER_ROLE, user2);
    }

    /*//////////////////////////////////////////////////////////////
                        MINTING FUNCTIONALITY TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tests that MINTER_ROLE can mint tokens
     */
    function test_MinterCanMintTokens() public {
        uint256 mintAmount = 1000 * 1e18;

        vm.prank(admin);
        fort.mint(user1, mintAmount);

        assertEq(fort.balanceOf(user1), mintAmount);
        assertEq(fort.totalSupply(), mintAmount);
        assertEq(fort.totalMinted(), mintAmount);
    }

    /**
     * @notice Tests that totalMinted is properly updated when minting
     */
    function test_TotalMintedUpdatesCorrectly() public {
        uint256 mintAmount1 = 1000 * 1e18;
        uint256 mintAmount2 = 2000 * 1e18;

        vm.startPrank(admin);
        fort.mint(user1, mintAmount1);
        assertEq(fort.totalMinted(), mintAmount1);

        fort.mint(user1, mintAmount2);
        assertEq(fort.totalMinted(), mintAmount1 + mintAmount2);
        vm.stopPrank();
    }

    /**
     * @notice Tests that minting to zero address is prevented
     */
    function test_RevertIf_MintToZeroAddress() public {
        uint256 mintAmount = 1000 * 1e18;

        vm.prank(admin);
        vm.expectRevert(FORT.ZeroAddressProhibited.selector);
        fort.mint(address(0), mintAmount);
    }

    /**
     * @notice Tests that non-minters cannot mint tokens
     */
    function test_RevertIf_NonMinterMints() public {
        uint256 mintAmount = 1000 * 1e18;

        bytes memory customError = abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            user1,
            MINTER_ROLE
        );

        vm.prank(user1);
        vm.expectRevert(customError);
        fort.mint(user2, mintAmount);
    }

    /**
     * @notice Tests that minting above MAX_SUPPLY is prevented
     */
    function test_RevertIf_MintAboveMaxSupply() public {
        // Try to mint more than MAX_SUPPLY
        uint256 tooMuch = MAX_SUPPLY + 1;

        vm.prank(admin);
        vm.expectRevert(FORT.ExceedsMaxSupply.selector);
        fort.mint(user1, tooMuch);
    }

    /**
     * @notice Tests that minting exactly MAX_SUPPLY is allowed
     */
    function test_CanMintExactlyMaxSupply() public {
        vm.prank(admin);
        fort.mint(user1, MAX_SUPPLY);

        assertEq(fort.totalMinted(), MAX_SUPPLY);
        assertEq(fort.totalSupply(), MAX_SUPPLY);
        assertEq(fort.balanceOf(user1), MAX_SUPPLY);
    }

    /**
     * @notice Tests that minting fails if it would exceed MAX_SUPPLY in multiple operations
     */
    function test_RevertIf_MintingExceedsMaxSupplyInMultipleOps() public {
        uint256 halfSupply = MAX_SUPPLY / 2;
        uint256 slightlyLessHalf = halfSupply - 1000 * 1e18;
        uint256 remainingPlusExtra = MAX_SUPPLY -
            halfSupply -
            slightlyLessHalf +
            1;

        vm.startPrank(admin);
        fort.mint(user1, halfSupply);
        fort.mint(user1, slightlyLessHalf);

        vm.expectRevert(FORT.ExceedsMaxSupply.selector);
        fort.mint(user1, remainingPlusExtra);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        BURNING FUNCTIONALITY TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tests that MINTER_ROLE can burn tokens
     */
    function test_MinterCanBurnTokens() public {
        uint256 mintAmount = 1000 * 1e18;
        uint256 burnAmount = 500 * 1e18;

        vm.startPrank(admin);
        fort.mint(user1, mintAmount);
        fort.burn(user1, burnAmount);
        vm.stopPrank();

        assertEq(fort.balanceOf(user1), mintAmount - burnAmount);
        assertEq(fort.totalSupply(), mintAmount - burnAmount);
        // totalMinted should remain unchanged after burning
        assertEq(fort.totalMinted(), mintAmount);
    }

    /**
     * @notice Tests that non-minters cannot burn tokens
     */
    function test_RevertIf_NonMinterBurns() public {
        uint256 mintAmount = 1000 * 1e18;
        uint256 burnAmount = 500 * 1e18;

        vm.prank(admin);
        fort.mint(user1, mintAmount);

        bytes memory customError = abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            user2,
            MINTER_ROLE
        );

        vm.prank(user2);
        vm.expectRevert(customError);
        fort.burn(user1, burnAmount);
    }

    /**
     * @notice Tests that burning more tokens than a user has is prevented
     */
    function test_RevertIf_BurnMoreThanBalance() public {
        uint256 mintAmount = 1000 * 1e18;
        uint256 burnAmount = 1001 * 1e18; // More than minted

        vm.prank(admin);
        fort.mint(user1, mintAmount);

        vm.prank(admin);
        vm.expectRevert(FORT.InvalidBurnAmount.selector);
        fort.burn(user1, burnAmount);
    }

    /**
     * @notice Tests that burning zero tokens is prevented
     */
    function test_RevertIf_BurnZeroTokens() public {
        uint256 mintAmount = 1000 * 1e18;

        vm.prank(admin);
        fort.mint(user1, mintAmount);

        vm.prank(admin);
        vm.expectRevert(FORT.InvalidBurnAmount.selector);
        fort.burn(user1, 0);
    }

    /*//////////////////////////////////////////////////////////////
                      ERC20 STANDARD FUNCTIONALITY TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tests that token transfers work correctly
     */
    function test_TokenTransfers() public {
        uint256 mintAmount = 1000 * 1e18;
        uint256 transferAmount = 400 * 1e18;

        vm.prank(admin);
        fort.mint(user1, mintAmount);

        vm.prank(user1);
        fort.transfer(user2, transferAmount);

        assertEq(fort.balanceOf(user1), mintAmount - transferAmount);
        assertEq(fort.balanceOf(user2), transferAmount);
    }

    /**
     * @notice Tests that token approvals and transferFrom work correctly
     */
    function test_ApproveAndTransferFrom() public {
        uint256 mintAmount = 1000 * 1e18;
        uint256 approveAmount = 600 * 1e18;
        uint256 transferAmount = 400 * 1e18;

        vm.prank(admin);
        fort.mint(user1, mintAmount);

        vm.prank(user1);
        fort.approve(user2, approveAmount);

        vm.prank(user2);
        fort.transferFrom(user1, user2, transferAmount);

        assertEq(fort.balanceOf(user1), mintAmount - transferAmount);
        assertEq(fort.balanceOf(user2), transferAmount);
        assertEq(fort.allowance(user1, user2), approveAmount - transferAmount);
    }

    /*//////////////////////////////////////////////////////////////
                       ERC20PERMIT FUNCTIONALITY TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tests the ERC20Permit functionality
     * @dev Creates and applies an EIP-2612 permit
     */
    function test_PermitFunctionality() public {
        uint256 privateKey = 0xA11CE;
        address owner = vm.addr(privateKey);

        uint256 mintAmount = 1000 * 1e18;

        vm.prank(admin);
        fort.mint(owner, mintAmount);

        uint256 value = 500 * 1e18;
        uint256 deadline = block.timestamp + 1 hours;

        // Prepare permit signature
        bytes32 domainSeparator = fort.DOMAIN_SEPARATOR();

        bytes32 permitTypehash = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(
                permitTypehash,
                owner,
                user2,
                value,
                fort.nonces(owner),
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        // Execute permit
        fort.permit(owner, user2, value, deadline, v, r, s);

        // Check result
        assertEq(fort.allowance(owner, user2), value);
        assertEq(fort.nonces(owner), 1);

        // Use the allowance
        vm.prank(user2);
        fort.transferFrom(owner, user2, value);

        assertEq(fort.balanceOf(owner), mintAmount - value);
        assertEq(fort.balanceOf(user2), value);
    }

    /**
     * @notice Tests expired deadline case for permit
     * @dev Updated to expect the custom error ERC2612ExpiredSignature
     */
    function test_PermitExpiredDeadline() public {
        uint256 privateKey = 0xA11CE;
        address owner = vm.addr(privateKey);

        uint256 mintAmount = 1000 * 1e18;

        vm.prank(admin);
        fort.mint(owner, mintAmount);

        uint256 value = 500 * 1e18;
        uint256 expiredDeadline = block.timestamp - 1;

        bytes32 domainSeparator = fort.DOMAIN_SEPARATOR();
        bytes32 permitTypehash = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(
                permitTypehash,
                owner,
                user2,
                value,
                fort.nonces(owner),
                expiredDeadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        // Expect revert with custom error ERC2612ExpiredSignature
        vm.expectRevert(
            abi.encodeWithSignature("ERC2612ExpiredSignature(uint256)", 0)
        );
        fort.permit(owner, user2, value, expiredDeadline, v, r, s);
    }

    /**
     * @notice Tests invalid signature case for permit
     * @dev Updated to expect the custom error ERC2612InvalidSigner
     */
    function test_PermitInvalidSignature() public {
        uint256 privateKey = 0xA11CE;
        address owner = vm.addr(privateKey);

        uint256 mintAmount = 1000 * 1e18;

        vm.prank(admin);
        fort.mint(owner, mintAmount);

        uint256 value = 500 * 1e18;
        uint256 validDeadline = block.timestamp + 1 hours;

        bytes32 domainSeparator = fort.DOMAIN_SEPARATOR();
        bytes32 permitTypehash = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(
                permitTypehash,
                owner,
                user2,
                value,
                fort.nonces(owner),
                validDeadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        // Use different private key to generate invalid signature
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey + 1, digest);

        // Get the recovered address to use in the error expectation (from trace logs)
        address recoveredAddress = 0xE27316fFF4839576802e8bFB695810C153bFcB92;

        // Expect revert with custom error ERC2612InvalidSigner
        vm.expectRevert(
            abi.encodeWithSignature(
                "ERC2612InvalidSigner(address,address)",
                recoveredAddress,
                owner
            )
        );
        fort.permit(owner, user2, value, validDeadline, v, r, s);
    }

    /**
     * @notice Tests replay protection for permits
     * @dev Updated to expect the custom error ERC2612InvalidSigner
     */
    function test_PermitReplayProtection() public {
        uint256 privateKey = 0xA11CE;
        address owner = vm.addr(privateKey);

        uint256 mintAmount = 1000 * 1e18;

        vm.prank(admin);
        fort.mint(owner, mintAmount);

        uint256 value = 500 * 1e18;
        uint256 validDeadline = block.timestamp + 1 hours;

        bytes32 domainSeparator = fort.DOMAIN_SEPARATOR();
        bytes32 permitTypehash = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(
                permitTypehash,
                owner,
                user2,
                value,
                fort.nonces(owner),
                validDeadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        // Execute valid permit
        fort.permit(owner, user2, value, validDeadline, v, r, s);

        // Get the recovered address to use in the error expectation (from trace logs)
        address recoveredAddress = 0x9a0550eB0fbaf58e1Ea80f0765822B1c1a14059e;

        // Try to use the same signature again
        vm.expectRevert(
            abi.encodeWithSignature(
                "ERC2612InvalidSigner(address,address)",
                recoveredAddress,
                owner
            )
        );
        fort.permit(owner, user2, value, validDeadline, v, r, s);
    }

    /*//////////////////////////////////////////////////////////////
                     VOTING POWER FUNCTIONALITY TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tests that voting power is tracked correctly on token transfers
     */
    function test_VotingPowerTracking() public {
        uint256 mintAmount = 1000 * 1e18;
        uint256 transferAmount = 400 * 1e18;

        vm.prank(admin);
        fort.mint(user1, mintAmount);

        // Initially no voting power until delegated
        assertEq(fort.getVotes(user1), 0);

        // Delegate to self to activate voting power
        vm.prank(user1);
        fort.delegate(user1);

        assertEq(fort.getVotes(user1), mintAmount);

        // Transfer tokens to user2
        vm.prank(user1);
        fort.transfer(user2, transferAmount);

        assertEq(fort.getVotes(user1), mintAmount - transferAmount);

        // Delegate user2's votes to themselves
        vm.prank(user2);
        fort.delegate(user2);

        assertEq(fort.getVotes(user2), transferAmount);
    }

    /**
     * @notice Tests that historical voting power is tracked correctly with checkpoints
     */
    function test_HistoricalVotingPower() public {
        uint256 mintAmount = 1000 * 1e18;
        uint256 additionalAmount = 500 * 1e18;

        // Mint initial tokens
        vm.prank(admin);
        fort.mint(user1, mintAmount);

        // Delegate to self to activate voting power
        vm.prank(user1);
        fort.delegate(user1);

        // Store the block number for historical check
        uint256 firstBlockNumber = block.number;

        // Move to next block
        vm.roll(block.number + 1);

        // Mint more tokens
        vm.prank(admin);
        fort.mint(user1, additionalAmount);

        // Check historical voting power
        assertEq(fort.getPastVotes(user1, firstBlockNumber), mintAmount);
        assertEq(fort.getVotes(user1), mintAmount + additionalAmount);
    }

    /**
     * @notice Tests delegation of voting power
     */
    function test_DelegationOfVotingPower() public {
        uint256 mintAmount = 1000 * 1e18;

        vm.prank(admin);
        fort.mint(user1, mintAmount);

        // Check initial voting power
        assertEq(fort.getVotes(user1), 0);
        assertEq(fort.getVotes(user2), 0);

        // Delegate to user2
        vm.prank(user1);
        fort.delegate(user2);

        // Check voting power after delegation
        assertEq(fort.getVotes(user1), 0);
        assertEq(fort.getVotes(user2), mintAmount);

        // Change delegation back to self
        vm.prank(user1);
        fort.delegate(user1);

        // Check voting power after changing delegation
        assertEq(fort.getVotes(user1), mintAmount);
        assertEq(fort.getVotes(user2), 0);
    }

    /**
     * @notice Tests voting power updates through the _update override
     * @dev This tests the critical integration between ERC20 operations and ERC20Votes
     */
    function test_UpdateFunctionVotingPowerIntegration() public {
        uint256 mintAmount = 1000 * 1e18;

        // Mint tokens to user1
        vm.prank(admin);
        fort.mint(user1, mintAmount);

        // Both users delegate to themselves to activate voting power
        vm.prank(user1);
        fort.delegate(user1);
        vm.prank(user2);
        fort.delegate(user2);

        // Verify initial voting power
        assertEq(fort.getVotes(user1), mintAmount);
        assertEq(fort.getVotes(user2), 0);

        // Test that various operations correctly update voting power

        // 1. Transfer updates voting power
        uint256 transferAmount = 400 * 1e18;
        vm.prank(user1);
        fort.transfer(user2, transferAmount);

        assertEq(fort.getVotes(user1), mintAmount - transferAmount);
        assertEq(fort.getVotes(user2), transferAmount);

        // 2. Mint updates voting power (for active delegations)
        uint256 additionalMint = 200 * 1e18;
        vm.prank(admin);
        fort.mint(user1, additionalMint);

        assertEq(
            fort.getVotes(user1),
            mintAmount - transferAmount + additionalMint
        );

        // 3. Burn updates voting power
        uint256 burnAmount = 100 * 1e18;
        vm.prank(admin);
        fort.burn(user1, burnAmount);

        assertEq(
            fort.getVotes(user1),
            mintAmount - transferAmount + additionalMint - burnAmount
        );

        // 4. TransferFrom updates voting power
        uint256 approveAmount = 300 * 1e18;
        vm.prank(user1);
        fort.approve(user2, approveAmount);

        uint256 transferFromAmount = 200 * 1e18;
        vm.prank(user2);
        fort.transferFrom(user1, user2, transferFromAmount);

        assertEq(
            fort.getVotes(user1),
            mintAmount -
                transferAmount +
                additionalMint -
                burnAmount -
                transferFromAmount
        );
        assertEq(fort.getVotes(user2), transferAmount + transferFromAmount);
    }

    /*//////////////////////////////////////////////////////////////
                      NONCES FUNCTIONALITY TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tests that nonces handling for permit operations
     * @dev In OpenZeppelin v5, delegation operations don't increment nonces anymore,
     *      only permit operations do. We test this with a permit operation.
     */
    function test_NoncesHandling() public {
        uint256 privateKey = 0xB0B;
        address owner = vm.addr(privateKey);

        // Check initial nonce
        assertEq(fort.nonces(owner), 0);

        // Mint some tokens to the owner
        vm.prank(admin);
        fort.mint(owner, 1000 * 1e18);

        // Create a permit
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 domainSeparator = fort.DOMAIN_SEPARATOR();

        bytes32 permitTypehash = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(
                permitTypehash,
                owner,
                user1,
                500 * 1e18,
                fort.nonces(owner),
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        // Execute permit operation
        fort.permit(owner, user1, 500 * 1e18, deadline, v, r, s);

        // Check nonce after permit operation
        assertEq(fort.nonces(owner), 1);
    }

    /*//////////////////////////////////////////////////////////////
                        FULL LIFECYCLE SCENARIO
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tests a complete lifecycle flow with all operations
     */
    function test_FullLifecycleFlow() public {
        // Grant minter role
        vm.prank(admin);
        fort.grantRole(MINTER_ROLE, minter);

        // Mint tokens as minter
        uint256 mintAmount = 10000 * 1e18;
        vm.prank(minter);
        fort.mint(user1, mintAmount);

        // User1 delegates to self
        vm.prank(user1);
        fort.delegate(user1);

        // User1 transfers to user2
        uint256 transferAmount = 3000 * 1e18;
        vm.prank(user1);
        fort.transfer(user2, transferAmount);

        // User2 delegates to self
        vm.prank(user2);
        fort.delegate(user2);

        // Minter burns some of user1's tokens
        uint256 burnAmount = 1000 * 1e18;
        vm.prank(minter);
        fort.burn(user1, burnAmount);

        // Verify final state
        assertEq(
            fort.balanceOf(user1),
            mintAmount - transferAmount - burnAmount
        );
        assertEq(fort.balanceOf(user2), transferAmount);
        assertEq(fort.totalSupply(), mintAmount - burnAmount);
        assertEq(fort.totalMinted(), mintAmount);
        assertEq(
            fort.getVotes(user1),
            mintAmount - transferAmount - burnAmount
        );
        assertEq(fort.getVotes(user2), transferAmount);
    }
}
