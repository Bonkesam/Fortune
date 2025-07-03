// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VRFCoordinatorV2_5} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFCoordinatorV2_5.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ILotteryManager} from "../interfaces/ILotteryManager.sol";

/**
 * @title Verifiable Randomness Provider
 * @notice Secure Chainlink VRF v2.5 integration for provably fair random number generation
 * @dev Implements VRF v2.5 with callback validation and request tracking
 */
contract Randomness is VRFConsumerBaseV2Plus, Ownable2Step, ReentrancyGuard {
    // -----------------------------
    // Chainlink VRF Configuration
    // -----------------------------
    VRFCoordinatorV2_5 public immutable VRF_COORDINATOR;
    bytes32 public immutable KEY_HASH;
    uint256 public subscriptionId; // ← CORRECT: uint256 for v2.5
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
    event SubscriptionUpdated(uint256 newSubscriptionId);
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
        uint256 _subscriptionId, // ← CORRECT: uint256 for v2.5
        address _lotteryManager,
        address initialOwner
    ) VRFConsumerBaseV2Plus(vrfCoordinator) Ownable(initialOwner) {
        if (vrfCoordinator == address(0)) revert InvalidCoordinator();

        VRF_COORDINATOR = VRFCoordinatorV2_5(vrfCoordinator);
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

        // Create VRF request using v2.5 format
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: KEY_HASH,
                subId: subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: 1,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({
                        nativePayment: false // Use LINK for payment
                    })
                )
            });

        // Request randomness from Chainlink
        requestId = VRF_COORDINATOR.requestRandomWords(request);

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
        uint256[] calldata randomWords
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
    function updateSubscriptionId(
        uint256 newSubscriptionId
    ) external onlyOwner {
        subscriptionId = newSubscriptionId;
        emit SubscriptionUpdated(newSubscriptionId);
    }

    function setLotteryManager(address _manager) external onlyOwner {
        if (subscriptionId == 0) {
            // Skip if subscription not set yet
            return;
        }

        // Remove current contract as consumer
        VRF_COORDINATOR.removeConsumer(subscriptionId, address(this));

        // Add new manager as consumer
        VRF_COORDINATOR.addConsumer(subscriptionId, _manager);
    }

    // Set subscription ID for V2.5
    function setSubscriptionId(uint256 _subId) external onlyOwner {
        require(subscriptionId == 0, "Subscription already set");
        subscriptionId = _subId;
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
