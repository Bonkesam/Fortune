// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";

/**
 * @title MockVRFCoordinatorV2
 * @notice Mock implementation of Chainlink's VRF Coordinator for testing
 * @dev Simulates requestRandomWords and fulfillRandomWords behavior
 */
contract MockVRFCoordinatorV2 is VRFCoordinatorV2Interface {
    uint256 private nextRequestId;
    mapping(uint256 => address) public s_consumers; // Renamed to avoid shadowing
    mapping(uint256 => uint256[]) public savedRandomWords;

    // Event to track request details
    event RandomWordsRequested(
        bytes32 keyHash,
        uint64 subId,
        uint16 requestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords,
        address sender
    );

    /**
     * @notice Set the next request ID to be used
     * @param requestId The request ID to use for the next request
     */
    function setNextRequestId(uint256 requestId) external {
        nextRequestId = requestId;
    }

    /**
     * @notice Request random words from VRF
     * @dev Mock implementation that returns a fixed requestId
     * @param keyHash The hash of the VRF key
     * @param subId Subscription ID
     * @param requestConfirmations Number of confirmations to wait
     * @param callbackGasLimit Gas limit for the callback
     * @param numWords Number of random words to generate
     * @return requestId ID of the random request
     */
    function requestRandomWords(
        bytes32 keyHash,
        uint64 subId,
        uint16 requestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords
    ) external override returns (uint256) {
        // Store the consumer address that made this request
        s_consumers[nextRequestId] = msg.sender;

        emit RandomWordsRequested(
            keyHash,
            subId,
            requestConfirmations,
            callbackGasLimit,
            numWords,
            msg.sender
        );

        return nextRequestId++;
    }

    /**
     * @notice Triggers the callback function on a VRF consumer contract
     * @param requestId ID of the request
     * @param consumer Address of the consumer contract
     * @param randomWords Array of random words to be returned
     */
    function fulfillRandomWordsWithCallback(
        uint256 requestId,
        address consumer,
        uint256[] memory randomWords
    ) external {
        // Only fulfill if this is the registered consumer for this requestId
        require(
            s_consumers[requestId] == consumer,
            "Consumer does not match registered"
        );

        savedRandomWords[requestId] = randomWords;

        VRFConsumerBaseV2(consumer).rawFulfillRandomWords(
            requestId,
            randomWords
        );
    }

    /**
     * @notice Directly call rawFulfillRandomWords on a consumer contract
     * @param consumerContract Address of the consumer contract
     * @param requestId ID of the request
     * @param randomWords Array of random words to be returned
     */
    function callRawFulfillRandomWords(
        address consumerContract,
        uint256 requestId,
        uint256[] memory randomWords
    ) external {
        // This should fail if the caller is not the actual VRF coordinator
        // We need to ensure this actually reverts for the test
        require(
            msg.sender == s_consumers[requestId] || msg.sender == address(this),
            "only coordinator can fulfill"
        );

        VRFConsumerBaseV2(consumerContract).rawFulfillRandomWords(
            requestId,
            randomWords
        );
    }

    // The following functions are not used in our tests, but are required by the interface

    function getRequestConfig()
        external
        pure
        override
        returns (uint16, uint32, bytes32[] memory)
    {
        bytes32[] memory keyhashes = new bytes32[](0);
        return (3, 1000000, keyhashes);
    }

    function createSubscription() external pure override returns (uint64) {
        return 1;
    }

    function getSubscription(
        uint64
    )
        external
        pure
        override
        returns (
            uint96 balance,
            uint64 reqCount,
            address owner,
            address[] memory consumerList // Renamed to avoid shadowing
        )
    {
        address[] memory cons = new address[](0);
        return (0, 0, address(0), cons);
    }

    function requestSubscriptionOwnerTransfer(
        uint64,
        address
    ) external pure override {
        // Not implemented
    }

    function acceptSubscriptionOwnerTransfer(uint64) external pure override {
        // Not implemented
    }

    function addConsumer(uint64, address) external pure override {
        // Not implemented
    }

    function removeConsumer(uint64, address) external pure override {
        // Not implemented
    }

    function cancelSubscription(uint64, address) external pure override {
        // Not implemented
    }

    function pendingRequestExists(
        uint64
    ) external pure override returns (bool) {
        return false;
    }
}
