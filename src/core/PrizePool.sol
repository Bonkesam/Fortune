// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ILotteryManager} from "../interfaces/ILotteryManager.sol";

/**
 * @title Prize Pool
 * @notice Manages prize distribution and yield generation for lottery funds
 * @dev Implements multi-layer security with DeFi integrations
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

    // -----------------------------
    // State Variables
    // -----------------------------
    ILotteryManager public immutable lotteryManager;
    address public treasury;
    address public feeCollector;

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

    mapping(uint256 => PrizeDistribution) public distributions;
    mapping(address => YieldConfig) public yieldStrategies;
    mapping(address => uint256) public tokenReserves;

    uint256 public protocolFee; // Basis points (e.g., 200 = 2%)
    uint256 public lastYieldTimestamp;
    uint256 public yieldInterval = 1 days;

    // -----------------------------
    // Events
    // -----------------------------
    event FundsDeposited(uint256 amount, uint256 feeDeducted);
    event PrizesDistributed(uint256 indexed drawId, uint256 totalAmount);
    event YieldGenerated(address indexed protocol, uint256 yieldAmount);
    event EmergencyWithdraw(address indexed token, uint256 amount);
    event ProtocolFeeUpdated(uint256 newFee);

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

    modifier validAddress(address addr) {
        if (addr == address(0)) revert ZeroAddressProhibited();
        _;
    }

    // -----------------------------
    // Constructor
    // -----------------------------
    constructor(
        address _manager,
        address _treasury,
        address _feeCollector,
        uint256 _protocolFee
    ) Ownable2Step() validAddress(_manager) {
        lotteryManager = ILotteryManager(_manager);
        _setFeeCollector(_feeCollector);
        _setTreasury(_treasury);
        _setProtocolFee(_protocolFee);
    }

    // -----------------------------
    // Core Functions
    // -----------------------------

    /**
     * @notice Deposit funds from ticket sales
     * @dev Called automatically by LotteryManager on ticket purchase
     * @param amount ETH amount being deposited
     */
    function deposit(uint256 amount) external payable onlyManager nonReentrant {
        uint256 feeAmount = (amount * protocolFee) / FEE_DENOMINATOR;
        uint256 netAmount = amount - feeAmount;

        // Distribute fees
        (bool feeSuccess, ) = feeCollector.call{value: feeAmount}("");
        if (!feeSuccess) revert TokenTransferFailed();

        // Update reserves
        tokenReserves[address(0)] += netAmount;

        emit FundsDeposited(amount, feeAmount);
    }

    /**
     * @notice Distribute prizes for a completed draw
     * @param drawId ID of the completed draw
     * @param winningTickets Array of winning ticket IDs
     * @dev Can only be called by LotteryManager
     */
    function distributePrizes(
        uint256 drawId,
        uint256[] calldata winningTickets
    ) external onlyManager nonReentrant {
        uint256 totalPrizePool = tokenReserves[address(0)];
        PrizeDistribution memory dist = _calculateDistribution(totalPrizePool);

        // Distribute grand prize
        _safeTransferETH(winningTickets[0], dist.grandPrize);

        // Distribute secondary prizes
        for (uint256 i = 1; i < winningTickets.length; i++) {
            _safeTransferETH(
                winningTickets[i],
                dist.secondaryPrizes / (winningTickets.length - 1)
            );
        }

        // Transfer DAO share
        (bool daoSuccess, ) = treasury.call{value: dist.daoShare}("");
        if (!daoSuccess) revert TokenTransferFailed();

        // Update state
        distributions[drawId] = dist;
        tokenReserves[address(0)] = 0;

        emit PrizesDistributed(drawId, totalPrizePool);
    }

    // -----------------------------
    // Yield Generation Functions
    // -----------------------------

    /**
     * @notice Invest reserves into yield-generating protocol
     * @param protocol Address of whitelisted yield protocol
     * @param minAmountOut Minimum expected tokens from investment
     * @dev Implements slippage protection
     */
    function investInYield(
        address protocol,
        uint256 minAmountOut
    ) external onlyOwner nonReentrant {
        YieldConfig memory config = yieldStrategies[protocol];
        if (!config.isActive) revert YieldProtocolNotWhitelisted();

        uint256 investmentAmount = tokenReserves[address(0)];
        if (investmentAmount == 0) revert InsufficientLiquidity();

        // Execute yield strategy
        tokenReserves[address(0)] = 0;
        uint256 sharesBefore = IERC20(config.yieldToken).balanceOf(
            address(this)
        );

        // Example: Aave deposit
        IAave(aavePool).deposit{value: investmentAmount}(
            address(0), // ETH
            investmentAmount,
            address(this),
            0
        );
        uint256 sharesAfter = IERC20(config.yieldToken).balanceOf(
            address(this)
        );
        if (sharesAfter - sharesBefore < minAmountOut)
            revert ExcessiveSlippage();

        tokenReserves[config.yieldToken] += sharesAfter - sharesBefore;
        lastYieldTimestamp = block.timestamp;

        emit YieldGenerated(protocol, sharesAfter - sharesBefore);
    }

    // -----------------------------
    // Emergency Functions
    // -----------------------------

    /**
     * @notice Emergency withdraw funds from contract
     * @param token Address of token to withdraw (address(0) for ETH)
     * @dev Only callable by owner after timelock
     */
    function emergencyWithdraw(address token) external onlyOwner nonReentrant {
        uint256 amount = token == address(0)
            ? address(this).balance
            : IERC20(token).balanceOf(address(this));

        _safeTransfer(token, msg.sender, amount);
        emit EmergencyWithdraw(token, amount);
    }

    // -----------------------------
    // Admin Functions
    // -----------------------------

    function setProtocolFee(uint256 newFee) external onlyOwner {
        _setProtocolFee(newFee);
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

    // -----------------------------
    // Fallback & Receive
    // -----------------------------
    receive() external payable {
        // Accept ETH deposits only through deposit()
        if (msg.sender != address(lotteryManager)) revert UnauthorizedManager();
    }
}
