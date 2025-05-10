// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../../src/interfaces/IRandomness.sol";

/**
 * @title MockRandomness
 * @dev Mock implementation of Randomness for testing purposes
 * Implements the IRandomness interface with test-friendly features
 */
contract MockRandomness is IRandomness, Ownable {
    // State variables
    address public lotteryManager;
    uint64 private _subscriptionId = 1000;
    uint32 private _callbackGasLimit = 200000;
    uint256 private nextRequestId;

    // Mappings for request tracking
    mapping(uint256 => VRFRequest) private _vrfRequests;
    mapping(uint256 => uint256) private _drawToRequestId;

    constructor() Ownable(msg.sender) {}

    // Setup function for tests
    function setLotteryManager(address _lotteryManager) external onlyOwner {
        lotteryManager = _lotteryManager;
    }

    // Setup function for tests
    function setNextRequestId(uint256 _nextRequestId) external {
        nextRequestId = _nextRequestId;
    }

    /**
     * @notice Request random number implementation for testing
     * @param drawId The draw ID to request randomness for
     * @return requestId The mocked request ID
     */
    function requestRandomNumber(
        uint256 drawId
    ) external override returns (uint256) {
        // Only the lottery manager can request randomness
        if (msg.sender != lotteryManager) {
            revert InvalidCaller();
        }

        uint256 requestId = nextRequestId;

        // Create an empty request
        _vrfRequests[requestId] = VRFRequest({
            drawId: drawId,
            fulfilled: false,
            randomWords: new uint256[](0)
        });

        // Map draw to request ID
        _drawToRequestId[drawId] = requestId;

        // Emit event
        emit RandomnessRequested(drawId, requestId);

        return requestId;
    }

    /**
     * @notice Fulfill randomness (test helper function)
     * @param requestId The ID of the request to fulfill
     * @param randomWords The random values to use
     */
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) external {
        VRFRequest storage request = _vrfRequests[requestId];
        require(!request.fulfilled, "Request already fulfilled");

        // Mark as fulfilled and set random words
        request.fulfilled = true;
        request.randomWords = randomWords;

        // Call the lottery manager contract
        // Cast to dynamic type to access CompleteDraw function
        (bool success, ) = lotteryManager.call(
            abi.encodeWithSignature(
                "CompleteDraw(uint256,uint256[])",
                request.drawId,
                randomWords
            )
        );
        require(success, "Callback failed");

        // Emit fulfillment event
        emit RandomnessFulfilled(request.drawId, requestId);
    }

    /**
     * @notice Get subscription ID (view function)
     * @return The current subscription ID
     */
    function subscriptionId() external view override returns (uint64) {
        return _subscriptionId;
    }

    /**
     * @notice Update subscription ID
     * @param newSubscriptionId The new subscription ID to set
     */
    function updateSubscriptionId(
        uint64 newSubscriptionId
    ) external override onlyOwner {
        _subscriptionId = newSubscriptionId;
    }

    /**
     * @notice Update callback gas limit
     * @param newGasLimit The new gas limit to set
     */
    function setCallbackGasLimit(
        uint32 newGasLimit
    ) external override onlyOwner {
        _callbackGasLimit = newGasLimit;
    }

    /**
     * @notice Retrieve VRF request details
     * @param requestId Chainlink VRF request ID
     * @return request Full VRF request metadata
     */
    function vrfRequests(
        uint256 requestId
    ) external view override returns (VRFRequest memory) {
        return _vrfRequests[requestId];
    }

    /**
     * @notice Get associated request ID for a draw
     * @param drawId Lottery draw ID
     * @return requestId Corresponding VRF request ID
     */
    function drawToRequestId(
        uint256 drawId
    ) external view override returns (uint256) {
        return _drawToRequestId[drawId];
    }
}
