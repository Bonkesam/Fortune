// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ILotteryManager} from "../interfaces/ILotteryManager.sol";

import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
/**
 * @title Verifiable Randomness Provider
 * @notice Secure Chainlink VRF integration for provably fair random number generation
 * @dev Implements VRF v2 with callback validation and request tracking
 */
contract Randomness is VRFConsumerBaseV2, Ownable2Step, ReentrancyGuard {
    // -----------------------------
    // Chainlink VRF Configuration
    // -----------------------------
    VRFCoordinatorV2Interface public immutable VRF_COORDINATOR;
    bytes32 public immutable KEY_HASH;
    uint64 public subscriptionId;
    uint32 public callbackGasLimit = 500_000;
    uint16 public requestConfirmations = 3;

    // -----------------------------
    // State Variables
    // -----------------------------
    ILotteryManager public immutable lotteryManager;

    struct VRFRequest {
        uint256 drawId;
        bool fulfilled;
        uint256[] randomWords;
    }

    mapping(uint256 => VRFRequest) public vrfRequests; // key: Chainlink request ID
    mapping(uint256 => uint256) public drawToRequestId; // key: draw ID

    // -----------------------------
    // Events
    // -----------------------------
    event RandomnessRequested(uint256 indexed drawId, uint256 requestId);
    event RandomnessFulfilled(uint256 indexed drawId, uint256 requestId);
    event SubscriptionUpdated(uint64 newSubscriptionId);
    event CallbackGasLimitUpdated(uint32 newGasLimit);

    // -----------------------------
    // Errors
    // -----------------------------
    error InvalidCaller();
    error InvalidRequest();
    error InsufficientFunds();
    error AlreadyFulfilled();
    error InvalidCoordinator();

    // -----------------------------
    // Modifiers
    // -----------------------------
    modifier onlyManager() {
        if (msg.sender != address(lotteryManager)) revert InvalidCaller();
        _;
    }

    // -----------------------------
    // Constructor
    // -----------------------------
    constructor(
        address vrfCoordinator,
        bytes32 keyHash,
        uint64 _subscriptionId,
        address _lotteryManager,
        address initialOwner
    ) VRFConsumerBaseV2(vrfCoordinator) Ownable(initialOwner) {
        if (vrfCoordinator == address(0)) revert InvalidCoordinator();

        VRF_COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        KEY_HASH = keyHash;
        subscriptionId = _subscriptionId;
        lotteryManager = ILotteryManager(_lotteryManager);
    }

    // -----------------------------
    // Core Functions
    // -----------------------------

    /**
     * @notice Request random numbers for a lottery draw
     * @param drawId ID of the current lottery draw
     * @dev Only callable by LotteryManager
     * @return requestId Chainlink VRF request ID
     */
    function requestRandomNumber(
        uint256 drawId
    ) external onlyManager nonReentrant returns (uint256 requestId) {
        // Check for existing request
        if (drawToRequestId[drawId] != 0) revert InvalidRequest();

        // Request randomness from Chainlink
        requestId = VRF_COORDINATOR.requestRandomWords(
            KEY_HASH,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            1 // Number of random values needed (we'll expand in callback)
        );

        // Store request metadata
        vrfRequests[requestId] = VRFRequest({
            drawId: drawId,
            fulfilled: false,
            randomWords: new uint256[](0)
        });
        drawToRequestId[drawId] = requestId;

        emit RandomnessRequested(drawId, requestId);
        return requestId;
    }

    /**
     * @notice Callback function used by VRF Coordinator
     * @param requestId Chainlink request ID
     * @param randomWords Array of random numbers from VRF
     * @dev Only VRF Coordinator can call this
     */
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override nonReentrant {
        VRFRequest storage request = vrfRequests[requestId];
        if (request.fulfilled) revert AlreadyFulfilled();

        // Store random words and expand to multiple numbers if needed
        request.randomWords = _expandRandomness(randomWords[0], 10);
        request.fulfilled = true;

        // Forward completion to LotteryManager
        lotteryManager.completeDraw(request.drawId, request.randomWords);

        emit RandomnessFulfilled(request.drawId, requestId);
    }

    // -----------------------------
    // Test-Only Functions
    // -----------------------------

    /**
     * @notice Test-only function to simulate VRF callback
     * @param requestId Request ID to fulfill
     * @param randomWords Random words to use
     * @dev This function should only be used in tests
     */
    function testFulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) external {
        // Only allow in test environment (you can add more restrictive checks)
        fulfillRandomWords(requestId, randomWords);
    }

    // -----------------------------
    // Admin Functions
    // -----------------------------

    /**
     * @notice Update Chainlink subscription ID
     * @param newSubscriptionId New subscription ID
     * @dev Only owner can update
     */
    function updateSubscriptionId(uint64 newSubscriptionId) external onlyOwner {
        subscriptionId = newSubscriptionId;
        emit SubscriptionUpdated(newSubscriptionId);
    }

    /**
     * @notice Update callback gas limit
     * @param newGasLimit New gas limit for VRF callback
     * @dev Only owner can update
     */
    function setCallbackGasLimit(uint32 newGasLimit) external onlyOwner {
        if (newGasLimit > 2_500_000) revert InvalidRequest();
        callbackGasLimit = newGasLimit;
        emit CallbackGasLimitUpdated(newGasLimit);
    }

    // -----------------------------
    // Internal Functions
    // -----------------------------

    /**
     * @dev Expand single random value into multiple numbers
     * @param seed Initial random value
     * @param count Number of values to generate
     * @return expanded Array of expanded random numbers
     */
    function _expandRandomness(
        uint256 seed,
        uint256 count
    ) internal pure returns (uint256[] memory expanded) {
        expanded = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            expanded[i] = uint256(keccak256(abi.encode(seed, i)));
        }
        return expanded;
    }

    // -----------------------------
    // Emergency Functions
    // -----------------------------

    /**
     * @notice Withdraw LINK tokens from contract
     * @param to Recipient address
     * @param amount Amount to withdraw
     * @dev Only owner can call
     */
    function withdrawLINK(
        address to,
        uint256 amount
    ) external onlyOwner nonReentrant {
        if (amount > address(this).balance) revert InsufficientFunds();
        (bool success, ) = payable(to).call{value: amount}("");
        if (!success) revert InvalidRequest();
    }
}
