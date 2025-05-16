// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ILotteryManager} from "../interfaces/ILotteryManager.sol";
import {IAave} from "../interfaces/IAave.sol";

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
    uint256 public constant MAX_PROTOCOL_FEE = 500; // 5%
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
    ILotteryManager public immutable lotteryManager;
    address public treasury;
    address public feeCollector;
    bool public reinvestFees;

    struct PrizeDistribution {
        uint256 grandPrize; // 70% of pool
        uint256 secondaryPrizes; // 20% of pool
        uint256 daoShare; // 10% of pool
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

    uint256 public lastYieldTimestamp;
    uint256 public yieldInterval = 1 days;

    // -----------------------------
    // Events
    // -----------------------------
    event FundsDeposited(uint256 amount, uint256 feeDeducted);
    event PrizesDistributed(uint256 indexed drawId, uint256 totalAmount);
    event YieldGenerated(address indexed protocol, uint256 yieldAmount);
    event ProtocolFeeUpdated(uint256 newFee);
    event DAOInvested(address protocol, uint256 amount);
    event DAOYieldRedeemed(uint256 ethAmount);
    event EmergencyScheduled(address asset, uint256 executeTime);
    event CircuitBreakerToggled(bool newState);
    event EmergencyWithdraw(address asset, uint256 amount);

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

        yieldStrategies[AAVE_POOL] = YieldConfig({
            yieldToken: A_WETH,
            yieldProtocol: AAVE_POOL,
            isActive: true
        });
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

        // Distribute grand prize
        _safeTransferETH(winners[0], dist.grandPrize);

        // Distribute secondary prizes
        for (uint256 i = 1; i < winners.length; i++) {
            _safeTransferETH(
                winners[i],
                dist.secondaryPrizes / (winners.length - 1)
            );
        }

        // Transfer DAO share
        daoEthReserves += dist.daoShare;
        prizeReserves =
            totalPrize -
            (dist.grandPrize + dist.secondaryPrizes + dist.daoShare);

        emit PrizesDistributed(drawId, totalPrize);
    }

    // -----------------------------
    // Yield Generation Functions
    // -----------------------------

    /**
     * @notice Invest DAO reserves into yield-generating protocol
     * @param protocol Address of whitelisted yield protocol
     * @param minAmountOut Minimum expected aWETH received
     * @dev Implements slippage protection
     */
    function investDAOFunds(
        address protocol,
        uint256 minAmountOut
    ) external onlyOwner operational nonReentrant {
        YieldConfig memory config = yieldStrategies[protocol];
        if (!config.isActive) revert YieldProtocolNotWhitelisted();

        uint256 investmentAmount = daoEthReserves;
        if (investmentAmount == 0) revert InsufficientLiquidity();

        // Execute yield strategy
        daoEthReserves = 0;
        uint256 preBalance = IERC20(config.yieldToken).balanceOf(address(this));

        // Example: Aave deposit
        IAave(config.yieldProtocol).deposit{value: investmentAmount}(
            address(0), // ETH
            investmentAmount,
            address(this),
            0
        );
        uint256 received = IERC20(config.yieldToken).balanceOf(address(this)) -
            preBalance;

        require(received >= minAmountOut, "Insufficient yield");

        daoInvestedAssets[config.yieldToken] += received;
        lastYieldAction = block.timestamp;

        emit DAOInvested(protocol, investmentAmount);
    }

    /**
     * @notice Redeem yield-generated assets back to ETH
     * @param protocol Yield protocol address
     * @param amount aWETH amount to redeem
     * @param minEthOut Minimum ETH expected
     */
    function redeemDAOYield(
        address protocol,
        uint256 amount,
        uint256 minEthOut
    ) external onlyOwner operational nonReentrant {
        YieldConfig memory config = yieldStrategies[protocol];
        require(
            daoInvestedAssets[config.yieldToken] >= amount,
            "Insufficient balance"
        );

        uint256 preBalance = address(this).balance;
        IAave(config.yieldProtocol).withdraw(address(0), amount, address(this));
        uint256 received = address(this).balance - preBalance;

        require(received >= minEthOut, "Slippage too high");
        daoInvestedAssets[config.yieldToken] -= amount;
        daoEthReserves += received;

        emit DAOYieldRedeemed(received);
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

    function setDistributionRatios(
        uint256 grand,
        uint256 secondary,
        uint256 dao
    ) external onlyOwner {
        _validateDistributionRatios(grand, secondary, dao);
    }

    function setFeeReinvest(bool status) external onlyOwner {
        reinvestFees = status;
    }

    function setYieldProtocol(
        address protocol,
        address yieldToken,
        bool active
    ) external onlyOwner validAddress(protocol) {
        yieldStrategies[protocol] = YieldConfig(yieldToken, protocol, active);
    }

    // -----------------------------
    // Internal Functions
    // -----------------------------

    function _calculateDistribution(
        uint256 totalAmount
    ) internal pure returns (PrizeDistribution memory) {
        return
            PrizeDistribution({
                grandPrize: (totalAmount * 7000) / FEE_DENOMINATOR, // 70%
                secondaryPrizes: (totalAmount * 2000) / FEE_DENOMINATOR, // 20%
                daoShare: (totalAmount * 1000) / FEE_DENOMINATOR // 10%
            });
    }

    function _validateDistributionRatios(
        uint256 grand,
        uint256 secondary,
        uint256 dao
    ) internal {
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
