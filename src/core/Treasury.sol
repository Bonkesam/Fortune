// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IAave} from "../interfaces/IAave.sol";

/**
 * @title dFortune Treasury
 * @notice Secure asset management contract with DAO-controlled withdrawals
 * @dev Implements timelock-protected operations and multi-asset support
 */
contract Treasury is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // -----------------------------
    // Constants & Roles
    // -----------------------------
    bytes32 public constant TIMELOCK_ROLE = keccak256("TIMELOCK_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant YIELD_MANAGER_ROLE =
        keccak256("YIELD_MANAGER_ROLE");
    uint256 public constant MIN_DELAY = 2 days;
    uint256 public constant EMERGENCY_DELAY = 6 hours;
    uint256 public constant FEE_DENOMINATOR = 10_000;
    uint256 public constant YIELD_SLIPPAGE = 100; // 1%

    // Mainnet Aave addresses - these were in PrizePool before
    address public constant AAVE_POOL =
        0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9; // Mainnet Aave LendingPool
    address public constant A_WETH = 0x030bA81f1c18d280636F32af80b9AAd02Cf0854e; // Mainnet aWETH

    // -----------------------------
    // Storage
    // -----------------------------
    struct Withdrawal {
        address target;
        uint256 value;
        bytes data;
        uint256 timestamp;
        bool executed;
    }

    struct YieldConfig {
        address yieldToken;
        address yieldProtocol;
        bool isActive;
    }

    mapping(bytes32 => Withdrawal) public scheduledOperations;
    mapping(address => bool) public approvedAssets;
    uint256 public operationDelay;
    uint256 public lastYieldAction;
    mapping(address => YieldConfig) public yieldStrategies;
    mapping(address => uint256) public investedAssets; // Track invested assets (e.g., aWETH balance)

    // -----------------------------
    // Events
    // -----------------------------
    event OperationScheduled(
        bytes32 indexed id,
        address target,
        uint256 value,
        bytes data
    );
    event OperationExecuted(bytes32 indexed id);
    event OperationCancelled(bytes32 indexed id);
    event EmergencyWithdraw(address indexed token, uint256 amount);
    event DelayUpdated(uint256 newDelay);
    event DAOInvested(address protocol, uint256 amount);
    event DAOYieldRedeemed(address indexed protocol, uint256 amount);
    event YieldStrategyUpdated(
        address protocol,
        address yieldToken,
        bool active
    );

    // -----------------------------
    // Errors
    // -----------------------------
    error Unauthorized();
    error InvalidOperation();
    error InsufficientDelay();
    error OperationPending();
    error OperationNotReady();
    error InvalidAsset();
    error YieldProtocolNotWhitelisted();
    error InsufficientLiquidity();
    error ExcessiveSlippage();

    // -----------------------------
    // Constructor
    // -----------------------------
    constructor(address dao, address[] memory initialAssets) {
        _grantRole(DEFAULT_ADMIN_ROLE, dao);
        _grantRole(TIMELOCK_ROLE, dao);
        _grantRole(EMERGENCY_ROLE, dao);
        _grantRole(YIELD_MANAGER_ROLE, dao);
        operationDelay = MIN_DELAY;

        for (uint256 i = 0; i < initialAssets.length; i++) {
            approvedAssets[initialAssets[i]] = true;
        }

        // Initialize Aave strategy
        yieldStrategies[AAVE_POOL] = YieldConfig({
            yieldToken: A_WETH,
            yieldProtocol: AAVE_POOL,
            isActive: true
        });

        // Approve ETH as a valid asset
        approvedAssets[address(0)] = true;
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
    ) external onlyRole(YIELD_MANAGER_ROLE) nonReentrant {
        YieldConfig memory config = yieldStrategies[protocol];
        if (!config.isActive) revert YieldProtocolNotWhitelisted();

        uint256 investmentAmount = address(this).balance;
        if (investmentAmount == 0) revert InsufficientLiquidity();

        // Execute yield strategy
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

        if (received < minAmountOut) revert ExcessiveSlippage();

        investedAssets[config.yieldToken] += received;
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
    ) external onlyRole(YIELD_MANAGER_ROLE) nonReentrant {
        YieldConfig memory config = yieldStrategies[protocol];
        if (!config.isActive) revert YieldProtocolNotWhitelisted();

        if (investedAssets[config.yieldToken] < amount)
            revert InsufficientLiquidity();

        uint256 preBalance = address(this).balance;
        IAave(config.yieldProtocol).withdraw(address(0), amount, address(this));
        uint256 received = address(this).balance - preBalance;

        if (received < minEthOut) revert ExcessiveSlippage();
        investedAssets[config.yieldToken] -= amount;

        emit DAOYieldRedeemed(protocol, received);
    }

    /**
     * @notice Configure a new yield protocol
     * @param protocol Protocol address
     * @param yieldToken Token received from protocol
     * @param active Whether protocol is active
     */
    function setYieldProtocol(
        address protocol,
        address yieldToken,
        bool active
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (protocol == address(0)) revert InvalidAsset();

        yieldStrategies[protocol] = YieldConfig({
            yieldToken: yieldToken,
            yieldProtocol: protocol,
            isActive: active
        });

        // Auto-approve the yield token as a valid asset
        if (yieldToken != address(0)) {
            approvedAssets[yieldToken] = true;
        }

        emit YieldStrategyUpdated(protocol, yieldToken, active);
    }

    // -----------------------------
    // Core Functions
    // -----------------------------

    /**
     * @notice Schedule a withdrawal operation
     * @param target Asset address (address(0) for ETH)
     * @param value Amount to withdraw
     * @param data Encoded recipient address
     * @return operationId Unique schedule identifier
     */
    function scheduleWithdraw(
        address target,
        uint256 value,
        bytes calldata data
    ) external onlyRole(TIMELOCK_ROLE) returns (bytes32 operationId) {
        if (!approvedAssets[target]) revert InvalidAsset();

        operationId = keccak256(
            abi.encode(target, value, data, block.timestamp)
        );
        if (scheduledOperations[operationId].timestamp != 0)
            revert OperationPending();

        scheduledOperations[operationId] = Withdrawal({
            target: target,
            value: value,
            data: data,
            timestamp: block.timestamp + operationDelay,
            executed: false
        });

        emit OperationScheduled(operationId, target, value, data);
    }

    /**
     * @notice Execute scheduled withdrawal
     * @param operationId Precomputed schedule identifier
     */
    function executeWithdraw(bytes32 operationId) external nonReentrant {
        Withdrawal storage op = scheduledOperations[operationId];
        if (op.executed) revert InvalidOperation();
        if (block.timestamp < op.timestamp) revert OperationNotReady();

        op.executed = true;
        _executeWithdraw(op.target, op.value, op.data);

        emit OperationExecuted(operationId);
    }

    // -----------------------------
    // Emergency Functions
    // -----------------------------

    /**
     * @notice Emergency asset withdrawal
     * @param token Asset address (address(0) for ETH)
     * @param amount Amount to withdraw
     * @dev Requires EMERGENCY_ROLE and enforces shorter delay
     */
    function emergencyWithdraw(
        address token,
        uint256 amount,
        address recipient
    ) external onlyRole(EMERGENCY_ROLE) nonReentrant {
        if (block.timestamp % EMERGENCY_DELAY != 0) revert OperationNotReady();
        _transferAsset(token, amount, recipient);
        emit EmergencyWithdraw(token, amount);
    }

    // -----------------------------
    // Admin Functions
    // -----------------------------

    /**
     * @notice Update operation delay
     * @param newDelay New delay in seconds
     * @dev Minimum delay enforced
     */
    function setDelay(uint256 newDelay) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newDelay < MIN_DELAY) revert InsufficientDelay();
        operationDelay = newDelay;
        emit DelayUpdated(newDelay);
    }

    /**
     * @notice Approve new asset for withdrawals
     * @param asset Asset contract address
     */
    function approveAsset(address asset) external onlyRole(DEFAULT_ADMIN_ROLE) {
        approvedAssets[asset] = true;
    }

    // -----------------------------
    // Internal Functions
    // -----------------------------

    function _executeWithdraw(
        address target,
        uint256 value,
        bytes memory data
    ) internal {
        address recipient = abi.decode(data, (address));
        _transferAsset(target, value, recipient);
    }

    function _transferAsset(
        address asset,
        uint256 amount,
        address to
    ) internal {
        if (asset == address(0)) {
            (bool success, ) = to.call{value: amount}("");
            if (!success) revert InvalidOperation();
        } else {
            IERC20(asset).safeTransfer(to, amount);
        }
    }

    // -----------------------------
    // Fallback
    // -----------------------------
    receive() external payable {} // Accept ETH deposits
}
