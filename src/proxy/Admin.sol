// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Proxy Admin
 * @notice Manages proxy upgrades using OpenZeppelin v5 patterns
 */
contract Admin is Ownable {
    mapping(address => bool) public isProxy;

    event ProxyUpgraded(address indexed proxy, address newImplementation);
    event ProxyAdminChanged(address indexed proxy, address newAdmin);

    constructor(address initialOwner) Ownable(initialOwner) {}

    /**
     * @notice Upgrade proxy implementation (v5-compatible)
     */
    function upgradeProxy(
        TransparentUpgradeableProxy proxy,
        address newImplementation
    ) external onlyOwner {
        require(isProxy[address(proxy)], "Unauthorized proxy");

        // Use low-level call to handle v5 function signature
        (bool success, ) = address(proxy).call(
            abi.encodeWithSignature("upgradeTo(address)", newImplementation)
        );
        require(success, "Upgrade failed");

        emit ProxyUpgraded(address(proxy), newImplementation);
    }

    /**
     * @notice Change proxy admin (v5-compatible)
     */
    function changeProxyAdmin(
        TransparentUpgradeableProxy proxy,
        address newAdmin
    ) external onlyOwner {
        require(isProxy[address(proxy)], "Unauthorized proxy");

        // Use v5-compatible admin change pattern
        (bool success, ) = address(proxy).call(
            abi.encodeWithSignature("changeAdmin(address)", newAdmin)
        );
        require(success, "Admin change failed");

        emit ProxyAdminChanged(address(proxy), newAdmin);
    }

    function addProxy(address proxy) external onlyOwner {
        isProxy[proxy] = true;
    }
}
