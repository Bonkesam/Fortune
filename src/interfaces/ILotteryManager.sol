// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title ILotteryManager
 * @notice Interface for the central lottery management contract
 * @dev Defines the external API and events for draw management
 */
interface ILotteryManager {
    // -----------------------------
    // Events
    // -----------------------------

    /// @notice Emitted when a new draw is started
    /// @param drawId The ID of the new draw
    /// @param startTime Timestamp when the draw started
    event DrawStarted(uint256 indexed drawId, uint256 startTime);

    /// @notice Emitted when tickets are purchased
    /// @param drawId Current active draw ID
    /// @param buyer Address that purchased tickets
    /// @param quantity Number of tickets purchased
    event TicketsPurchased(
        uint256 indexed drawId,
        address indexed buyer,
        uint256 quantity
    );

    /// @notice Emitted when a draw is completed
    /// @param drawId ID of the completed draw
    /// @param winningNumbers Array of winning ticket IDs
    event DrawCompleted(uint256 indexed drawId, uint256[] winningNumbers);

    // -----------------------------
    // Errors
    // -----------------------------

    /// @dev Reverts when incorrect payment is sent
    error InsufficientPayment();

    /// @dev Reverts when invalid phase is detected
    error InvalidPhase(uint8 expected);

    // -----------------------------
    // Core Functions
    // -----------------------------

    /**
     * @notice Start a new lottery draw
     * @dev Can only be called by contract owner
     */
    function startNewDraw() external;

    /**
     * @notice Purchase lottery tickets
     * @param quantity Number of tickets to purchase
     * @dev Value must equal ticketPrice * quantity
     */
    function buyTickets(uint256 quantity) external payable;

    /**
     * @notice Trigger the draw process
     * @dev Can only be called after sale period ends
     */
    function triggerDraw() external;

    // -----------------------------
    // View Functions
    // -----------------------------

    /**
     * @notice Get current draw details
     * @return drawId Current active draw ID
     * @return startTime Draw start timestamp
     * @return endTime Draw end timestamp
     * @return phase Current draw phase
     */
    function getCurrentDraw()
        external
        view
        returns (
            uint256 drawId,
            uint256 startTime,
            uint256 endTime,
            uint8 phase
        );

    /**
     * @notice Get current ticket price
     * @return priceInWei Current ticket price in wei
     */
    function ticketPrice() external view returns (uint256);

    /**
     * @notice Get the owner of a specific ticket
     * @param ticketId The ID of the ticket
     * @return The address of the ticket owner
     */
    function getTicketOwner(uint256 ticketId) external view returns (address);

    function completeDraw(
        uint256 drawId,
        uint256[] calldata randomWords
    ) external;
}
