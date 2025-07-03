// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ILotteryManager} from "../interfaces/ILotteryManager.sol";

/**
 * @title Advanced Prize Pool with DAO Yield Management
 * @notice Manages prize distribution and yield generation for DAO funds
 * @dev Implements multi-layer security, yield strategy management, and DAO-specific investment logic
 */
contract PrizePool is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address payable;

    // -----------------------------
    // Constants
    // -----------------------------
    uint256 public constant FEE_DENOMINATOR = 10_000;
    uint256 public constant MAX_PROTOCOL_FEE = 1000; // 10%
    uint256 public constant YIELD_SLIPPAGE = 100; // 1%
    uint256 public constant DAO_MIN_SHARE = 500; // 5% minimum
    uint256 public constant EMERGENCY_DELAY = 2 days;

    // Mainnet Aave addresses
    address public constant AAVE_POOL =
        0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9; // Mainnet Aave LendingPool
    address public constant A_WETH = 0x030bA81f1c18d280636F32af80b9AAd02Cf0854e; // Mainnet aWETH

    // -----------------------------
    // State Variables
    // -----------------------------
    ILotteryManager public lotteryManager;
    address public treasury;
    address public feeCollector;
    bool public reinvestFees;

    struct PrizeDistribution {
        uint256 grandPrize; // 30% of pool
        uint256 secondaryPrizes; // 40% of pool
        uint256 daoShare; // 30% of pool
    }

    struct YieldConfig {
        address yieldToken;
        address yieldProtocol;
        bool isActive;
    }

    struct EmergencyWithdrawalSchedule {
        uint256 scheduledTime;
        uint256 amount;
    }

    // Core tracking
    uint256 public prizeReserves; // ETH reserved for prizes
    uint256 public daoEthReserves; // ETH awaiting investment
    uint256 public protocolFee; // Basis points (eg. 200 = 2%)
    uint256 public lastYieldAction;

    // Security controls
    bool public contractActive = true;
    mapping(address => EmergencyWithdrawalSchedule) public emergencySchedules;
    mapping(address => YieldConfig) public yieldStrategies;
    mapping(address => uint256) public daoInvestedAssets; // aWETH balance

    mapping(uint256 => PrizeDistribution) public distributions;
    mapping(address => uint256) public tokenReserves;
    mapping(address => uint256) public unclaimedPrizes;

    uint256 public lastYieldTimestamp;
    uint256 public yieldInterval = 1 days;

    // -----------------------------
    // Events
    // -----------------------------
    event FundsDeposited(uint256 amount, uint256 feeDeducted);
    event PrizesDistributed(uint256 indexed drawId, uint256 totalAmount);
    event YieldGenerated(address indexed protocol, uint256 yieldAmount);
    event ProtocolFeeUpdated(uint256 newFee);

    event EmergencyScheduled(address asset, uint256 executeTime);
    event CircuitBreakerToggled(bool newState);
    event EmergencyWithdraw(address asset, uint256 amount);
    event PrizeAwarded(
        uint256 indexed drawId,
        address indexed winner,
        uint256 amount,
        bool isGolden
    );
    event PrizeClaimed(address indexed winner, uint256 amount);
    event DAOShareTransferred(address indexed treasury, uint256 amount);

    // -----------------------------
    // Errors
    // -----------------------------
    error UnauthorizedManager();
    error InvalidFeeConfiguration();
    error InsufficientLiquidity();
    error YieldProtocolNotWhitelisted();
    error TokenTransferFailed();
    error ZeroAddressProhibited();
    error ExcessiveSlippage();

    // -----------------------------
    // Modifiers
    // -----------------------------
    modifier onlyManager() {
        if (msg.sender != address(lotteryManager)) revert UnauthorizedManager();
        _;
    }

    modifier operational() {
        require(contractActive, "Contract paused");
        _;
    }

    modifier validAddress(address addr) {
        if (addr == address(0)) revert ZeroAddressProhibited();
        _;
    }

    // -----------------------------
    // Constructor
    // -----------------------------
    constructor(
        address _initialOwner,
        address _manager,
        address _treasury,
        address _feeCollector,
        uint256 _protocolFee
    ) Ownable(_initialOwner) validAddress(_manager) {
        require(_treasury != address(0), "Invalid treasury");
        require(_feeCollector != address(0), "Invalid fee collector");

        lotteryManager = ILotteryManager(_manager);
        _setFeeCollector(_feeCollector);
        _setTreasury(_treasury);
        _setProtocolFee(_protocolFee);
    }

    // -----------------------------
    // Core Functions
    // -----------------------------

    /**
     * @notice Deposit lottery proceeds and deduct protocol fees
     * @dev Called automatically by LotteryManager on ticket purchase
     * @param amount ETH amount being deposited
     */
    function deposit(
        uint256 amount
    ) external payable onlyManager operational nonReentrant {
        uint256 feeAmount = (amount * protocolFee) / FEE_DENOMINATOR;
        uint256 netAmount = amount - feeAmount;

        // Distribute fees
        if (reinvestFees) {
            daoEthReserves += feeAmount;
        } else {
            _safeTransferETH(feeCollector, feeAmount);
        }

        // Update reserves
        prizeReserves += netAmount;
        emit FundsDeposited(amount, feeAmount);
    }

    /**
     * @notice Distribute prizes for a completed draw and allocate DAO share
     * @dev Only DAO share is retained for yield generation
     * @param drawId ID of the completed draw
     * @param winners Array of winning ticket IDs
     * @dev Can only be called by LotteryManager
     */
    function distributePrizes(
        uint256 drawId,
        address[] calldata winners
    ) external onlyManager operational nonReentrant {
        uint256 totalPrize = prizeReserves;
        PrizeDistribution memory dist = _calculateDistribution(totalPrize);

        // Record grand prize
        unclaimedPrizes[winners[0]] += dist.grandPrize;
        emit PrizeAwarded(drawId, winners[0], dist.grandPrize, true); // true for golden ticket winner

        // Record secondary prizes
        uint256 secondaryPrize = dist.secondaryPrizes / (winners.length - 1);
        for (uint256 i = 1; i < winners.length; i++) {
            unclaimedPrizes[winners[i]] += secondaryPrize;
            emit PrizeAwarded(drawId, winners[i], secondaryPrize, false); // false for secondary winners
        }

        // Transfer DAO share directly to Treasury
        _safeTransferETH(treasury, dist.daoShare);
        emit DAOShareTransferred(treasury, dist.daoShare);

        prizeReserves =
            totalPrize -
            (dist.grandPrize + dist.secondaryPrizes + dist.daoShare);

        emit PrizesDistributed(drawId, totalPrize);
    }

    function claimPrize() external nonReentrant {
        uint256 amount = unclaimedPrizes[msg.sender];
        require(amount > 0, "No prize to claim");

        unclaimedPrizes[msg.sender] = 0;
        _safeTransferETH(msg.sender, amount);

        emit PrizeClaimed(msg.sender, amount);
    }

    // -----------------------------
    // Security, Admin and Emergency Functions
    // -----------------------------

    function toggleCircuitBreaker() external onlyOwner {
        contractActive = !contractActive;
        emit CircuitBreakerToggled(contractActive);
    }

    function scheduleEmergencyWithdraw(address asset) external onlyOwner {
        emergencySchedules[asset] = EmergencyWithdrawalSchedule({
            scheduledTime: block.timestamp + EMERGENCY_DELAY,
            amount: _getAssetBalance(asset)
        });
        emit EmergencyScheduled(asset, block.timestamp + EMERGENCY_DELAY);
    }

    function executeEmergencyWithdraw(address asset) external onlyOwner {
        EmergencyWithdrawalSchedule memory scheduled = emergencySchedules[
            asset
        ];
        require(block.timestamp >= scheduled.scheduledTime, "Too early");

        uint256 amount = _getAssetBalance(asset);
        _safeTransfer(asset, owner(), amount);

        delete emergencySchedules[asset];
        emit EmergencyWithdraw(asset, amount);
    }

    // -----------------------------
    // Configuration Functions
    // -----------------------------

    function setProtocolFee(uint256 newFee) external onlyOwner {
        _setProtocolFee(newFee);
    }

    function setLotteryManager(address _manager) external onlyOwner {
        require(_manager != address(0), "Invalid address");
        lotteryManager = ILotteryManager(_manager);
    }

    function setDistributionRatios(
        uint256 grand,
        uint256 secondary,
        uint256 dao
    ) external view onlyOwner {
        _validateDistributionRatios(grand, secondary, dao);
    }

    function setFeeReinvest(bool status) external onlyOwner {
        reinvestFees = status;
    }

    // -----------------------------
    // Internal Functions
    // -----------------------------

    function _calculateDistribution(
        uint256 totalAmount
    ) internal pure returns (PrizeDistribution memory) {
        return
            PrizeDistribution({
                grandPrize: (totalAmount * 3000) / FEE_DENOMINATOR, // 30%
                secondaryPrizes: (totalAmount * 4000) / FEE_DENOMINATOR, // 40%
                daoShare: (totalAmount * 3000) / FEE_DENOMINATOR // 30%
            });
    }

    function _validateDistributionRatios(
        uint256 grand,
        uint256 secondary,
        uint256 dao
    ) internal pure {
        require(grand + secondary + dao == FEE_DENOMINATOR, "Invalid ratios");
        require(dao >= DAO_MIN_SHARE, "DAO share too low");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        if (token == address(0)) {
            _safeTransferETH(to, amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    function _safeTransferETH(address to, uint256 amount) internal {
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert TokenTransferFailed();
    }

    function _setProtocolFee(uint256 newFee) internal {
        if (newFee > MAX_PROTOCOL_FEE) revert InvalidFeeConfiguration();
        protocolFee = newFee;
        emit ProtocolFeeUpdated(newFee);
    }

    function _setTreasury(
        address newTreasury
    ) internal validAddress(newTreasury) {
        treasury = newTreasury;
    }

    function _setFeeCollector(
        address newCollector
    ) internal validAddress(newCollector) {
        feeCollector = newCollector;
    }

    function _getAssetBalance(address asset) internal view returns (uint256) {
        return
            asset == address(0)
                ? address(this).balance
                : IERC20(asset).balanceOf(address(this));
    }

    // -----------------------------
    // Fallback & Receive
    // -----------------------------
    receive() external payable {
        // Accept ETH deposits only through deposit()
        if (msg.sender != address(lotteryManager)) revert UnauthorizedManager();
    }
}
