// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MyToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    constructor()
        ERC20("Test Token", "TEST")
        ERC20Permit("Test Token")
        ERC20Votes()
        Ownable(msg.sender)
    {
        _mint(msg.sender, 1_000_000e18);
    }

    // Mapping to track authorized minters
    mapping(address => bool) public authorizedMinters;

    // Add a modifier to check if an address is authorized to mint
    modifier onlyMinter() {
        require(
            msg.sender == owner() || authorizedMinters[msg.sender],
            "Not authorized to mint"
        );
        _;
    }

    /**
     * @notice Authorize an address to mint tokens
     * @param minter Address to authorize
     */
    function addMinter(address minter) external onlyOwner {
        authorizedMinters[minter] = true;
    }

    /**
     * @notice Remove an address from authorized minters
     * @param minter Address to remove authorization from
     */
    function removeMinter(address minter) external onlyOwner {
        authorizedMinters[minter] = false;
    }

    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    function deal(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyMinter {
        _burn(from, amount);
    }

    // Required overrides for OZ v5
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(
        address owner
    ) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
