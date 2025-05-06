// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title dFortune Proxy
 * @notice Transparent upgradeable proxy with explicit ether handling
 */
contract Proxy is TransparentUpgradeableProxy {
    bytes32 private constant _ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    constructor(
        address _logic,
        address _admin,
        bytes memory _data
    ) TransparentUpgradeableProxy(_logic, _admin, _data) {}

    /**
     * @notice Explicit receive ether function for safe ETH handling
     * @dev Allows the proxy to safely accept ETH transfers
     */
    receive() external payable {}

    function implementation() public view returns (address) {
        return _implementation();
    }

    function admin() public view returns (address adm) {
        assembly {
            adm := sload(_ADMIN_SLOT)
        }
    }
}
