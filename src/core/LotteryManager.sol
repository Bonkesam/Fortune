// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {ITicketNFT} from "../interfaces/ITicketNFT.sol";
import {IPrizePool} from "../interfaces/IPrizePool.sol";
import {IRandomness} from "../interfaces/IRandomness.sol";

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

    /// @notice Duration between draw finalization and prize claim (seconds)
    uint256 public cooldownPeriod;

    /// @dev Reference to TicketNFT contract
    ITicketNFT public ticketNFT;

    /// @dev Reference to PrizePool contract
    IPrizePool public prizePool;

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

    modifier onlyActiveDraw() {
        if (draws[currentDrawId].phase != DrawPhase.SaleOpen) {
            revert InvalidPhase(DrawPhase.SaleOpen);
        }
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
        uint256 _ticketPrice,
        uint256 _salePeriod,
        uint256 _cooldownPeriod
    ) Ownable2Step() {
        ticketNFT = ITicketNFT(_ticketNFT);
        prizePool = IPrizePool(_prizePool);
        randomness = IRandomness(_randomness);
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
    function buyTickets(
        uint256 quantity
    ) external payable onlyActiveDraw nonReentrant {
        if (quantity == 0 || quantity > 10) revert InvalidTicketCount();
        if (msg.value != ticketPrice * quantity) revert InsufficientPayment();

        Draw storage draw = draws[currentDrawId];
        prizePool.deposit{value: msg.value}();

        // Mint NFT tickets
        uint256[] memory ticketIds = ticketNFT.mintBatch(msg.sender, quantity);

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
        Draw storage draw = draws[currentDrawId];

        if (block.timestamp < draw.endTime)
            revert InvalidPhase(DrawPhase.SaleClosed);
        if (draw.phase != DrawPhase.SaleOpen)
            revert InvalidPhase(DrawPhase.SaleOpen);

        draw.phase = DrawPhase.Drawing;
        uint256 requestId = randomness.requestRandomNumber(currentDrawId);
        draw.requestId = requestId;

        emit DrawTriggered(currentDrawId, requestId);
    }

    /**
     * @notice Complete the draw with VRF result
     * @dev Called by Chainlink VRF callback
     * @param requestId Chainlink VRF request ID
     * @param randomWords Array of random numbers
     */
    function fulfillRandomness(
        uint256 requestId,
        uint256[] memory randomWords
    ) external {
        if (msg.sender != address(randomness)) revert OnlyCoordinator();

        Draw storage draw = draws[currentDrawId];
        if (draw.requestId != requestId) revert RandomnessNotFulfilled();

        draw.winningNumbers = _selectWinners(
            randomWords[0],
            draw.tickets.length
        );
        draw.phase = DrawPhase.Completed;

        prizePool.distributePrizes(currentDrawId, draw.winningNumbers);

        emit DrawCompleted(currentDrawId, draw.winningNumbers);
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
        // Implementation details omitted for brevity
        // Returns 10 winners for demonstration
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
}
