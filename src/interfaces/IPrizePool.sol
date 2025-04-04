// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IPrizePool
 * @notice Interface for Prize Pool management and distribution
 * @dev Defines secure interaction points for prize pool operations
 */
interface IPrizePool {
    // -----------------------------
    // Structures
    // -----------------------------

    /// @notice Prize distribution configuration
    /// @param grandPrize Percentage allocated to main winner (basis points)
    /// @param secondaryPrizes Percentage for secondary winners
    /// @param daoShare Percentage reserved for DAO treasury
    struct PrizeDistribution {
        uint256 grandPrize;
        uint256 secondaryPrizes;
        uint256 daoShare;
    }

    /// @notice Yield generation protocol configuration
    /// @param yieldToken Token representing yield position
    /// @param yieldProtocol Address of yield provider (e.g., Aave)
    /// @param isActive Whether protocol is currently enabled
    struct YieldConfig {
        address yieldToken;
        address yieldProtocol;
        bool isActive;
    }

    // -----------------------------
    // Events
    // -----------------------------

    /// @notice Emitted on successful fund deposit
    /// @param amount Total ETH deposited
    /// @param feeDeducted Protocol fee amount
    event FundsDeposited(uint256 amount, uint256 feeDeducted);

    /// @notice Emitted when prizes are distributed
    /// @param drawId Lottery draw identifier
    /// @param totalAmount Total ETH distributed
    event PrizesDistributed(uint256 indexed drawId, uint256 totalAmount);

    /// @notice Emitted on yield generation
    /// @param protocol Yield protocol address
    /// @param yieldAmount Amount of yield generated
    event YieldGenerated(address indexed protocol, uint256 yieldAmount);

    // -----------------------------
    // Errors
    // -----------------------------

    /// @dev Reverts on unauthorized manager access
    error UnauthorizedManager();

    /// @dev Reverts when protocol fee exceeds maximum
    error InvalidFeeConfiguration();

    /// @dev Reverts on insufficient funds for operation
    error InsufficientLiquidity();

    // -----------------------------
    // Core Functions
    // -----------------------------

    /**
     * @notice Deposit funds into prize pool
     * @dev Only callable by LotteryManager
     * @param amount ETH value being deposited
     */
    function deposit(uint256 amount) external payable;

    /**
     * @notice Distribute prizes for completed draw
     * @param drawId Lottery draw identifier
     * @param winningTickets Array of winning ticket IDs
     * @dev Only callable by LotteryManager
     */
    function distributePrizes(
        uint256 drawId,
        uint256[] calldata winningTickets
    ) external;

    // -----------------------------
    // Yield Management
    // -----------------------------

    /**
     * @notice Invest reserves in yield-generating protocol
     * @param protocol Whitelisted yield protocol address
     * @param minAmountOut Minimum expected output tokens
     * @dev Implements slippage protection
     */
    function investInYield(address protocol, uint256 minAmountOut) external;

    // -----------------------------
    // View Functions
    // -----------------------------

    /**
     * @notice Get current protocol fee
     * @return feeInBasisPoints Protocol fee (basis points)
     */
    function protocolFee() external view returns (uint256);

    /**
     * @notice Get reserve balance for asset
     * @param asset Token address (address(0) for ETH)
     * @return balance Current reserve amount
     */
    function tokenReserves(address asset) external view returns (uint256);

    /**
     * @notice Get yield protocol configuration
     * @param protocol Protocol address
     * @return config Current yield strategy settings
     */
    function yieldStrategies(
        address protocol
    ) external view returns (YieldConfig memory config);

    // -----------------------------
    // Admin Functions
    // -----------------------------

    /**
     * @notice Update protocol fee percentage
     * @param newFee New fee in basis points
     * @dev Only owner, capped at MAX_PROTOCOL_FEE
     */
    function setProtocolFee(uint256 newFee) external;

    /**
     * @notice Configure yield generation protocol
     * @param protocol Protocol address
     * @param yieldToken Associated yield token
     * @param active Activation status
     * @dev Only owner
     */
    function setYieldProtocol(
        address protocol,
        address yieldToken,
        bool active
    ) external;

    // -----------------------------
    // Emergency Functions
    // -----------------------------

    /**
     * @notice Emergency withdraw funds
     * @param token Token address (address(0) for ETH)
     * @dev Only owner, non-reentrant
     */
    function emergencyWithdraw(address token) external;
}
