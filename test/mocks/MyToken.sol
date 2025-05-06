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

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function deal(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
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
