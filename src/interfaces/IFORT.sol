// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IFORT
 * @notice Interface for dFortune Governance Token
 * @dev Combines ERC20, ERC20Permit, and ERC20Votes functionality
 */
interface IFORT {
    // -----------------------------
    // ERC20 Core Functions
    // -----------------------------

    /// @notice Transfers tokens to specified address
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice Approves spender to manage tokens
    function approve(address spender, uint256 amount) external returns (bool);

    /// @notice Transfers tokens on behalf of owner
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    // -----------------------------
    // ERC20Permit Functions
    // -----------------------------

    /// @notice Approves via signature for gasless transactions
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    // -----------------------------
    // ERC20Votes Functions
    // -----------------------------

    /// @notice Delegates voting power to another address
    function delegate(address delegatee) external;

    /// @notice Gets current voting power of account
    function getVotes(address account) external view returns (uint256);

    /// @notice Gets past voting power at block number
    function getPastVotes(
        address account,
        uint256 blockNumber
    ) external view returns (uint256);

    // -----------------------------
    // FORT-Specific Functions
    // -----------------------------

    /// @notice Burns tokens from address (MINTER_ROLE only)
    function burn(address from, uint256 amount) external;

    /**
     * @notice Record a user as having placed a bet and award welcome token if first-time
     * @param bettor Address of the bettor to record
     * @return awarded Whether welcome token was awarded
     */
    function recordBettor(address bettor) external returns (bool awarded);

    /**
     * @notice Check if an address has bet before
     * @param account Address to check
     * @return bool Whether address has bet before
     */
    function hasBetBefore(address account) external view returns (bool);

    /**
     * @notice Mint new tokens (MINTER_ROLE only)
     * @param to Recipient address
     * @param amount Amount to mint (in wei)
     */

    function mint(address to, uint256 amount) external;
    // -----------------------------
    // View & Constants
    // -----------------------------

    /// @notice Returns token name
    function name() external view returns (string memory);

    /// @notice Returns token symbol
    function symbol() external view returns (string memory);

    /// @notice Returns token decimals
    function decimals() external view returns (uint8);

    /// @notice Returns total supply
    function totalSupply() external view returns (uint256);

    /// @notice Returns account balance
    function balanceOf(address account) external view returns (uint256);

    /// @notice Returns spending allowance
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    /// @notice Returns maximum token supply
    function MAX_SUPPLY() external view returns (uint256);

    /// @notice Returns total minted tokens
    function totalMinted() external view returns (uint256);

    /// @notice Returns MINTER_ROLE identifier
    function MINTER_ROLE() external pure returns (bytes32);
}
