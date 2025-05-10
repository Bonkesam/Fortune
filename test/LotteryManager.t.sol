// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {LotteryManager} from "../src/core/LotteryManager.sol";
import {MockTicketNFT} from "./mocks/MockTicketNFT.sol";
import {MockPrizePool} from "./mocks/MockPrizePool.sol";
import {MockRandomness} from "./mocks/MockRandomness.sol";
// Add this with other imports
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LotteryManagerTest
 * @dev Comprehensive test suite for LotteryManager contract
 * Ensures 100% line coverage with thorough testing of all functionality
 */
contract LotteryManagerTest is Test {
    // Constants
    uint256 constant TICKET_PRICE = 0.01 ether;
    uint256 constant SALE_PERIOD = 86400; // 1 day in seconds
    uint256 constant COOLDOWN_PERIOD = 43200; // 12 hours in seconds

    // Test accounts
    address owner = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    address user3 = address(0x4);

    // Contracts
    LotteryManager lotteryManager;
    MockTicketNFT mockTicketNFT;
    MockPrizePool mockPrizePool;
    MockRandomness mockRandomness;

    // Events (from LotteryManager)
    event DrawStarted(uint256 indexed drawId, uint256 startTime);
    event TicketsPurchased(
        uint256 indexed drawId,
        address indexed buyer,
        uint256 quantity
    );
    event DrawTriggered(uint256 indexed drawId, uint256 requestId);
    event DrawCompleted(uint256 indexed drawId, uint256[] winningNumbers);
    event EmergencyStopTriggered(uint256 indexed drawId);
    event FundsRecovered(address indexed recipient, uint256 amount);

    /**
     * @dev Sets up the test environment before each test
     */
    function setUp() public {
        // Set up accounts
        vm.startPrank(owner);

        // Deploy mock contracts
        mockTicketNFT = new MockTicketNFT(owner);
        mockPrizePool = new MockPrizePool();
        mockRandomness = new MockRandomness();

        // Deploy LotteryManager
        lotteryManager = new LotteryManager(
            address(mockTicketNFT),
            address(mockPrizePool),
            address(mockRandomness),
            TICKET_PRICE,
            SALE_PERIOD,
            COOLDOWN_PERIOD,
            owner
        );

        // Set permissions in mock contracts
        mockTicketNFT.setLotteryManager(address(lotteryManager));
        mockPrizePool.setLotteryManager(address(lotteryManager));
        mockRandomness.setLotteryManager(address(lotteryManager));

        vm.stopPrank();
    }

    /**
     * @dev Helper function to start a draw and buy tickets
     * @param numTickets Number of tickets to buy
     */
    function _startDrawAndBuyTickets(uint256 numTickets) internal {
        vm.prank(owner);
        lotteryManager.startNewDraw();

        if (numTickets > 0) {
            // Set up ticket IDs
            uint256[] memory ticketIds = new uint256[](numTickets);
            for (uint256 i = 0; i < numTickets; i++) {
                ticketIds[i] = i + 1;
            }
            mockTicketNFT.setNextTicketIds(ticketIds);

            // Buy tickets
            vm.deal(user1, TICKET_PRICE * numTickets);
            vm.prank(user1);
            lotteryManager.buyTickets{value: TICKET_PRICE * numTickets}(
                numTickets
            );
        }
    }

    /**
     * @dev Helper function to start a draw, buy tickets, and trigger draw
     * @param numTickets Number of tickets to buy
     */
    function _setupCompleteDraw(uint256 numTickets) internal {
        // Start draw and buy tickets
        _startDrawAndBuyTickets(numTickets);

        // Set up ticket owners
        for (uint256 i = 0; i < numTickets; i++) {
            mockTicketNFT.setTicketOwner(i + 1, user1);
        }

        // Fast forward past sale period
        vm.warp(block.timestamp + SALE_PERIOD + 1);

        // Trigger draw
        vm.prank(owner);
        lotteryManager.triggerDraw();
    }

    /**
     * @dev Verify the contract initializes correctly
     */
    function testInitialization() public {
        assertEq(address(lotteryManager.ticketNFT()), address(mockTicketNFT));
        assertEq(address(lotteryManager.prizePool()), address(mockPrizePool));
        assertEq(address(lotteryManager.randomness()), address(mockRandomness));
        assertEq(lotteryManager.ticketPrice(), TICKET_PRICE);
        assertEq(lotteryManager.salePeriod(), SALE_PERIOD);
        assertEq(lotteryManager.cooldownPeriod(), COOLDOWN_PERIOD);
        assertEq(lotteryManager.owner(), owner);
        assertEq(lotteryManager.currentDrawId(), 0);
    }

    /**
     * @dev Test starting a new draw
     */
    function testStartNewDraw() public {
        // Expected starting state
        assertEq(lotteryManager.currentDrawId(), 0);

        // Start a new draw
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit DrawStarted(1, block.timestamp);
        lotteryManager.startNewDraw();

        // Verify state changes
        assertEq(lotteryManager.currentDrawId(), 1);

        // Check draw details
        LotteryManager.Draw memory draw = lotteryManager.getCurrentDraw();
        assertEq(draw.drawId, 1);
        assertEq(draw.startTime, block.timestamp);
        assertEq(draw.endTime, block.timestamp + SALE_PERIOD);
        assertEq(uint256(draw.phase), 1); // DrawPhase.SaleOpen
    }

    /**
     * @dev Test attempting to start a new draw when one is already active
     */
    function testCannotStartNewDrawWhenActive() public {
        // Start first draw
        vm.prank(owner);
        lotteryManager.startNewDraw();

        // Try to start another
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(LotteryManager.InvalidPhase.selector, 4)
        ); // Expecting Completed
        lotteryManager.startNewDraw();
    }

    /**
     * @dev Test only owner can start new draw
     */
    function testOnlyOwnerCanStartDraw() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user1
            )
        );
        lotteryManager.startNewDraw();
    }

    /**
     * @dev Test starting multiple draws in sequence after completing each one
     */
    function testStartMultipleDraws() public {
        // Start first draw and buy enough tickets
        _setupCompleteDraw(10);

        // Complete draw with random numbers
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 123456789;
        vm.prank(address(mockRandomness));
        lotteryManager.CompleteDraw(1, randomWords);

        // Start second draw
        vm.prank(owner);
        lotteryManager.startNewDraw();

        // Verify state
        assertEq(lotteryManager.currentDrawId(), 2);

        LotteryManager.Draw memory draw = lotteryManager.getCurrentDraw();
        assertEq(draw.drawId, 2);
        assertEq(uint256(draw.phase), 1); // DrawPhase.SaleOpen
    }

    /**
     * @dev Test buying tickets
     */
    function testBuyTickets() public {
        // Start a draw
        vm.prank(owner);
        lotteryManager.startNewDraw();

        // Set up ticket IDs
        uint256[] memory ticketIds = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            ticketIds[i] = i + 1;
        }
        mockTicketNFT.setNextTicketIds(ticketIds);

        // Buy tickets as user1
        uint256 quantity = 3;
        uint256 cost = TICKET_PRICE * quantity;
        vm.deal(user1, cost);

        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit TicketsPurchased(1, user1, quantity);
        lotteryManager.buyTickets{value: cost}(quantity);

        // Verify ticket mint was called correctly
        assertEq(mockTicketNFT.mintBatchCalled(), true);
        assertEq(mockTicketNFT.lastMintTo(), user1);
        assertEq(mockTicketNFT.lastMintQuantity(), quantity);
        assertEq(mockTicketNFT.lastMintDrawId(), 1);

        // Verify funds transferred to prize pool
        assertEq(mockPrizePool.lastDepositAmount(), cost);
    }

    /**
     * @dev Test buying the maximum allowed tickets (10)
     */
    function testBuyMaxTickets() public {
        // Start a draw
        vm.prank(owner);
        lotteryManager.startNewDraw();

        // Set up ticket IDs
        uint256[] memory ticketIds = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            ticketIds[i] = i + 1;
        }
        mockTicketNFT.setNextTicketIds(ticketIds);

        // Buy max tickets
        uint256 quantity = 10;
        uint256 cost = TICKET_PRICE * quantity;
        vm.deal(user1, cost);

        vm.prank(user1);
        lotteryManager.buyTickets{value: cost}(quantity);

        // Verify tickets were purchased
        assertEq(mockTicketNFT.lastMintQuantity(), quantity);
    }

    /**
     * @dev Test buying tickets with insufficient payment fails
     */
    function testBuyTicketsInsufficientPayment() public {
        // Start a draw
        vm.prank(owner);
        lotteryManager.startNewDraw();

        // Try to buy tickets with insufficient payment
        uint256 quantity = 2;
        uint256 insufficientCost = TICKET_PRICE * quantity - 1; // 1 wei less
        vm.deal(user1, insufficientCost);

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(LotteryManager.InsufficientPayment.selector)
        );
        lotteryManager.buyTickets{value: insufficientCost}(quantity);
    }

    /**
     * @dev Test buying zero tickets fails
     */
    function testCannotBuyZeroTickets() public {
        // Start a draw
        vm.prank(owner);
        lotteryManager.startNewDraw();

        // Try to buy 0 tickets
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(LotteryManager.InvalidTicketCount.selector)
        );
        lotteryManager.buyTickets{value: 0}(0);
    }

    /**
     * @dev Test buying more than maximum allowed tickets fails
     */
    function testCannotBuyTooManyTickets() public {
        // Start a draw
        vm.prank(owner);
        lotteryManager.startNewDraw();

        // Try to buy 11 tickets (max is 10)
        uint256 quantity = 11;
        uint256 cost = TICKET_PRICE * quantity;
        vm.deal(user1, cost);

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(LotteryManager.InvalidTicketCount.selector)
        );
        lotteryManager.buyTickets{value: cost}(quantity);
    }

    /**
     * @dev Test buying tickets when no draw is active fails
     */
    function testCannotBuyTicketsWhenNoDrawActive() public {
        // Try to buy tickets before any draw is started
        vm.deal(user1, TICKET_PRICE);

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(LotteryManager.InvalidPhase.selector, 1)
        ); // Expecting SaleOpen
        lotteryManager.buyTickets{value: TICKET_PRICE}(1);
    }

    /**
     * @dev Test buying tickets after sale period ends fails
     */
    function testCannotBuyTicketsAfterSalePeriod() public {
        // Start a draw
        vm.prank(owner);
        lotteryManager.startNewDraw();

        // Fast forward past sale period
        vm.warp(block.timestamp + SALE_PERIOD + 1);

        // Try to buy tickets
        vm.deal(user1, TICKET_PRICE);

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(LotteryManager.InvalidPhase.selector, 1)
        ); // Expecting SaleOpen
        lotteryManager.buyTickets{value: TICKET_PRICE}(1);
    }

    /**
     * @dev Test triggering a draw
     */
    function testTriggerDraw() public {
        // Start a draw and buy tickets
        _startDrawAndBuyTickets(10);

        // Fast forward past sale period
        vm.warp(block.timestamp + SALE_PERIOD + 1);

        // Set next request ID for mock
        mockRandomness.setNextRequestId(42);

        // Trigger draw
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit DrawTriggered(1, 42);
        lotteryManager.triggerDraw();

        // Verify state changes
        LotteryManager.Draw memory draw = lotteryManager.getCurrentDraw();
        assertEq(uint256(draw.phase), 3); // DrawPhase.Drawing
        assertEq(draw.requestId, 42);
    }

    /**
     * @dev Test triggerDraw can be called by anyone (not just owner)
     */
    function testAnyoneCanTriggerDraw() public {
        // Start a draw and buy tickets
        _startDrawAndBuyTickets(10);

        // Fast forward past sale period
        vm.warp(block.timestamp + SALE_PERIOD + 1);

        // Trigger draw as non-owner
        vm.prank(user2);
        lotteryManager.triggerDraw();

        // Verify draw was triggered
        LotteryManager.Draw memory draw = lotteryManager.getCurrentDraw();
        assertEq(uint256(draw.phase), 3); // DrawPhase.Drawing
    }

    /**
     * @dev Test cannot trigger draw before sale period ends
     */
    function testCannotTriggerDrawBeforeSalePeriodEnds() public {
        // Start a draw and buy tickets
        _startDrawAndBuyTickets(10);

        // Attempt to trigger draw immediately (sale period not over)
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(LotteryManager.InvalidPhase.selector, 2)
        ); // Expecting SaleClosed
        lotteryManager.triggerDraw();
    }

    /**
     * @dev Test cannot trigger draw multiple times
     */
    function testCannotTriggerDrawMultipleTimes() public {
        // Start a draw and buy tickets
        _startDrawAndBuyTickets(10);

        // Fast forward past sale period
        vm.warp(block.timestamp + SALE_PERIOD + 1);

        // Trigger draw first time
        vm.prank(owner);
        lotteryManager.triggerDraw();

        // Try to trigger draw again
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                LotteryManager.InvalidPhase.selector,
                LotteryManager.DrawPhase.SaleClosed
            )
        ); // Expecting SaleOpen
        lotteryManager.triggerDraw();
    }

    /**
     * @dev Test completing a draw with random numbers
     */
    function testCompleteDraw() public {
        // Setup a draw ready for completion
        _setupCompleteDraw(10);

        // Complete draw with random numbers
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 123456789;

        vm.prank(address(mockRandomness));
        vm.expectEmit(true, false, false, false);
        emit DrawCompleted(1, new uint256[](0)); // We don't check exact winning numbers
        lotteryManager.CompleteDraw(1, randomWords);

        // Verify state changes
        LotteryManager.Draw memory draw = lotteryManager.getCurrentDraw();
        assertEq(uint256(draw.phase), 4); // DrawPhase.Completed
        assertEq(draw.winningNumbers.length, 10); // 10 winners

        // Verify prize distribution was called
        assertEq(mockPrizePool.distributePrizesCalled(), true);
        assertEq(mockPrizePool.lastDistributeDrawId(), 1);
        assertEq(mockPrizePool.lastDistributeWinners().length, 10);
    }

    /**
     * @dev Test only the randomness contract can complete a draw
     */
    function testOnlyRandomnessCanCompleteDraw() public {
        // Setup a draw ready for completion
        _setupCompleteDraw(10);

        // Try to complete draw from unauthorized address
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 123456789;

        vm.prank(user1);
        vm.expectRevert("Caller not Randomness");
        lotteryManager.CompleteDraw(1, randomWords);
    }

    /**
     * @dev Test completing a draw that's not in Drawing phase
     */
    function testCannotCompleteDrawInWrongPhase() public {
        // Start a draw but don't trigger it
        _startDrawAndBuyTickets(10);

        // Try to complete draw before it's triggered
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 123456789;

        vm.prank(address(mockRandomness));
        vm.expectRevert("Invalid phase");
        lotteryManager.CompleteDraw(1, randomWords);
    }

    /**
     * @dev Test the _selectWinners function with insufficient tickets
     */
    function testSelectWinnersRequiresMinimumTickets() public {
        // Start a draw with only 5 tickets (less than 10 required)
        _setupCompleteDraw(5);

        // Try to complete draw
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 123456789;

        vm.prank(address(mockRandomness));
        vm.expectRevert("Insufficient tickets");
        lotteryManager.CompleteDraw(1, randomWords);
    }

    /**
     * @dev Test emergency stop functionality
     */
    function testEmergencyStop() public {
        // Start a draw
        vm.prank(owner);
        lotteryManager.startNewDraw();

        // Trigger emergency stop
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit EmergencyStopTriggered(1);
        lotteryManager.emergencyStop();

        // Verify draw is marked as completed
        LotteryManager.Draw memory draw = lotteryManager.getCurrentDraw();
        assertEq(uint256(draw.phase), 4); // DrawPhase.Completed
    }

    /**
     * @dev Test emergency stop fails on completed draw
     */
    function testCannotEmergencyStopCompletedDraw() public {
        // Setup a complete draw
        _setupCompleteDraw(10);

        // Complete draw
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 123456789;
        vm.prank(address(mockRandomness));
        lotteryManager.CompleteDraw(1, randomWords);

        // Try emergency stop on completed draw
        vm.prank(owner);
        vm.expectRevert("Draw already completed");
        lotteryManager.emergencyStop();
    }

    /**
     * @dev Test only owner can call emergency stop
     */
    function testOnlyOwnerCanEmergencyStop() public {
        // Start a draw
        vm.prank(owner);
        lotteryManager.startNewDraw();

        // Try emergency stop as non-owner
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user1
            )
        );
        lotteryManager.emergencyStop();
    }

    /**
     * @dev Test recover funds functionality
     */
    function testRecoverFunds() public {
        // Send some ETH to the contract
        vm.deal(address(lotteryManager), 1 ether);

        // Verify initial balances
        uint256 initialOwnerBalance = owner.balance;
        uint256 contractBalance = address(lotteryManager).balance;
        assertEq(contractBalance, 1 ether);

        // Recover funds
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit FundsRecovered(owner, 1 ether);
        lotteryManager.recoverFunds();

        // Verify balances after recovery
        assertEq(address(lotteryManager).balance, 0);
        assertEq(owner.balance, initialOwnerBalance + 1 ether);
    }

    /**
     * @dev Test only owner can recover funds
     */
    function testOnlyOwnerCanRecoverFunds() public {
        // Send some ETH to the contract
        vm.deal(address(lotteryManager), 1 ether);

        // Try to recover funds as non-owner
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user1
            )
        );
        lotteryManager.recoverFunds();
    }

    /**
     * @dev Test ownership transfer (two-step process)
     */
    function testTwoStepOwnershipTransfer() public {
        // Start ownership transfer from owner to user1
        vm.prank(owner);
        lotteryManager.transferOwnership(user1);

        // Verify ownership hasn't changed yet
        assertEq(lotteryManager.owner(), owner);
        assertEq(lotteryManager.pendingOwner(), user1);

        // Complete ownership transfer
        vm.prank(user1);
        lotteryManager.acceptOwnership();

        // Verify new owner
        assertEq(lotteryManager.owner(), user1);

        // Verify new owner can perform owner-only functions
        vm.prank(user1);
        lotteryManager.startNewDraw();
    }

    /**
     * @dev Test renouncing ownership
     */
    function testRenounceOwnership() public {
        // Renounce ownership
        vm.prank(owner);
        lotteryManager.renounceOwnership();

        // Verify ownership is now zero address
        assertEq(lotteryManager.owner(), address(0));
    }
}
