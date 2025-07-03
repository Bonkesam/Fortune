// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {VRFCoordinatorV2_5} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFCoordinatorV2_5.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {IVRFProxy} from "../interfaces/IVRFProxy.sol";

contract VRFProxy is VRFConsumerBaseV2Plus {
    VRFCoordinatorV2_5 public immutable COORDINATOR;
    address public immutable MAIN_CONTRACT;
    bytes32 public immutable KEY_HASH;
    uint256 public subscriptionId;

    constructor(
        address vrfCoordinator,
        bytes32 keyHash,
        uint256 _subscriptionId,
        address mainContract
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        COORDINATOR = VRFCoordinatorV2_5(vrfCoordinator);
        KEY_HASH = keyHash;
        subscriptionId = _subscriptionId;
        MAIN_CONTRACT = mainContract;
    }

    function requestRandomness(uint256 drawId) external {
        require(msg.sender == MAIN_CONTRACT, "Unauthorized");

        VRFV2PlusClient.RandomWordsRequest memory req = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: KEY_HASH,
                subId: subscriptionId,
                requestConfirmations: 3,
                callbackGasLimit: 500_000,
                numWords: 1,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });

        uint256 requestId = COORDINATOR.requestRandomWords(req);
        IVRFProxy(MAIN_CONTRACT).handleVRFRequest(requestId, drawId);
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) internal override {
        IVRFProxy(MAIN_CONTRACT).handleVRFResponse(requestId, randomWords);
    }

    // Admin functions
    function updateSubscription(uint256 newSubId) external {
        require(msg.sender == MAIN_CONTRACT, "Unauthorized");
        subscriptionId = newSubId;
    }
}
