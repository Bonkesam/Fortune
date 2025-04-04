// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IRandomness
 * @notice Interface for Verifiable Randomness Provider
 * @dev Defines the VRF request/response lifecycle and security boundaries
 */
interface IRandomness {
    // -----------------------------
    // Structures
    // -----------------------------

    /// @notice VRF request metadata
    /// @param drawId Lottery draw ID associated with request
    /// @param fulfilled Whether randomness has been delivered
    /// @param randomWords Array of generated random values
    struct VRFRequest {
        uint256 drawId;
        bool fulfilled;
        uint256[] randomWords;
    }

    // -----------------------------
    // Events
    // -----------------------------

    /// @notice Emitted when new randomness is requested
    /// @param drawId Associated lottery draw ID
    /// @param requestId Chainlink VRF request ID
    event RandomnessRequested(uint256 indexed drawId, uint256 requestId);

    /// @notice Emitted when randomness is delivered
    /// @param drawId Completed lottery draw ID
    /// @param requestId Fulfilled Chainlink request ID
    event RandomnessFulfilled(uint256 indexed drawId, uint256 requestId);

    // -----------------------------
    // Errors
    // -----------------------------

    /// @dev Reverts when unauthorized account tries to request randomness
    error InvalidCaller();

    /// @dev Reverts when invalid request parameters are provided
    error InvalidRequest();

    /// @dev Reverts when contract lacks funds for operation
    error InsufficientFunds();

    // -----------------------------
    // Core Functions
    // -----------------------------

    /**
     * @notice Initiate randomness request for a lottery draw
     * @param drawId ID of the active lottery draw
     * @return requestId Chainlink VRF request identifier
     * @dev Restricted to authorized lottery manager contract
     */
    function requestRandomNumber(
        uint256 drawId
    ) external returns (uint256 requestId);

    // -----------------------------
    // View Functions
    // -----------------------------

    /**
     * @notice Get Chainlink subscription ID
     * @return Current VRF subscription identifier
     */
    function subscriptionId() external view returns (uint64);

    /**
     * @notice Retrieve VRF request details
     * @param requestId Chainlink VRF request ID
     * @return request Full VRF request metadata
     */
    function vrfRequests(
        uint256 requestId
    ) external view returns (VRFRequest memory request);

    /**
     * @notice Get associated request ID for a draw
     * @param drawId Lottery draw ID
     * @return requestId Corresponding VRF request ID
     */
    function drawToRequestId(
        uint256 drawId
    ) external view returns (uint256 requestId);

    // -----------------------------
    // Configuration Functions
    // -----------------------------

    /**
     * @notice Update Chainlink VRF subscription ID
     * @param newSubscriptionId New subscription identifier
     * @dev Restricted to contract owner
     */
    function updateSubscriptionId(uint64 newSubscriptionId) external;

    /**
     * @notice Update callback gas limit for VRF responses
     * @param newGasLimit New gas limit value
     * @dev Restricted to contract owner
     */
    function setCallbackGasLimit(uint32 newGasLimit) external;
}
