// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IChainlinkVRF
 * @notice Interface for Chainlink VRF v2
 * @dev Used in Randomness.sol
 */
interface IChainlinkVRF {
    /**
     * @notice Request randomness
     * @param keyHash Key hash for oracle job
     * @param subId Subscription ID
     * @param minConfs Minimum confirmations
     * @param callbackGasLimit Gas limit for callback
     * @param numWords Number of random values
     * @return requestId Generated request ID
     */
    function requestRandomWords(
        bytes32 keyHash,
        uint64 subId,
        uint16 minConfs,
        uint32 callbackGasLimit,
        uint32 numWords
    ) external returns (uint256 requestId);

    /**
     * @notice Check request status
     * @param requestId ID to check
     * @return fulfilled True if request completed
     * @return randomWords Array of random numbers
     */
    function getRequestStatus(
        uint256 requestId
    ) external view returns (bool fulfilled, uint256[] memory randomWords);
}
