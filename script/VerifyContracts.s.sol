// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console} from "forge-std/console.sol";

contract VerifyContracts is Script {
    using stdJson for string;

    struct Deployment {
        address fortToken;
        address timelock;
        address governor;
        address treasury;
        address ticketNFT;
        address randomness;
        address prizePool;
        address lotteryManager;
        address loyaltyTracker;
        uint256 chainId;
    }

    function run() external {
        uint256 chainId = vm.envUint("CHAIN_ID");
        string memory fileName = string(
            abi.encodePacked("deployments/", vm.toString(chainId), ".json")
        );

        string memory json = vm.readFile(fileName);
        Deployment memory deployment = abi.decode(
            json.parseRaw("."),
            (Deployment)
        );

        console.log("Starting verification for chain ID:", chainId);

        verifyContract(
            "FORT",
            deployment.fortToken,
            abi.encode(deployment.timelock)
        );
        verifyContract(
            "TimelockController",
            deployment.timelock,
            getTimelockArgs()
        );
        verifyContract(
            "DAOGovernor",
            deployment.governor,
            getGovernorArgs(deployment)
        );
        // Add similar lines for other contracts
    }

    function getTimelockArgs() internal pure returns (bytes memory) {
        return
            abi.encode(
                172800, // minDelay (2 days)
                new address[](0), // proposers (empty)
                new address[](0), // executors (empty)
                address(0) // admin (zero address)
            );
    }

    function getGovernorArgs(
        Deployment memory dep
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                dep.fortToken,
                dep.timelock,
                dep.lotteryManager,
                dep.prizePool,
                dep.treasury
            );
    }

    function verifyContract(
        string memory contractName,
        address contractAddress,
        bytes memory constructorArgs
    ) internal {
        string[] memory command = new string[](10);
        command[0] = "forge";
        command[1] = "verify-contract";
        command[2] = vm.toString(contractAddress);
        command[3] = contractName;
        command[4] = "--chain-id";
        command[5] = vm.toString(vm.envUint("CHAIN_ID"));
        command[6] = "--constructor-args";
        command[7] = vm.toString(constructorArgs);
        command[8] = "--verifier";
        command[9] = "etherscan"; // or blockscout depending on chain

        bytes memory result = vm.ffi(command);
        console.log(string(result));
    }
}
