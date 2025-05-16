// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IAave
 * @notice Minimal interface for Aave lending pool interactions
 * @dev Used in PrizePool for yield generation
 */
interface IAave {
    /**
     * @notice Deposit assets into Aave
     * @param asset Asset to deposit (address(0) for ETH)
     * @param amount Amount to deposit
     * @param onBehalfOf Receiver of aTokens
     * @param referralCode Referral code (unused)
     */
    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external payable;

    /**
     * @notice Withdraw assets from Aave
     * @param asset Asset to withdraw
     * @param amount Amount to withdraw
     * @return Withdrawn amount
     */
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);

    /**
     * @notice Get reserve data for asset
     * @param asset Asset address
     * @return aTokenAddress Corresponding aToken address
     */
    function getReserveData(
        address asset
    ) external view returns (address aTokenAddress);
}
