// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ILotteryManager} from "../../src/interfaces/ILotteryManager.sol";

/**
 * @title MockLotteryManager
 * @dev Mock implementation of ILotteryManager for testing
 */
contract MockLotteryManager {
    address public prizePool;
    uint256 public ticketPrice = 1 ether;
    uint256 public protocolFee = 200; // 2%
    uint256 public firstPrize = 7000; // 70%
    uint256 public secondPrize = 2000; // 20%
    uint256 public thirdPrize = 1000; // 10%

    // We can set the prize pool address for tests that need it
    function setPrizePool(address _prizePool) external {
        prizePool = _prizePool;
    }

    // Add governance-controlled functions
    function setTicketPrice(uint256 _ticketPrice) external {
        ticketPrice = _ticketPrice;
    }

    function setProtocolFee(uint256 _protocolFee) external {
        protocolFee = _protocolFee;
    }

    function updatePrizeDistribution(
        uint256 _firstPrize,
        uint256 _secondPrize,
        uint256 _thirdPrize
    ) external {
        firstPrize = _firstPrize;
        secondPrize = _secondPrize;
        thirdPrize = _thirdPrize;
    }

    function prizeDistribution()
        external
        view
        returns (uint256, uint256, uint256)
    {
        return (firstPrize, secondPrize, thirdPrize);
    }

    // Implement required interface methods without override keyword
    // Since we're not implementing the full interface

    function createDraw(
        uint256,
        uint256,
        uint256
    ) external pure returns (uint256) {
        return 1; // Always return draw ID 1 for simplicity
    }

    function startNewDraw() external pure {
        // Do nothing for mock
    }

    function buyTickets(
        uint256,
        uint256
    ) external payable returns (uint256[] memory) {
        // Return some dummy ticket IDs
        uint256[] memory ticketIds = new uint256[](1);
        ticketIds[0] = 1;
        return ticketIds;
    }

    function buyTickets(uint256) external payable {
        // Do nothing for mock
    }

    function triggerDraw() external pure {
        // Do nothing for mock
    }

    function getCurrentDraw()
        external
        view
        returns (uint256, uint256, uint256, uint256)
    {
        return (1, block.timestamp, block.timestamp + 1 days, 10);
    }

    function getTicketOwner(uint256) external view returns (address) {
        return address(this);
    }

    function completeDraw(uint256) external pure returns (address[] memory) {
        // Return some dummy winners
        address[] memory winners = new address[](1);
        winners[0] = address(0x123);
        return winners;
    }

    function getActiveDrawDetails()
        external
        view
        returns (uint256, uint256, uint256, uint256)
    {
        return (1, block.timestamp, block.timestamp + 1 days, 1 ether);
    }

    // Add fallback to receive ETH
    receive() external payable {}
}
