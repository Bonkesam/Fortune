// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Proxy Admin
 * @notice Manages proxy upgrades and ownership
 * @dev Separates admin and owner roles for security
 */
contract Admin is Ownable {
    /// @notice Track managed proxies
    mapping(address => bool) public isProxy;

    event ProxyUpgraded(address indexed proxy, address newImplementation);
    event ProxyAdminChanged(address indexed proxy, address newAdmin);

    /**
     * @notice Upgrade proxy implementation
     * @param proxy Proxy contract address
     * @param newImplementation New logic contract
     */
    function upgradeProxy(
        TransparentUpgradeableProxy proxy,
        address newImplementation
    ) external onlyOwner {
        require(isProxy[address(proxy)], "Unauthorized proxy");
        proxy.upgradeTo(newImplementation);
        emit ProxyUpgraded(address(proxy), newImplementation);
    }

    /**
     * @notice Change proxy admin
     * @param proxy Proxy contract address
     * @param newAdmin New admin address
     */
    function changeProxyAdmin(
        TransparentUpgradeableProxy proxy,
        address newAdmin
    ) external onlyOwner {
        require(isProxy[address(proxy)], "Unauthorized proxy");
        proxy.changeAdmin(newAdmin);
        emit ProxyAdminChanged(address(proxy), newAdmin);
    }

    /**
     * @notice Authorize a new proxy
     * @dev Only callable by owner
     */
    function addProxy(address proxy) external onlyOwner {
        isProxy[proxy] = true;
    }
}
