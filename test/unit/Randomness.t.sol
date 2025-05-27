// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Randomness} from "../../src/core/Randomness.sol";
import {MockVRFCoordinatorV2} from "../mocks/MockVRFCoordinatorV2.sol";
import {LotteryManager} from "../../src/core/LotteryManager.sol";
import {ILotteryManager} from "../../src/interfaces/ILotteryManager.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RandomnessTest
 * @notice Comprehensive test suite for the Randomness contract
 * @dev Tests all functions and edge cases for the Randomness contract
 */
contract RandomnessTest is Test {
    // Contract instances
    Randomness public randomness;
    MockVRFCoordinatorV2 public vrfCoordinator;

    // We'll use a mock for this interface to avoid full dependency chain
    ILotteryManager public mockLotteryManager;

    // Test accounts
    address public owner;
    address public user;
    address public newOwner;

    // Constants used for test
    bytes32 public constant KEY_HASH =
        0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c;
    uint64 public constant SUBSCRIPTION_ID = 1234;
    uint32 public constant DEFAULT_CALLBACK_GAS_LIMIT = 500_000;
    uint16 public constant DEFAULT_REQUEST_CONFIRMATIONS = 3;

    // Events to test against
    event RandomnessRequested(uint256 indexed drawId, uint256 requestId);
    event RandomnessFulfilled(uint256 indexed drawId, uint256 requestId);
    event SubscriptionUpdated(uint64 newSubscriptionId);
    event CallbackGasLimitUpdated(uint32 newGasLimit);

    // Custom errors to test against
    error InvalidCaller();
    error InvalidRequest();
    error InsufficientFunds();
    error AlreadyFulfilled();
    error InvalidCoordinator();
    error OwnableUnauthorizedAccount(address account);

    /**
     * @notice Setup test environment before each test
     * @dev Deploy mock contracts and the Randomness contract
     */
    function setUp() public {
        // Setup accounts
        owner = makeAddr("owner");
        user = makeAddr("user");
        newOwner = makeAddr("newOwner");

        // Deploy mock contracts
        vrfCoordinator = new MockVRFCoordinatorV2();

        // Deploy a mock lottery manager instead of using the real one
        // This simplifies testing of the Randomness contract in isolation
        mockLotteryManager = new MockLotteryManagerMinimal();

        // Deploy the Randomness contract with initial configuration
        vm.startPrank(owner);
        randomness = new Randomness(
            address(vrfCoordinator),
            KEY_HASH,
            SUBSCRIPTION_ID,
            address(mockLotteryManager),
            owner
        );
        vm.stopPrank();
    }

    /**
     * @notice Test constructor initialization
     * @dev Verifies all initial values are correctly set
     */
    function testConstructor() public {
        // Verify initial state variables
        assertEq(
            address(randomness.VRF_COORDINATOR()),
            address(vrfCoordinator)
        );
        assertEq(randomness.KEY_HASH(), KEY_HASH);
        assertEq(randomness.subscriptionId(), SUBSCRIPTION_ID);
        assertEq(
            address(randomness.lotteryManager()),
            address(mockLotteryManager)
        );
        assertEq(randomness.owner(), owner);
        assertEq(randomness.callbackGasLimit(), DEFAULT_CALLBACK_GAS_LIMIT);
        assertEq(
            randomness.requestConfirmations(),
            DEFAULT_REQUEST_CONFIRMATIONS
        );
    }

    /**
     * @notice Test constructor with zero address for VRF coordinator
     * @dev Should revert with InvalidCoordinator error
     */
    function testConstructorWithZeroCoordinator() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidCoordinator.selector));
        new Randomness(
            address(0),
            KEY_HASH,
            SUBSCRIPTION_ID,
            address(mockLotteryManager),
            owner
        );
    }

    /**
     * @notice Test requesting a random number
     * @dev Verifies correct event emission and state changes
     */
    function testRequestRandomNumber() public {
        uint256 drawId = 1;
        uint256 expectedRequestId = 0; // First request ID from mock

        // Setup mock VRF coordinator to return request ID 0
        vrfCoordinator.setNextRequestId(expectedRequestId);

        // Only manager can call
        vm.prank(address(mockLotteryManager));

        // Expect the event to be emitted
        vm.expectEmit(true, true, false, true);
        emit RandomnessRequested(drawId, expectedRequestId);

        // Call the function
        uint256 requestId = randomness.requestRandomNumber(drawId);

        // Verify state changes
        assertEq(requestId, expectedRequestId);

        // Get the stored values
        (uint256 storedDrawId, bool fulfilled) = randomness.vrfRequests(
            requestId
        );

        assertEq(storedDrawId, drawId);
        assertEq(fulfilled, false);
        assertEq(randomness.drawToRequestId(drawId), requestId);
    }

    /**
     * @notice Test requesting a random number with non-manager account
     * @dev Should revert with InvalidCaller error
     */
    function testRequestRandomNumberNotManager() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(InvalidCaller.selector));
        randomness.requestRandomNumber(1);
    }

    /**
     * @notice Test requesting a random number for an existing draw
     * @dev Should revert with InvalidRequest error
     */
    function testRequestRandomNumberExistingDraw() public {
        uint256 drawId = 1;

        // First request (should succeed)
        vm.startPrank(address(mockLotteryManager));

        // Setup mock VRF coordinator to return request ID 0
        vrfCoordinator.setNextRequestId(1);

        // First request
        uint256 firstRequestId = randomness.requestRandomNumber(drawId);

        // Verify the mapping is updated correctly
        assertEq(randomness.drawToRequestId(drawId), firstRequestId);

        // Debug output to verify the value
        console.log("Draw ID:", drawId);
        console.log("First Request ID:", firstRequestId);
        console.log("Stored Request ID:", randomness.drawToRequestId(drawId));

        // Second request for same drawId (should fail)
        vrfCoordinator.setNextRequestId(1); // Set a different request ID

        // This should revert with InvalidRequest
        vm.expectRevert(abi.encodeWithSelector(InvalidRequest.selector));
        randomness.requestRandomNumber(drawId);

        vm.stopPrank();
    }

    /**
     * @notice Test fulfillment of random words
     * @dev Verifies callback functionality and state updates
     */
    function testFulfillRandomWords() public {
        uint256 drawId = 1;
        uint256 requestId = 0;

        // Setup request
        vrfCoordinator.setNextRequestId(requestId);
        vm.prank(address(mockLotteryManager));
        randomness.requestRandomNumber(drawId);

        // Prepare random words
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 12345;

        // Mock the fulfillment call that would come from VRF coordinator
        vm.expectEmit(true, true, false, true);
        emit RandomnessFulfilled(drawId, requestId);

        vm.prank(address(vrfCoordinator));
        vrfCoordinator.fulfillRandomWordsWithCallback(
            requestId,
            address(randomness),
            randomWords
        );

        // Get the stored values
        (uint256 storedDrawId, bool fulfilled) = randomness.vrfRequests(
            requestId
        );

        // Get the random words through the mock lottery manager instead
        MockLotteryManagerMinimal mockLM = MockLotteryManagerMinimal(
            address(mockLotteryManager)
        );
        uint256[] memory storedRandomWords = mockLM.lastRandomWords();

        assertEq(storedDrawId, drawId);
        assertEq(fulfilled, true);
        assertEq(storedRandomWords.length, 10); // Should expand to 10 values

        // Verify LotteryManager was called
        assertEq(mockLM.lastDrawId(), drawId);
    }

    /**
     * @notice Test double fulfillment of random words
     * @dev Should revert with AlreadyFulfilled error
     */
    function testFulfillRandomWordsAlreadyFulfilled() public {
        uint256 drawId = 1;
        uint256 requestId = 0;

        // Setup and fulfill request first time
        vrfCoordinator.setNextRequestId(requestId);
        vm.prank(address(mockLotteryManager));
        randomness.requestRandomNumber(drawId);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 12345;

        vm.prank(address(vrfCoordinator));
        vrfCoordinator.fulfillRandomWordsWithCallback(
            requestId,
            address(randomness),
            randomWords
        );

        // Try to fulfill again
        vm.prank(address(vrfCoordinator));
        vm.expectRevert(abi.encodeWithSelector(AlreadyFulfilled.selector));
        vrfCoordinator.fulfillRandomWordsWithCallback(
            requestId,
            address(randomness),
            randomWords
        );
    }

    /**
     * @notice Test random number expansion
     * @dev Verifies that one seed expands to multiple distinct values
     */
    function testRandomNumberExpansion() public {
        uint256 drawId = 1;
        uint256 requestId = 0;

        // Setup request
        vrfCoordinator.setNextRequestId(requestId);
        vm.prank(address(mockLotteryManager));
        randomness.requestRandomNumber(drawId);

        // Fulfill with known seed
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 12345;

        vm.prank(address(vrfCoordinator));
        vrfCoordinator.fulfillRandomWordsWithCallback(
            requestId,
            address(randomness),
            randomWords
        );

        // Fix: Get the random words through the mock lottery manager
        MockLotteryManagerMinimal mockLM = MockLotteryManagerMinimal(
            address(mockLotteryManager)
        );
        uint256[] memory expandedWords = mockLM.lastRandomWords();

        // Check length
        assertEq(expandedWords.length, 10);

        // Check each expanded value is unique
        for (uint256 i = 0; i < expandedWords.length; i++) {
            for (uint256 j = i + 1; j < expandedWords.length; j++) {
                assertTrue(expandedWords[i] != expandedWords[j]);
            }
        }
    }

    /**
     * @notice Test updating subscription ID
     * @dev Verifies owner permissions and state updates
     */
    function testUpdateSubscriptionId() public {
        uint64 newSubscriptionId = 5678;

        // Only owner can update
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit SubscriptionUpdated(newSubscriptionId);

        randomness.updateSubscriptionId(newSubscriptionId);

        // Verify state change
        assertEq(randomness.subscriptionId(), newSubscriptionId);
    }

    /**
     * @notice Test updating subscription ID by non-owner
     * @dev Should revert with OwnableUnauthorizedAccount error
     */
    function testUpdateSubscriptionIdNotOwner() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user)
        );
        randomness.updateSubscriptionId(5678);
    }

    /**
     * @notice Test setting callback gas limit
     * @dev Verifies owner permissions and state updates
     */
    function testSetCallbackGasLimit() public {
        uint32 newGasLimit = 300_000;

        // Only owner can update
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit CallbackGasLimitUpdated(newGasLimit);

        randomness.setCallbackGasLimit(newGasLimit);

        // Verify state change
        assertEq(randomness.callbackGasLimit(), newGasLimit);
    }

    /**
     * @notice Test setting callback gas limit by non-owner
     * @dev Should revert with OwnableUnauthorizedAccount error
     */
    function testSetCallbackGasLimitNotOwner() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user)
        );
        randomness.setCallbackGasLimit(300_000);
    }

    /**
     * @notice Test setting callback gas limit above max threshold
     * @dev Should revert with InvalidRequest error
     */
    function testSetCallbackGasLimitTooHigh() public {
        uint32 tooHighGasLimit = 3_000_000; // Above 2.5M limit

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(InvalidRequest.selector));
        randomness.setCallbackGasLimit(tooHighGasLimit);
    }

    /**
     * @notice Test LINK token withdrawal
     * @dev Verifies owner permissions and fund transfers
     */
    function testWithdrawLINK() public {
        uint256 amount = 1 ether;

        // Fund the contract
        vm.deal(address(randomness), amount);

        // Check starting balances
        uint256 initialContractBalance = address(randomness).balance;
        uint256 initialOwnerBalance = owner.balance;

        // Withdraw funds
        vm.prank(owner);
        randomness.withdrawLINK(owner, amount);

        // Verify balances after withdrawal
        assertEq(address(randomness).balance, initialContractBalance - amount);
        assertEq(owner.balance, initialOwnerBalance + amount);
    }

    /**
     * @notice Test LINK token withdrawal by non-owner
     * @dev Should revert with OwnableUnauthorizedAccount error
     */
    function testWithdrawLINKNotOwner() public {
        vm.deal(address(randomness), 1 ether);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user)
        );
        randomness.withdrawLINK(user, 1 ether);
    }

    /**
     * @notice Test LINK token withdrawal with insufficient funds
     * @dev Should revert with InsufficientFunds error
     */
    function testWithdrawLINKInsufficientFunds() public {
        // Fund contract with 0.5 ETH
        vm.deal(address(randomness), 0.5 ether);

        // Try to withdraw 1 ETH
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(InsufficientFunds.selector));
        randomness.withdrawLINK(owner, 1 ether);
    }

    /**
     * @notice Test LINK token withdrawal to a reverting recipient
     * @dev Should revert with InvalidRequest error
     */
    function testWithdrawLINKToRevertingRecipient() public {
        // Deploy a contract that reverts on receive
        RevertingRecipient revertingRecipient = new RevertingRecipient();

        // Fund the randomness contract
        vm.deal(address(randomness), 1 ether);

        // Try to withdraw to reverting recipient
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(InvalidRequest.selector));
        randomness.withdrawLINK(address(revertingRecipient), 1 ether);
    }

    /**
     * @notice Test ownership transfer process (from Ownable2Step)
     * @dev Verifies the two-step ownership transfer process
     */
    function testOwnershipTransfer() public {
        // Step 1: Current owner proposes new owner
        vm.prank(owner);
        randomness.transferOwnership(newOwner);

        // Verify pending owner
        assertEq(randomness.pendingOwner(), newOwner);
        assertEq(randomness.owner(), owner);

        // Step 2: New owner accepts ownership
        vm.prank(newOwner);
        randomness.acceptOwnership();

        // Verify ownership changed
        assertEq(randomness.owner(), newOwner);
        assertEq(randomness.pendingOwner(), address(0));
    }

    /**
     * @notice Test direct access to fulfillRandomWords function
     * @dev Should revert as it can only be called by VRF Coordinator
     */
    function testDirectCallToFulfillRandomWords() public {
        // This test confirms that the fulfillRandomWords function cannot be
        // called directly, but we can't test it directly since it's internal.
        // Instead, we rely on the VRFConsumerBaseV2 implementation.

        // Setup a request so we have a valid requestId
        uint256 drawId = 1;
        uint256 requestId = 0;

        vrfCoordinator.setNextRequestId(requestId);
        vm.prank(address(mockLotteryManager));
        randomness.requestRandomNumber(drawId);

        // Try to call rawFulfillRandomWords directly (exposed by VRFConsumerBaseV2)
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 12345;

        // This should revert as we're not the coordinator
        // Using a different approach that will ensure we catch the revert
        vm.expectRevert("only coordinator can fulfill");
        vm.prank(user); // Not the coordinator
        vrfCoordinator.callRawFulfillRandomWords(
            address(randomness),
            requestId,
            randomWords
        );
    }
}

/**
 * @title RevertingRecipient
 * @notice Mock contract that reverts on receiving ETH
 * @dev Used to test failure scenarios in withdrawLINK
 */
contract RevertingRecipient {
    // Always revert when receiving ETH
    receive() external payable {
        revert("I always revert");
    }
}

/**
 * @title MockLotteryManagerMinimal
 * @notice Minimal mock implementation of ILotteryManager for testing
 * @dev Implements required functions to pass compilation
 */
contract MockLotteryManagerMinimal is ILotteryManager {
    uint256 public lastDrawId;
    uint256[] internal _lastRandomWords;

    /**
     * @notice Implementation of completeDraw to validate callback
     * @param drawId ID of the draw
     * @param randomWords Array of random values
     */
    function completeDraw(
        uint256 drawId,
        uint256[] calldata randomWords
    ) external override {
        lastDrawId = drawId;
        delete _lastRandomWords;

        for (uint256 i = 0; i < randomWords.length; i++) {
            _lastRandomWords.push(randomWords[i]);
        }
    }

    /**
     * @notice Get the last random words received
     * @return Array of random values
     */
    function lastRandomWords() external view returns (uint256[] memory) {
        return _lastRandomWords;
    }

    // Required implementations for ILotteryManager interface
    function startNewDraw() external override {}

    function buyTickets(uint256) external payable override {}

    function triggerDraw() external override {}

    function getCurrentDraw()
        external
        pure
        override
        returns (
            uint256 drawId,
            uint256 startTime,
            uint256 endTime,
            uint8 phase
        )
    {
        return (0, 0, 0, 0);
    }

    function ticketPrice() external pure override returns (uint256) {
        return 0;
    }

    function getTicketOwner(uint256) external pure override returns (address) {
        return address(0);
    }
}
