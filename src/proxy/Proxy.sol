// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title dFortune Proxy
 * @notice Delegates calls to implementation contract while preserving storage
 * @dev Uses ERC1967 storage slots for upgrade safety
 */
contract Proxy is ERC1967Proxy {
    constructor(
        address _logic,
        address _admin,
        bytes memory _data
    ) ERC1967Proxy(_logic, _data) {
        _changeAdmin(_admin);
    }

    /**
     * @notice Returns current implementation address
     */
    function implementation() public view returns (address) {
        return _implementation();
    }

    /**
     * @notice Returns current proxy admin
     */
    function admin() public view returns (address) {
        return _getAdmin();
    }
}
