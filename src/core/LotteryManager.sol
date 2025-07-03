// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {ITicketNFT} from "../interfaces/ITicketNFT.sol";
import {IPrizePool} from "../interfaces/IPrizePool.sol";
import {IFORT} from "../interfaces/IFORT.sol";
import {IRandomness} from "../interfaces/IRandomness.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title Lottery Manager
 * @dev Central coordination contract for managing lottery draws, ticket sales, and prize distribution.
 * Features:
 * - Draw lifecycle management
 * - Chainlink VRF integration for randomness
 * - Integration with TicketNFT and PrizePool contracts
 * - Time-based draw phases with safety checks
 */
contract LotteryManager is Ownable2Step, ReentrancyGuard {
    using Address for address payable;

    // -----------------------------
    // State Variables
    // -----------------------------

    /// @notice Current active draw ID
    uint256 public currentDrawId;

    /// @notice Ticket price in ETH
    uint256 public ticketPrice;

    /// @notice Duration of ticket sales period (seconds)
    uint256 public salePeriod;

    /// @notice Duration bAetween draw finalization and prize claim (seconds)
    uint256 public cooldownPeriod;

    /// @dev Reference to TicketNFT contract
    ITicketNFT public ticketNFT;

    /// @dev Reference to PrizePool contract
    IPrizePool public prizePool;

    /// @dev Reference to FORT contract
    IFORT public fortToken;

    /// @dev Reference to Randomness contract
    IRandomness public randomness;

    /// @dev Draw state tracking
    mapping(uint256 => Draw) internal draws;

    // -----------------------------
    // Structs & Enums
    // -----------------------------

    enum DrawPhase {
        NotStarted,
        SaleOpen,
        SaleClosed,
        Drawing,
        Completed
    }

    struct Draw {
        uint256 drawId;
        uint256 startTime;
        uint256 endTime;
        uint256[] tickets;
        address[] participants;
        DrawPhase phase;
        uint256 requestId;
        uint256[] winningNumbers;
    }

    // -----------------------------
    // Events
    // -----------------------------

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

    // -----------------------------
    // Errors
    // -----------------------------

    error InvalidPhase(DrawPhase expected);
    error InvalidTicketCount();
    error InsufficientPayment();
    error RandomnessNotFulfilled();
    error DrawNotCompleted();
    error OnlyCoordinator();

    // -----------------------------
    // Modifiers
    // -----------------------------

    modifier onlyRandomness() {
        require(msg.sender == address(randomness), "Caller not Randomness");
        _;
    }

    modifier onlyCompletedDraw(uint256 drawId) {
        if (draws[drawId].phase != DrawPhase.Completed) {
            revert DrawNotCompleted();
        }
        _;
    }

    // -----------------------------
    // Constructor
    // -----------------------------

    constructor(
        address _ticketNFT,
        address _prizePool,
        address _randomness,
        address _fortToken,
        uint256 _ticketPrice,
        uint256 _salePeriod,
        uint256 _cooldownPeriod,
        address initialOwner
    ) Ownable(initialOwner) {
        ticketNFT = ITicketNFT(_ticketNFT);
        prizePool = IPrizePool(_prizePool);
        randomness = IRandomness(_randomness);
        fortToken = IFORT(_fortToken);
        ticketPrice = _ticketPrice;
        salePeriod = _salePeriod;
        cooldownPeriod = _cooldownPeriod;
    }

    // -----------------------------
    // External Functions
    // -----------------------------

    /**
     * @notice Start a new lottery draw
     * @dev Can only be called by owner when previous draw is completed
     */
    function startNewDraw() external onlyOwner {
        if (
            currentDrawId > 0 &&
            draws[currentDrawId].phase != DrawPhase.Completed
        ) {
            revert InvalidPhase(DrawPhase.Completed);
        }

        currentDrawId++;
        Draw storage newDraw = draws[currentDrawId];
        newDraw.drawId = currentDrawId;
        newDraw.startTime = block.timestamp;
        newDraw.endTime = block.timestamp + salePeriod;
        newDraw.phase = DrawPhase.SaleOpen;

        emit DrawStarted(currentDrawId, block.timestamp);
    }

    /**
     * @notice Purchase lottery tickets
     * @param quantity Number of tickets to purchase
     * @dev Payments are forwarded to PrizePool
     */
    function buyTickets(uint256 quantity) external payable nonReentrant {
        // Check that there is an active draw with sales open
        if (
            currentDrawId == 0 ||
            draws[currentDrawId].phase != DrawPhase.SaleOpen
        ) {
            revert InvalidPhase(DrawPhase.SaleOpen);
        }

        // Check that the sale period hasn't ended
        Draw storage draw = draws[currentDrawId];
        if (block.timestamp > draw.endTime) {
            draw.phase = DrawPhase.SaleClosed;
            revert InvalidPhase(DrawPhase.SaleOpen);
        }

        // Validate ticket purchase
        if (quantity == 0 || quantity > 10) revert InvalidTicketCount();
        if (msg.value != ticketPrice * quantity) revert InsufficientPayment();

        // Forward payment to prize pool
        prizePool.deposit{value: msg.value}(msg.value);

        // Mint NFT tickets
        uint256[] memory ticketIds = ticketNFT.mintBatch(
            msg.sender,
            quantity,
            currentDrawId
        );
        fortToken.recordBettor(msg.sender);

        // Record ticket IDs for this draw
        for (uint256 i = 0; i < quantity; i++) {
            draw.tickets.push(ticketIds[i]);
        }

        emit TicketsPurchased(currentDrawId, msg.sender, quantity);
    }

    /**
     * @notice Trigger the draw process
     * @dev Can only be called after sale period ends
     */
    function triggerDraw() external nonReentrant {
        require(currentDrawId > 0, "No active draw");
        Draw storage draw = draws[currentDrawId];

        // Check if sales period has ended
        if (block.timestamp < draw.endTime) {
            revert InvalidPhase(DrawPhase.SaleClosed);
        }

        // Update the phase if it's still in SaleOpen but time has passed
        if (
            draw.phase == DrawPhase.SaleOpen && block.timestamp >= draw.endTime
        ) {
            draw.phase = DrawPhase.SaleClosed;
        }

        // Ensure we're in the correct phase to trigger a draw
        if (draw.phase != DrawPhase.SaleClosed) {
            revert InvalidPhase(DrawPhase.SaleClosed);
        }

        // Request randomness
        draw.phase = DrawPhase.Drawing;
        uint256 requestId = randomness.requestRandomNumber(currentDrawId);
        draw.requestId = requestId;

        emit DrawTriggered(currentDrawId, requestId);
    }

    /**
     * @notice Complete the draw with VRF result
     * @dev Called by Chainlink VRF callback
     * @param drawId Chainlink VRF request ID
     * @param randomWords Array of random numbers
     */
    function CompleteDraw(
        uint256 drawId,
        uint256[] memory randomWords
    ) external nonReentrant onlyRandomness {
        Draw storage draw = draws[drawId];

        require(draw.phase == DrawPhase.Drawing, "Invalid phase");
        require(draw.drawId == drawId, "ID mismatch"); // Verify stored ID matches
        require(randomWords.length > 0, "No random words provided");

        // Check if we have enough tickets to select winners
        uint256 totalTickets = draw.tickets.length;
        if (totalTickets < 10) {
            revert("Insufficient tickets");
        }

        draw.winningNumbers = _selectWinners(randomWords[0], totalTickets);

        // Convert indices to ticket IDs and get owners
        address[] memory winners = new address[](draw.winningNumbers.length);
        for (uint256 i = 0; i < draw.winningNumbers.length; i++) {
            uint256 ticketIndex = draw.winningNumbers[i];
            uint256 ticketId = draw.tickets[ticketIndex];
            winners[i] = ticketNFT.ownerOf(ticketId);

            // Set first ticket as golden
            if (i == 0) {
                ticketNFT.setGoldenTicket(ticketId);
            } else {
                ticketNFT.setSilverTicket(ticketId);
            }
        }

        prizePool.distributePrizes(drawId, winners);

        draw.phase = DrawPhase.Completed;

        emit DrawCompleted(drawId, draw.winningNumbers);
    }

    // -----------------------------
    // View Functions
    // -----------------------------

    /**
     * @notice Get current draw details
     * @return Draw struct for current active draw
     */
    function getCurrentDraw() external view returns (Draw memory) {
        return draws[currentDrawId];
    }

    // -----------------------------
    // Internal Functions
    // -----------------------------

    /**
     * @dev Select winners using Fisher-Yates shuffle algorithm
     * @param randomnessSeed Seed value for shuffle
     * @param totalTickets Total tickets in draw
     * @return winners Array of winning ticket indices
     */
    function _selectWinners(
        uint256 randomnessSeed,
        uint256 totalTickets
    ) internal pure returns (uint256[] memory winners) {
        require(totalTickets >= 10, "Insufficient tickets");
        winners = new uint256[](10);
        bytes32 rngHash = keccak256(abi.encode(randomnessSeed));

        // Initialize with first 10 tickets as base case
        for (uint256 i = 0; i < 10; i++) {
            winners[i] = i;
        }

        // Generate 10 random indices using hash chain
        for (uint256 i = 0; i < 10; i++) {
            // Get 25 bits of randomness per iteration (250 bits total)
            uint256 random = uint256(rngHash) >> (i * 25);
            uint256 j = i + (random % (totalTickets - i));

            // Fisher-Yates swap logic
            if (j < 10) {
                // Swap positions within winners array
                (winners[i], winners[j]) = (winners[j], winners[i]);
            } else {
                // Replace with new unique index
                winners[i] = j;
            }

            // Generate new hash if needed
            if (i % 10 == 9) rngHash = keccak256(abi.encode(rngHash));
        }

        // Final uniqueness check and sort
        _validateAndSort(winners, totalTickets);
        return winners;
    }

    function _validateAndSort(
        uint256[] memory winners,
        uint256 totalTickets
    ) private pure {
        // Implement sorting and uniqueness checks
        for (uint256 i = 0; i < winners.length; i++) {
            require(winners[i] < totalTickets, "Invalid winner index");

            // Check for duplicates
            for (uint256 j = i + 1; j < winners.length; j++) {
                require(winners[i] != winners[j], "Duplicate winner");
            }
        }

        // Insertion sort for deterministic output
        for (uint256 i = 1; i < winners.length; i++) {
            uint256 key = winners[i];
            int256 j = int256(i) - 1;
            while (j >= 0 && winners[uint256(j)] > key) {
                winners[uint256(j + 1)] = winners[uint256(j)];
                j--;
            }
            winners[uint256(j + 1)] = key;
        }
    }

    // -----------------------------
    // Emergency Functions
    // -----------------------------

    /**
     * @notice Emergency stop current draw
     * @dev Only callable by owner in case of critical issues
     */
    function emergencyStop() external onlyOwner {
        Draw storage draw = draws[currentDrawId];
        require(draw.phase != DrawPhase.Completed, "Draw already completed");

        draw.phase = DrawPhase.Completed;
        emit EmergencyStopTriggered(currentDrawId);
    }

    /**
     * @notice Recover stuck funds (only ETH)
     * @dev Safety measure for accidental transfers
     */
    function recoverFunds() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        payable(owner()).sendValue(balance);
        emit FundsRecovered(owner(), balance);
    }
    function setPrizePool(address _prizePool) external onlyOwner {
        require(address(prizePool) == address(0), "PrizePool already set");
        prizePool = IPrizePool(_prizePool);
    }
}
