// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

contract MockPrizePool is Ownable {
    constructor() Ownable(msg.sender) {} // Initialize Ownable

    // Original state variables
    struct Distribution {
        uint256 winnerShare;
        uint256 charityShare;
        uint256 rolloverShare;
    }

    Distribution public prizeDistribution;

    // Additional state variables needed for tests
    address public lotteryManager;
    bool public distributePrizesCalled;
    uint256 public lastDepositAmount;
    uint256 public lastDistributeDrawId;
    address[] private _lastDistributeWinners;

    // For governance tests
    address public yieldAdapter;
    address public yieldToken;
    bool public isYieldActive;

    // Original function
    function updatePrizeDistribution(
        uint256 winner,
        uint256 charity,
        uint256 rollover
    ) external onlyOwner {
        prizeDistribution = Distribution(winner, charity, rollover);
    }

    // Governance controllable function
    function setYieldProtocol(
        address _yieldAdapter,
        address _yieldToken,
        bool _active
    ) external {
        yieldAdapter = _yieldAdapter;
        yieldToken = _yieldToken;
        isYieldActive = _active;
    }

    function yieldProtocol() external view returns (address, address, bool) {
        return (yieldAdapter, yieldToken, isYieldActive);
    }

    // Additional functions needed for tests
    function setLotteryManager(address _lotteryManager) external onlyOwner {
        lotteryManager = _lotteryManager;
    }

    /**
     * @notice Mock deposit function (added amount parameter)
     */
    function deposit(uint256 /* amount */) external payable {
        lastDepositAmount = msg.value;
    }

    /**
     * @notice Mock distribute prizes function
     * @param drawId The draw ID to distribute for
     * @param winners The winner addresses
     */
    function distributePrizes(
        uint256 drawId,
        address[] memory winners
    ) external {
        require(msg.sender == lotteryManager, "Not lottery manager");

        distributePrizesCalled = true;
        lastDistributeDrawId = drawId;

        // Store winners for later verification
        delete _lastDistributeWinners;
        for (uint256 i = 0; i < winners.length; i++) {
            _lastDistributeWinners.push(winners[i]);
        }
    }

    /**
     * @notice Getter for the last distributed winners array
     * @return An array of winner addresses from the last distribution
     */
    function lastDistributeWinners() external view returns (address[] memory) {
        return _lastDistributeWinners;
    }
}
