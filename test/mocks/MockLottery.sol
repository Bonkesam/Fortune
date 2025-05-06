// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

contract MockLottery is Ownable {
    constructor() Ownable(msg.sender) {} // Initialize Ownable

    uint256 public ticketPrice;
    uint256 public protocolFee;
    address public yieldStrategy;
    address public yieldToken;
    bool public yieldEnabled;

    function setTicketPrice(uint256 price) external onlyOwner {
        ticketPrice = price;
    }

    function setProtocolFee(uint256 fee) external onlyOwner {
        protocolFee = fee;
    }

    function setYieldProtocol(
        address strategy,
        address token,
        bool enabled
    ) external onlyOwner {
        yieldStrategy = strategy;
        yieldToken = token;
        yieldEnabled = enabled;
    }
}
