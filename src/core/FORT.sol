// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20, ERC20Permit, ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title dFortune Governance Token (FORT)
 * @notice ERC20 token with governance voting capabilities and controlled minting
 * @dev Features:
 * - Snapshot-based voting power
 * - Meta-transaction support via ERC20Permit
 * - Role-based minting/burning
 * - DAO-controlled supply
 */
contract FORT is ERC20, ERC20Permit, ERC20Votes, AccessControl {
    /// @notice Role identifier for minting/burning tokens
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Maximum supply cap (100 million tokens)
    uint256 public constant MAX_SUPPLY = 100_000_000 * 1e18;

    /// @notice Track total minted amount
    uint256 public totalMinted;

    /// @dev Custom errors for gas efficiency
    error ExceedsMaxSupply();
    error ZeroAddressProhibited();

    /**
     * @notice Initialize token with governance parameters
     * @param admin Initial admin address (typically DAO timelock)
     */
    constructor(
        address admin
    ) ERC20("dFortune", "FORT") ERC20Permit("dFortune") {
        if (admin == address(0)) revert ZeroAddressProhibited();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    // -----------------------------
    // Token Operations
    // -----------------------------

    /**
     * @notice Mint new tokens (MINTER_ROLE only)
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (totalMinted + amount > MAX_SUPPLY) revert ExceedsMaxSupply();
        totalMinted += amount;
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens from address (MINTER_ROLE only)
     * @param from Address to burn from
     * @param amount Amount to burn
     */
    function burn(address from, uint256 amount) external onlyRole(MINTER_ROLE) {
        _burn(from, amount);
    }

    // -----------------------------
    // Governance Hooks
    // -----------------------------

    /// @dev Update voting power on transfers
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    /// @dev Modified mint for voting power tracking
    function _mint(
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._mint(to, amount);
    }

    /// @dev Modified burn for voting power tracking
    function _burn(
        address account,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._burn(account, amount);
    }

    // -----------------------------
    // View Functions
    // -----------------------------

    /**
     * @notice Get voting power at historical block
     * @param account Voter address
     * @param blockNumber Block number to check
     * @return Voting power at specified block
     */
    function getPastVotes(
        address account,
        uint256 blockNumber
    ) public view returns (uint256) {
        return getPastVotes(account, blockNumber);
    }

    /**
     * @notice Current voting power for account
     * @param account Voter address
     * @return Current voting power
     */
    function getVotes(address account) public view returns (uint256) {
        return getVotes(account);
    }
}
