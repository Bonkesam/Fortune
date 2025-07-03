// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVRFProxy {
    function handleVRFRequest(uint256 requestId, uint256 drawId) external;
    function handleVRFResponse(
        uint256 requestId,
        uint256[] calldata randomWords
    ) external;
}
