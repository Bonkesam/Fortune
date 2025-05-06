// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IDAO
 * @notice Governance interface for parameter updates
 * @dev Used across LotteryManager and PrizePool
 */
interface IDAO {
    struct Proposal {
        address target;
        bytes data;
        uint256 value;
        uint256 deadline;
    }

    /**
     * @notice Submit governance proposal
     * @param proposal Proposal data structure
     */
    function propose(Proposal calldata proposal) external;

    /**
     * @notice Execute approved proposal
     * @param proposalId ID of passed proposal
     */
    function execute(uint256 proposalId) external;

    /**
     * @notice Check proposal approval status
     * @param proposalId ID to check
     * @return bool True if approved
     */
    function isApproved(uint256 proposalId) external view returns (bool);
}
