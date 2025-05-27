// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockTreasury
 * @notice Mock implementation of Treasury contract for testing
 * @dev Simulates treasury operations without complex timelock logic
 */
contract MockTreasury {
    using SafeERC20 for IERC20;

    // -----------------------------
    // Storage
    // -----------------------------
    struct YieldConfig {
        address yieldToken;
        address yieldProtocol;
        bool isActive;
    }

    struct Withdrawal {
        address target;
        uint256 value;
        bytes data;
        uint256 timestamp;
        bool executed;
    }

    mapping(address => bool) public approvedAssets;
    mapping(address => YieldConfig) public yieldStrategies;
    mapping(address => uint256) public investedAssets;
    mapping(bytes32 => Withdrawal) public scheduledOperations;

    uint256 public operationDelay = 2 days;
    uint256 public lastYieldAction;
    address public owner;

    // Mock state variables for testing
    uint256 public mockBalance = 100 ether;
    uint256 public mockYieldGenerated = 5 ether;
    bool public shouldFailInvestment = false;
    bool public shouldFailRedemption = false;

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
    event AssetApproved(address indexed asset);

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
    constructor() {
        owner = msg.sender;

        // Pre-approve common assets for testing
        approvedAssets[address(0)] = true; // ETH

        // Mock Aave strategy
        address mockAavePool = address(0x1);
        address mockAWETH = address(0x2);
        yieldStrategies[mockAavePool] = YieldConfig({
            yieldToken: mockAWETH,
            yieldProtocol: mockAavePool,
            isActive: true
        });
        approvedAssets[mockAWETH] = true;
    }

    // -----------------------------
    // Modifiers
    // -----------------------------
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    // -----------------------------
    // Yield Generation Functions
    // -----------------------------

    /**
     * @notice Mock investment function
     * @param protocol Address of yield protocol
     * @param minAmountOut Minimum expected yield tokens
     */
    function investDAOFunds(
        address protocol,
        uint256 minAmountOut
    ) external onlyOwner {
        if (shouldFailInvestment) revert InsufficientLiquidity();

        YieldConfig storage config = yieldStrategies[protocol];
        if (!config.isActive) revert YieldProtocolNotWhitelisted();

        uint256 investmentAmount = mockBalance;
        if (investmentAmount == 0) revert InsufficientLiquidity();

        // Simulate yield token receipt
        uint256 yieldTokensReceived = investmentAmount; // 1:1 for simplicity
        if (yieldTokensReceived < minAmountOut) revert ExcessiveSlippage();

        investedAssets[config.yieldToken] += yieldTokensReceived;
        mockBalance = 0; // All funds invested
        lastYieldAction = block.timestamp;

        emit DAOInvested(protocol, investmentAmount);
    }

    /**
     * @notice Mock yield redemption function
     * @param protocol Yield protocol address
     * @param amount Yield tokens to redeem
     * @param minEthOut Minimum ETH expected
     */
    function redeemDAOYield(
        address protocol,
        uint256 amount,
        uint256 minEthOut
    ) external onlyOwner {
        if (shouldFailRedemption) revert InsufficientLiquidity();

        YieldConfig storage config = yieldStrategies[protocol];
        if (!config.isActive) revert YieldProtocolNotWhitelisted();

        if (investedAssets[config.yieldToken] < amount) {
            revert InsufficientLiquidity();
        }

        // Simulate ETH received (with yield)
        uint256 ethReceived = amount + mockYieldGenerated;
        if (ethReceived < minEthOut) revert ExcessiveSlippage();

        investedAssets[config.yieldToken] -= amount;
        mockBalance += ethReceived;

        emit DAOYieldRedeemed(protocol, ethReceived);
    }

    /**
     * @notice Configure yield protocol
     * @param protocol Protocol address
     * @param yieldToken Yield token address
     * @param active Whether protocol is active
     */
    function setYieldProtocol(
        address protocol,
        address yieldToken,
        bool active
    ) external onlyOwner {
        if (protocol == address(0)) revert InvalidAsset();

        yieldStrategies[protocol] = YieldConfig({
            yieldToken: yieldToken,
            yieldProtocol: protocol,
            isActive: active
        });

        if (yieldToken != address(0)) {
            approvedAssets[yieldToken] = true;
        }

        emit YieldStrategyUpdated(protocol, yieldToken, active);
    }

    // -----------------------------
    // Withdrawal Functions
    // -----------------------------

    /**
     * @notice Schedule withdrawal (simplified for testing)
     * @param target Asset address
     * @param value Amount to withdraw
     * @param data Encoded recipient data
     */
    function scheduleWithdraw(
        address target,
        uint256 value,
        bytes calldata data
    ) external onlyOwner returns (bytes32 operationId) {
        if (!approvedAssets[target]) revert InvalidAsset();

        operationId = keccak256(
            abi.encode(target, value, data, block.timestamp)
        );

        if (scheduledOperations[operationId].timestamp != 0) {
            revert OperationPending();
        }

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
     * @param operationId Operation identifier
     */
    function executeWithdraw(bytes32 operationId) external {
        Withdrawal storage op = scheduledOperations[operationId];

        if (op.executed) revert InvalidOperation();
        if (block.timestamp < op.timestamp) revert OperationNotReady();

        op.executed = true;

        // Simulate withdrawal execution
        address recipient = abi.decode(op.data, (address));
        _mockTransfer(op.target, op.value, recipient);

        emit OperationExecuted(operationId);
    }

    /**
     * @notice Emergency withdrawal function
     * @param token Token address (address(0) for ETH)
     * @param amount Amount to withdraw
     * @param recipient Recipient address
     */
    function emergencyWithdraw(
        address token,
        uint256 amount,
        address recipient
    ) external onlyOwner {
        _mockTransfer(token, amount, recipient);
        emit EmergencyWithdraw(token, amount);
    }

    // -----------------------------
    // Admin Functions
    // -----------------------------

    /**
     * @notice Set operation delay
     * @param newDelay New delay in seconds
     */
    function setDelay(uint256 newDelay) external onlyOwner {
        if (newDelay < 1 hours) revert InsufficientDelay();
        operationDelay = newDelay;
        emit DelayUpdated(newDelay);
    }

    /**
     * @notice Approve asset for operations
     * @param asset Asset address
     */
    function approveAsset(address asset) external onlyOwner {
        approvedAssets[asset] = true;
        emit AssetApproved(asset);
    }

    /**
     * @notice Transfer ownership
     * @param newOwner New owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidOperation();
        owner = newOwner;
    }

    // -----------------------------
    // Test Helper Functions
    // -----------------------------

    /**
     * @notice Set mock balance for testing
     * @param newBalance New mock balance
     */
    function setMockBalance(uint256 newBalance) external {
        mockBalance = newBalance;
    }

    /**
     * @notice Set mock yield generated
     * @param yieldAmount Yield amount
     */
    function setMockYieldGenerated(uint256 yieldAmount) external {
        mockYieldGenerated = yieldAmount;
    }

    /**
     * @notice Toggle investment failure for testing
     * @param shouldFail Whether investment should fail
     */
    function setShouldFailInvestment(bool shouldFail) external {
        shouldFailInvestment = shouldFail;
    }

    /**
     * @notice Toggle redemption failure for testing
     * @param shouldFail Whether redemption should fail
     */
    function setShouldFailRedemption(bool shouldFail) external {
        shouldFailRedemption = shouldFail;
    }

    /**
     * @notice Get invested amount for asset
     * @param asset Asset address
     * @return Invested amount
     */
    function getInvestedAmount(address asset) external view returns (uint256) {
        return investedAssets[asset];
    }

    /**
     * @notice Check if asset is approved
     * @param asset Asset address
     * @return Whether asset is approved
     */
    function isAssetApproved(address asset) external view returns (bool) {
        return approvedAssets[asset];
    }

    /**
     * @notice Get yield strategy config
     * @param protocol Protocol address
     * @return YieldConfig struct
     */
    function getYieldStrategy(
        address protocol
    ) external view returns (YieldConfig memory) {
        return yieldStrategies[protocol];
    }

    // -----------------------------
    // Internal Functions
    // -----------------------------

    /**
     * @notice Mock transfer function
     * @param asset Asset address
     * @param amount Amount to transfer
     * @param recipient Recipient address
     */
    function _mockTransfer(
        address asset,
        uint256 amount,
        address recipient
    ) internal {
        // In a real implementation, this would transfer tokens
        // For mock, we just emit events and update balances
        if (asset == address(0)) {
            // Mock ETH transfer
            require(mockBalance >= amount, "Insufficient ETH balance");
            mockBalance -= amount;
        } else {
            // Mock token transfer - in real test, you'd use actual tokens
            // This is just a placeholder for the mock
        }
    }

    // -----------------------------
    // Fallback
    // -----------------------------
    receive() external payable {
        mockBalance += msg.value;
    }
}
