// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";

/**
 * @title dFortune Governance Token (FORT)
 * @notice ERC20 token with governance voting capabilities and controlled minting
 * @dev Features:
 * - Snapshot-based voting power tracking
 * - Meta-transaction support via ERC20Permit
 * - Role-based minting/burning (MINTER_ROLE)
 * - DAO-controlled supply with hard cap
 * - Secure inheritance structure with OpenZeppelin components
 *
 * Security Features:
 * - Explicit access control for mint/burn operations
 * - Supply cap enforcement
 * - Input validation for zero addresses
 * - Proper function overriding for upgrade safety
 */
contract FORT is ERC20, ERC20Permit, ERC20Votes, AccessControl {
    /// @notice Role identifier for minting/burning tokens
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Role identifier for tracking first-time bettors
    bytes32 public constant BETTOR_TRACKER_ROLE =
        keccak256("BETTOR_TRACKER_ROLE");

    /// @notice Maximum supply cap (100 million tokens with 18 decimals)
    uint256 public constant MAX_SUPPLY = 100_000_000 * 1e18;

    /// @notice Welcome token amount (1 FORT with 18 decimals)
    uint256 public constant WELCOME_TOKEN_AMOUNT = 1 * 1e18;

    /// @notice Track total minted amount to enforce supply cap
    uint256 public totalMinted;

    /// @notice Track which addresses have already bet at least once
    /// @dev This automatically creates a getter function: hasBetBefore(address) returns (bool)
    mapping(address => bool) public hasBetBefore;

    /// @dev Custom errors for gas-efficient reverts
    error ExceedsMaxSupply();
    error ZeroAddressProhibited();
    error InvalidBurnAmount();
    error AlreadyReceivedWelcomeToken();
    error NotAuthorizedBettorTracker();

    /// @dev Events for tracking
    event WelcomeTokenAwarded(address indexed user, uint256 amount);
    event BettorStatusUpdated(address indexed user, bool hasBet);

    //////////////////////////////////////
    /// Constructor & Initialization /////
    //////////////////////////////////////

    /**
     * @notice Deploys the FORT token with initial configuration
     * @param admin Initial admin address (typically DAO timelock)
     * @dev Sets up:
     * - Token metadata (name: "dFortune", symbol: "FORT")
     * - ERC20Permit for meta-transactions
     * - Access control roles
     */
    constructor(
        address admin
    ) ERC20("dFortune", "FORT") ERC20Permit("dFortune") {
        if (admin == address(0)) revert ZeroAddressProhibited();

        // Set up role hierarchy
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    ///////////////////////////////
    /// Bettor Tracking ///////////
    ///////////////////////////////

    /**
     * @notice Record a user as having placed a bet and award welcome token if first-time
     * @param bettor Address of the bettor to record
     * @dev Only callable by addresses with BETTOR_TRACKER_ROLE
     * @return awarded Whether welcome token was awarded
     */
    function recordBettor(address bettor) external returns (bool awarded) {
        if (!hasRole(BETTOR_TRACKER_ROLE, msg.sender))
            revert NotAuthorizedBettorTracker();

        if (bettor == address(0)) revert ZeroAddressProhibited();

        // If first-time bettor, award welcome token
        if (!hasBetBefore[bettor]) {
            hasBetBefore[bettor] = true;

            // Award welcome token if supply cap allows
            if (totalMinted + WELCOME_TOKEN_AMOUNT <= MAX_SUPPLY) {
                totalMinted += WELCOME_TOKEN_AMOUNT;
                _mint(bettor, WELCOME_TOKEN_AMOUNT);

                emit WelcomeTokenAwarded(bettor, WELCOME_TOKEN_AMOUNT);
                emit BettorStatusUpdated(bettor, true);
                return true;
            }

            // Still record bettor status even if we couldn't mint
            emit BettorStatusUpdated(bettor, true);
        }

        return false;
    }

    // NOTE: Removed duplicate hasBetBefore function - the public mapping already provides this functionality

    ///////////////////////////////
    /// Mint/Burn Operations //////
    ///////////////////////////////

    /**
     * @notice Mint new tokens (MINTER_ROLE only)
     * @param to Recipient address
     * @param amount Amount to mint (in wei)
     * @dev Enforces:
     * - MINTER_ROLE access control
     * - Supply cap compliance
     * - Non-zero recipient check
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (to == address(0)) revert ZeroAddressProhibited();
        if (totalMinted + amount > MAX_SUPPLY) revert ExceedsMaxSupply();

        totalMinted += amount;
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens from address (MINTER_ROLE only)
     * @param from Address to burn from
     * @param amount Amount to burn (in wei)
     * @dev Enforces:
     * - MINTER_ROLE access control
     * - Valid burn amount (≤ balance)
     */
    function burn(address from, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (amount == 0 || amount > balanceOf(from)) revert InvalidBurnAmount();
        _burn(from, amount);
    }

    //////////////////////////////////
    /// Governance View Functions ////
    //////////////////////////////////

    /**
     * @notice Get historical voting power
     * @param account Voter address
     * @param blockNumber Block number to check
     * @return uint256 Voting power at specified block
     */
    function getPastVotes(
        address account,
        uint256 blockNumber
    ) public view override(Votes) returns (uint256) {
        // Only allow voting power for accounts that have bet before
        if (!hasBetBefore[account]) {
            return 0;
        }
        return super.getPastVotes(account, blockNumber);
    }

    /**
     * @notice Get current voting power
     * @param account Voter address
     * @return uint256 Current voting power
     */
    function getVotes(
        address account
    ) public view override(Votes) returns (uint256) {
        // Only allow voting power for accounts that have bet before
        if (!hasBetBefore[account]) {
            return 0;
        }
        return super.getVotes(account);
    }

    //////////////////////////////////
    /// Required Overrides ///////////
    //////////////////////////////////

    /**
     * @dev Handle nonces for both ERC20Permit and Votes
     * @param owner Address to check nonces for
     * @return uint256 Current nonce value
     */
    function nonces(
        address owner
    ) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    /**
     * @dev Central state update handler used by ERC20, Votes, and Permit logic
     * @param from Sender address
     * @param to Recipient address
     * @param value Transfer amount
     * @notice Updates balances and voting power on transfers/mint/burn
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }
}
