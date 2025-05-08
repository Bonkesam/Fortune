// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {MyToken} from "./MyToken.sol";

/**
 * @title MockAave
 * @dev Mock implementation of Aave LendingPool for testing
 */
contract MockAave {
    address public aToken;
    uint256 public yieldMultiplier = 100; // Default 1:1 (no yield)

    // Set the aToken that will be minted on deposit
    function setAToken(address _aToken) external {
        aToken = _aToken;
    }

    // Set the yield multiplier (100 = 100% or 1:1, 105 = 105% or 1.05:1)
    function setYieldMultiplier(uint256 multiplier) external {
        yieldMultiplier = multiplier;
    }
    function convertToShares(uint256 assets) external view returns (uint256) {
        return (assets * yieldMultiplier) / 100;
    }

    /**
     * @notice Mock implementation of Aave deposit
     * @dev Mints aTokens based on ETH deposited
     */
    // In MockAave.sol
    function deposit(
        address,
        uint256 assets,
        address to,
        uint16
    ) external payable returns (uint256) {
        uint256 shares = this.convertToShares(assets);
        // Mint aTokens to simulate real protocol behavior
        MyToken(aToken).mint(to, shares);
        return shares;
    }

    /**
     * @notice Mock implementation of Aave withdraw
     * @dev Burns aTokens and returns ETH
     */
    function withdraw(
        address, // asset
        uint256 amount
    ) external returns (uint256) {
        // Burn aTokens
        MyToken(aToken).burn(msg.sender, amount);

        // Transfer ETH to recipient
        payable(msg.sender).transfer(amount);

        return amount;
    }

    /**
     * @notice Mock implementation of getReserveData
     */
    function getReserveData(
        address
    )
        external
        pure
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (0, 0, 0, 0, 0, 0, 0, 0);
    }

    // Add fallback to receive ETH
    receive() external payable {}
}
