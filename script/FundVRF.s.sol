// scripts/FundVRF.s.sol
pragma solidity ^0.8.19;
import {Script} from "forge-std/Script.sol";

interface LINK {
    function transferAndCall(
        address,
        uint256,
        bytes calldata
    ) external returns (bool);
}

contract FundVRF is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address coordinator = 0x271682DEB8C4E0901D1a1550aD2e64D568E69909;
        uint64 subId = 123; // Your subscription ID

        // Fund with 10 LINK
        LINK link = LINK(0x514910771AF9Ca656af840dff83E8264EcF986CA);
        bytes memory data = abi.encode(subId);
        link.transferAndCall(coordinator, 10 ether, data);

        vm.stopBroadcast();
    }
}
