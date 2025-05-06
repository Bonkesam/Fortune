// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

contract MockPrizePool is Ownable {
    constructor() Ownable(msg.sender) {} // Initialize Ownable

    struct Distribution {
        uint256 winnerShare;
        uint256 charityShare;
        uint256 rolloverShare;
    }

    Distribution public prizeDistribution;

    function updatePrizeDistribution(
        uint256 winner,
        uint256 charity,
        uint256 rollover
    ) external onlyOwner {
        prizeDistribution = Distribution(winner, charity, rollover);
    }
}
