// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// OpenZeppelin contracts
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Core contracts
import {FORT} from "../src/core/FORT.sol";
import {DAOGovernor} from "../src/core/DAOGovenor.sol";
import {Treasury} from "../src/core/Treasury.sol";
import {TicketNFT} from "../src/core/TicketNFT.sol";
import {Randomness} from "../src/core/Randomness.sol";
import {PrizePool} from "../src/core/PrizePool.sol";
import {LotteryManager} from "../src/core/LotteryManager.sol";
import {LoyaltyTracker} from "../src/core/LoyaltyTracker.sol";

// VRF V2.5 Interfaces
interface VRFCoordinatorV2_5 {
    function createSubscription() external returns (uint256 subId);
    function addConsumer(uint256 subId, address consumer) external;
    function fundSubscription(uint256 subId, uint96 amount) external;
}

interface LinkToken {
    function transferAndCall(
        address to,
        uint256 value,
        bytes calldata data
    ) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract DeployAndVerifySystem is Script {
    // Network-specific configurations
    struct NetworkConfig {
        address vrfCoordinator;
        address linkToken;
        bytes32 keyHash;
        uint256 chainId;
        string verifier;
        bool isTestnet;
    }

    mapping(uint256 => NetworkConfig) public networkConfigs;

    struct DeploymentAddresses {
        address fortToken;
        address timelock;
        address governor;
        address treasury;
        address ticketNFT;
        address randomness;
        address prizePool;
        address lotteryManager;
        address loyaltyTracker;
        uint256 vrfSubscriptionId; // Changed from uint64 to uint256 for V2.5
    }

    constructor() {
        // Sepolia Testnet Configuration - Updated for VRF V2.5
        networkConfigs[11155111] = NetworkConfig({
            vrfCoordinator: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B, // VRF V2.5 Coordinator
            linkToken: 0x779877A7B0D9E8603169DdbD7836e478b4624789, // SEPOLIA LINK
            keyHash: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae, // 500 gwei key hash
            chainId: 11155111,
            verifier: "etherscan",
            isTestnet: true
        });

        // Ethereum Mainnet Configuration - Updated for VRF V2.5
        networkConfigs[1] = NetworkConfig({
            vrfCoordinator: 0xD7f86b4b8Cae7D942340FF628F82735b7a20893a, // VRF V2.5 Coordinator Mainnet
            linkToken: 0x514910771AF9Ca656af840dff83E8264EcF986CA, // MAINNET LINK
            keyHash: 0x9fe0eebf5e446e3c998ec9bb19951541aee00bb90ea201ae456421a2ded86805, // 1000 gwei key hash
            chainId: 1,
            verifier: "etherscan",
            isTestnet: false
        });
    }

    function run() external {
        uint256 chainId = block.chainid;
        NetworkConfig memory config = networkConfigs[chainId];

        require(config.chainId != 0, "Unsupported network");

        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("========================================");
        console.log("dFortune System Deployment");
        console.log("========================================");
        console.log(
            "Network:",
            config.isTestnet ? "Sepolia Testnet" : "Mainnet"
        );
        console.log("Chain ID:", chainId);
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance / 1e18, "ETH");
        console.log("VRF Version: V2.5");
        console.log("========================================");

        // Check minimum balance for deployment
        if (config.isTestnet) {
            require(
                deployer.balance >= 0.1 ether,
                "Insufficient ETH for testnet deployment"
            );
        } else {
            require(
                deployer.balance >= 0.5 ether,
                "Insufficient ETH for mainnet deployment"
            );
        }

        vm.startBroadcast(deployerPrivateKey);

        // Deploy all contracts
        DeploymentAddresses memory addrs = deployContracts(config, deployer);

        // Configure the entire system
        configureSystem(addrs, deployer);

        vm.stopBroadcast();

        // Save deployment data
        saveDeployment(addrs, config);

        // Verify contracts on block explorer
        if (vm.envOr("SKIP_VERIFICATION", false) == false) {
            console.log("\n========================================");
            console.log("Starting Contract Verification...");
            console.log("========================================");
            verifyAllContracts(addrs, config);
        } else {
            console.log("\nSkipping verification (SKIP_VERIFICATION=true)");
        }

        console.log("Deployment and verification completed successfully!");
        console.log(
            "Check deployment_%s.json for addresses",
            vm.toString(chainId)
        );
    }

    function deployContracts(
        NetworkConfig memory config,
        address deployer
    ) internal returns (DeploymentAddresses memory addrs) {
        console.log("\n--- Deploying Core Contracts ---");

        // 1. Deploy FORT Token
        addrs.fortToken = address(new FORT(deployer));
        console.log("FORT Token:", addrs.fortToken);
        require(addrs.fortToken != address(0), "FORT deployment failed");

        // 2. Deploy TimelockController
        address[] memory proposers = new address[](1);
        proposers[0] = deployer;
        address[] memory executors = new address[](1);
        executors[0] = deployer;

        addrs.timelock = address(
            new TimelockController(
                config.isTestnet ? 1 hours : 2 days, // Shorter delay for testnet
                proposers,
                executors,
                deployer
            )
        );
        console.log(" TimelockController:", addrs.timelock);
        require(addrs.timelock != address(0), "Timelock deployment failed");

        // 3. Deploy Treasury
        address[] memory initialAssets = new address[](1);
        initialAssets[0] = address(0); // ETH

        addrs.treasury = address(new Treasury(addrs.timelock, initialAssets));
        console.log(" Treasury:", addrs.treasury);
        require(addrs.treasury != address(0), "Treasury deployment failed");

        console.log("\n--- Deploying Lottery System ---");

        // 4. Deploy TicketNFT
        addrs.ticketNFT = address(
            new TicketNFT(
                "dFortune Ticket",
                "dTICKET",
                config.isTestnet
                    ? "https://api.dfortune.io/testnet/tickets/"
                    : "https://api.dfortune.io/tickets/",
                deployer,
                deployer
            )
        );
        console.log(" TicketNFT:", addrs.ticketNFT);
        require(addrs.ticketNFT != address(0), "TicketNFT deployment failed");

        // 5. Deploy Randomness - Note: subscription ID will be set to 0 initially
        addrs.randomness = address(
            new Randomness(
                config.vrfCoordinator,
                config.keyHash,
                0, // Will be set after subscription creation
                deployer,
                deployer
            )
        );
        console.log(" Randomness:", addrs.randomness);
        require(addrs.randomness != address(0), "Randomness deployment failed");

        // 6. Deploy PrizePool
        addrs.prizePool = address(
            new PrizePool(
                deployer,
                deployer,
                addrs.treasury,
                deployer,
                config.isTestnet ? 100 : 200 // 1% fee for testnet, 2% for mainnet
            )
        );
        console.log(" PrizePool:", addrs.prizePool);
        require(addrs.prizePool != address(0), "PrizePool deployment failed");

        // 7. Deploy LotteryManager
        addrs.lotteryManager = address(
            new LotteryManager(
                addrs.ticketNFT,
                addrs.prizePool,
                addrs.randomness,
                addrs.fortToken,
                config.isTestnet ? 0.001 ether : 0.01 ether, // Fixed ticket prices
                config.isTestnet ? 1 hours : 3 days, // Draw periods
                config.isTestnet ? 30 minutes : 6 hours, // Purchase periods
                addrs.timelock
            )
        );
        console.log(" LotteryManager:", addrs.lotteryManager);
        require(
            addrs.lotteryManager != address(0),
            "LotteryManager deployment failed"
        );

        // 8. Deploy LoyaltyTracker
        addrs.loyaltyTracker = address(
            new LoyaltyTracker(addrs.fortToken, addrs.timelock)
        );
        console.log(" LoyaltyTracker:", addrs.loyaltyTracker);
        require(
            addrs.loyaltyTracker != address(0),
            "LoyaltyTracker deployment failed"
        );

        console.log("\n--- Deploying Governance System ---");

        // 9. Deploy DAO Governor
        addrs.governor = address(
            new DAOGovernor(
                FORT(addrs.fortToken),
                TimelockController(payable(addrs.timelock)),
                addrs.lotteryManager,
                addrs.prizePool,
                addrs.treasury
            )
        );
        console.log(" DAOGovernor:", addrs.governor);
        require(addrs.governor != address(0), "DAOGovernor deployment failed");

        console.log("All contracts deployed successfully!");
    }

    function configureSystem(
        DeploymentAddresses memory addrs,
        address deployer
    ) internal {
        console.log("\n--- Configuring System Integration ---");

        // Fetch network configuration
        uint256 chainId = block.chainid;
        NetworkConfig memory config = networkConfigs[chainId];

        // Set LotteryManager in dependencies
        TicketNFT(addrs.ticketNFT).updateLotteryManager(addrs.lotteryManager);
        console.log(" Connected TicketNFT to LotteryManager");

        // Set manager in PrizePool
        PrizePool(payable(addrs.prizePool)).setLotteryManager(
            addrs.lotteryManager
        );
        console.log(" Set LotteryManager in PrizePool");

        // Set manager in Randomness
        Randomness(addrs.randomness).setLotteryManager(addrs.lotteryManager);
        console.log(" Set LotteryManager in Randomness");

        // Grant FORT token roles
        FORT fort = FORT(addrs.fortToken);
        bytes32 minterRole = fort.MINTER_ROLE();
        bytes32 trackerRole = fort.BETTOR_TRACKER_ROLE();

        fort.grantRole(minterRole, addrs.lotteryManager);
        console.log(" Granted MINTER_ROLE to LotteryManager");

        fort.grantRole(trackerRole, addrs.loyaltyTracker);
        console.log(" Granted BETTOR_TRACKER_ROLE to LoyaltyTracker");

        // Check if VRF setup should be skipped
        if (vm.envOr("SKIP_VRF_SETUP", false)) {
            console.log(
                "\n--- Skipping VRF Setup (Manual configuration required) ---"
            );
            console.log(" Please manually:");
            console.log(
                " 1. Create VRF V2.5 subscription at:",
                config.vrfCoordinator
            );
            console.log(" 2. Fund it with LINK tokens");
            console.log(" 3. Add consumer:", addrs.randomness);
            console.log(" 4. Call setSubscriptionId() on Randomness contract");

            // Continue with rest of setup
            finishSystemSetup(addrs, deployer);
            return;
        }

        console.log("\n--- Creating VRF V2.5 Subscription ---");
        VRFCoordinatorV2_5 vrfCoordinator = VRFCoordinatorV2_5(
            config.vrfCoordinator
        );
        LinkToken linkToken = LinkToken(config.linkToken);

        // Get current private key
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // Stop current broadcast
        vm.stopBroadcast();

        // Start new broadcast with specific gas limit for VRF subscription
        vm.startBroadcast{gas: 500000}(deployerPrivateKey);

        uint256 subId;
        try vrfCoordinator.createSubscription() returns (uint256 _subId) {
            subId = _subId;
            addrs.vrfSubscriptionId = subId;
            console.log(" VRF V2.5 Subscription created:", subId);
        } catch Error(string memory reason) {
            console.log(" VRF Subscription creation failed:", reason);
            console.log(" Please manually create subscription and set it up");

            // Stop broadcast and restart normal one
            vm.stopBroadcast();
            vm.startBroadcast(deployerPrivateKey);

            finishSystemSetup(addrs, deployer);
            return;
        } catch {
            console.log(" VRF Subscription creation failed with unknown error");
            console.log(" Please manually create subscription and set it up");

            // Stop broadcast and restart normal one
            vm.stopBroadcast();
            vm.startBroadcast(deployerPrivateKey);

            finishSystemSetup(addrs, deployer);
            return;
        }

        // Stop and restart normal broadcast
        vm.stopBroadcast();
        vm.startBroadcast(deployerPrivateKey);

        // 2. Check LINK balance before attempting to fund
        uint256 linkBalance = linkToken.balanceOf(deployer);
        console.log(" Deployer LINK balance:", linkBalance / 1e18, "LINK");

        if (linkBalance >= 5 ether) {
            // VRF V2.5 might need more LINK
            // Method 1: Try direct funding (V2.5 specific)
            try linkToken.approve(config.vrfCoordinator, 5 ether) {
                console.log(" LINK approval successful");
                try vrfCoordinator.fundSubscription(subId, 5 ether) {
                    console.log(
                        " Funded subscription with 5 LINK via direct funding"
                    );
                } catch {
                    console.log(
                        " Direct funding failed, trying transferAndCall..."
                    );
                    // Method 2: Try transferAndCall (backward compatibility)
                    try
                        linkToken.transferAndCall(
                            config.vrfCoordinator,
                            5 ether,
                            abi.encode(subId)
                        )
                    {
                        console.log(
                            " Funded subscription with 5 LINK via transferAndCall"
                        );
                    } catch {
                        console.log(" WARNING: Both funding methods failed");
                        console.log(
                            " Please manually fund subscription ID:",
                            subId
                        );
                        console.log(
                            " With at least 5 LINK at:",
                            config.vrfCoordinator
                        );
                    }
                }
            } catch {
                console.log(" WARNING: Failed to approve LINK for funding");
                console.log(" Please manually fund subscription ID:", subId);
            }
        } else {
            console.log(
                " WARNING: Insufficient LINK balance to fund subscription"
            );
            console.log(
                " Need at least 5 LINK for V2.5. Please manually fund subscription ID:",
                subId
            );
            console.log(" At coordinator:", config.vrfCoordinator);
        }

        // 3. Set subscription ID in Randomness contract
        try Randomness(addrs.randomness).setSubscriptionId(subId) {
            console.log(" Subscription ID set in Randomness contract");
        } catch {
            console.log(
                " WARNING: Failed to set subscription ID in Randomness contract"
            );
            console.log(
                " Please manually call setSubscriptionId(",
                subId,
                ") on:",
                addrs.randomness
            );
        }

        // 4. Add Randomness contract as consumer
        try vrfCoordinator.addConsumer(subId, addrs.randomness) {
            console.log(" Randomness contract added as consumer");
        } catch {
            console.log(" WARNING: Failed to add Randomness as consumer");
            console.log(" Please manually add consumer:", addrs.randomness);
            console.log(" To subscription ID:", subId);
        }

        finishSystemSetup(addrs, deployer);
    }

    function finishSystemSetup(
        DeploymentAddresses memory addrs,
        address deployer
    ) internal {
        console.log("\n--- Transferring Ownership to Timelock ---");
        // Transfer ownerships to Timelock for decentralization
        transferOwnershipSafe(addrs.fortToken, addrs.timelock, "FORT Token");
        transferOwnershipSafe(addrs.ticketNFT, addrs.timelock, "TicketNFT");
        transferOwnershipSafe(addrs.randomness, addrs.timelock, "Randomness");
        transferOwnershipSafe(
            addrs.loyaltyTracker,
            addrs.timelock,
            "LoyaltyTracker"
        );

        console.log("\n--- Configuring Timelock Governance ---");
        // Configure Timelock roles for proper governance
        configureTimelockRoles(
            TimelockController(payable(addrs.timelock)),
            addrs.governor,
            deployer
        );

        console.log("\n--- Starting First Lottery ---");
        try LotteryManager(addrs.lotteryManager).startNewDraw() {
            console.log(" First lottery draw started");
        } catch {
            console.log(
                " Could not start first lottery - manual start required"
            );
        }

        console.log("System configuration completed!");
    }

    function transferOwnershipSafe(
        address target,
        address newOwner,
        string memory contractName
    ) internal {
        try Ownable(target).owner() returns (address currentOwner) {
            if (currentOwner == msg.sender || currentOwner == address(this)) {
                try Ownable(target).transferOwnership(newOwner) {
                    console.log(
                        " Transferred %s ownership to Timelock",
                        contractName
                    );
                } catch Error(string memory reason) {
                    console.log(
                        " Failed to transfer %s ownership: %s",
                        contractName,
                        reason
                    );
                } catch {
                    console.log(
                        " Failed to transfer %s ownership: Unknown error",
                        contractName
                    );
                }
            } else {
                console.log(
                    " Cannot transfer %s ownership - not current owner",
                    contractName
                );
            }
        } catch {
            console.log(" %s does not implement Ownable pattern", contractName);
        }
    }

    function configureTimelockRoles(
        TimelockController timelock,
        address governor,
        address deployer
    ) internal {
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        // Grant Governor the proposer role
        timelock.grantRole(proposerRole, governor);
        console.log(" Governor granted Timelock proposer role");

        // Allow public execution (address(0))
        timelock.grantRole(executorRole, address(0));
        console.log(" Public execution enabled for Timelock");

        // Revoke deployer's temporary roles
        timelock.revokeRole(proposerRole, deployer);
        timelock.revokeRole(executorRole, deployer);
        console.log(" Deployer's temporary Timelock roles revoked");

        // Transfer admin to Governor for full decentralization
        timelock.grantRole(adminRole, governor);
        timelock.revokeRole(adminRole, deployer);
        console.log(" Timelock admin role transferred to Governor");
    }

    function saveDeployment(
        DeploymentAddresses memory addrs,
        NetworkConfig memory config
    ) internal {
        string memory deploymentData = string(
            abi.encodePacked(
                "{\n",
                '  "network": "',
                config.isTestnet ? "sepolia" : "mainnet",
                '",\n',
                '  "chainId": ',
                vm.toString(config.chainId),
                ",\n",
                '  "vrfVersion": "V2.5",\n',
                '  "timestamp": ',
                vm.toString(block.timestamp),
                ",\n",
                '  "fortToken": "',
                vm.toString(addrs.fortToken),
                '",\n',
                '  "timelock": "',
                vm.toString(addrs.timelock),
                '",\n',
                '  "governor": "',
                vm.toString(addrs.governor),
                '",\n',
                '  "treasury": "',
                vm.toString(addrs.treasury),
                '",\n',
                '  "ticketNFT": "',
                vm.toString(addrs.ticketNFT),
                '",\n',
                '  "randomness": "',
                vm.toString(addrs.randomness),
                '",\n',
                '  "prizePool": "',
                vm.toString(addrs.prizePool),
                '",\n',
                '  "lotteryManager": "',
                vm.toString(addrs.lotteryManager),
                '",\n',
                '  "loyaltyTracker": "',
                vm.toString(addrs.loyaltyTracker),
                '",\n',
                '  "vrfSubscriptionId": ',
                vm.toString(addrs.vrfSubscriptionId),
                ",\n",
                '  "vrfCoordinator": "',
                vm.toString(config.vrfCoordinator),
                '"\n',
                "}"
            )
        );

        string memory fileName = string(
            abi.encodePacked(
                "deployment_",
                vm.toString(config.chainId),
                ".json"
            )
        );

        try vm.writeFile(fileName, deploymentData) {
            console.log("Deployment saved to %s", fileName);
        } catch Error(string memory reason) {
            console.log("Failed to save deployment file: %s", reason);
            console.log("Please manually save deployment addresses");
        } catch {
            console.log("Failed to save deployment file");
            console.log("Please manually save deployment addresses");
        }
    }

    // Verification functions remain the same...
    function verifyAllContracts(
        DeploymentAddresses memory addrs,
        NetworkConfig memory config
    ) internal {
        string memory etherscanApiKey;

        try vm.envString("ETHERSCAN_API_KEY") returns (string memory key) {
            etherscanApiKey = key;
        } catch {
            console.log("ETHERSCAN_API_KEY not set - skipping verification");
            return;
        }

        require(
            bytes(etherscanApiKey).length > 0,
            "ETHERSCAN_API_KEY is empty"
        );

        // Verify contracts in order
        verifyContract(
            "src/core/FORT.sol:FORT",
            addrs.fortToken,
            abi.encode(vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY")))
        );

        verifyContract(
            "@openzeppelin/contracts/governance/TimelockController.sol:TimelockController",
            addrs.timelock,
            getTimelockArgs(config.isTestnet)
        );

        verifyContract(
            "src/core/Treasury.sol:Treasury",
            addrs.treasury,
            getTreasuryArgs(addrs)
        );

        verifyContract(
            "src/core/TicketNFT.sol:TicketNFT",
            addrs.ticketNFT,
            getTicketNFTArgs(config)
        );

        verifyContract(
            "src/core/Randomness.sol:Randomness",
            addrs.randomness,
            getRandomnessArgs(config)
        );

        verifyContract(
            "src/core/PrizePool.sol:PrizePool",
            addrs.prizePool,
            getPrizePoolArgs(addrs, config)
        );

        verifyContract(
            "src/core/LotteryManager.sol:LotteryManager",
            addrs.lotteryManager,
            getLotteryManagerArgs(addrs, config)
        );

        verifyContract(
            "src/core/LoyaltyTracker.sol:LoyaltyTracker",
            addrs.loyaltyTracker,
            getLoyaltyTrackerArgs(addrs)
        );

        verifyContract(
            "src/core/DAOGovenor.sol:DAOGovernor",
            addrs.governor,
            getGovernorArgs(addrs)
        );

        console.log("\n All contracts submitted for verification!");
    }

    function verifyContract(
        string memory contractPath,
        address contractAddress,
        bytes memory constructorArgs
    ) internal {
        NetworkConfig memory config = networkConfigs[block.chainid];
        string memory etherscanApiKey = vm.envString("ETHERSCAN_API_KEY");

        console.log("Verifying:", contractPath);

        string[] memory command = new string[](12);
        command[0] = "forge";
        command[1] = "verify-contract";
        command[2] = vm.toString(contractAddress);
        command[3] = contractPath;
        command[4] = "--chain-id";
        command[5] = vm.toString(config.chainId);
        command[6] = "--constructor-args";
        command[7] = vm.toString(constructorArgs);
        command[8] = "--verifier";
        command[9] = config.verifier;
        command[10] = "--etherscan-api-key";
        command[11] = etherscanApiKey;

        try vm.ffi(command) {
            console.log("    Submitted for verification");
        } catch {
            console.log("    Verification submission failed");
        }
    }

    // Constructor argument helpers (same as before but updated for VRF V2.5)
    function getTimelockArgs(
        bool isTestnet
    ) internal view returns (bytes memory) {
        address deployer = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address[] memory proposers = new address[](1);
        proposers[0] = deployer;
        address[] memory executors = new address[](1);
        executors[0] = deployer;

        return
            abi.encode(
                isTestnet ? 1 hours : 2 days,
                proposers,
                executors,
                deployer
            );
    }

    function getTreasuryArgs(
        DeploymentAddresses memory addrs
    ) internal pure returns (bytes memory) {
        address[] memory initialAssets = new address[](1);
        initialAssets[0] = address(0);
        return abi.encode(addrs.timelock, initialAssets);
    }

    function getTicketNFTArgs(
        NetworkConfig memory config
    ) internal view returns (bytes memory) {
        address deployer = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        return
            abi.encode(
                "dFortune Ticket",
                "dTICKET",
                config.isTestnet
                    ? "https://api.dfortune.io/testnet/tickets/"
                    : "https://api.dfortune.io/tickets/",
                deployer,
                deployer
            );
    }

    function getRandomnessArgs(
        NetworkConfig memory config
    ) internal view returns (bytes memory) {
        address deployer = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        return
            abi.encode(
                config.vrfCoordinator,
                config.keyHash,
                uint256(0),
                deployer,
                deployer
            );
    }

    function getPrizePoolArgs(
        DeploymentAddresses memory addrs,
        NetworkConfig memory config
    ) internal view returns (bytes memory) {
        address deployer = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        return
            abi.encode(
                deployer,
                deployer,
                addrs.treasury,
                deployer,
                config.isTestnet ? 100 : 200
            );
    }

    function getLotteryManagerArgs(
        DeploymentAddresses memory addrs,
        NetworkConfig memory config
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                addrs.ticketNFT,
                addrs.prizePool,
                addrs.randomness,
                addrs.fortToken,
                config.isTestnet ? 0.001 ether : 0.01 ether,
                config.isTestnet ? 1 hours : 3 days,
                config.isTestnet ? 30 minutes : 6 hours,
                addrs.timelock
            );
    }

    function getLoyaltyTrackerArgs(
        DeploymentAddresses memory addrs
    ) internal pure returns (bytes memory) {
        return abi.encode(addrs.fortToken, addrs.timelock);
    }

    function getGovernorArgs(
        DeploymentAddresses memory addrs
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                addrs.fortToken,
                addrs.timelock,
                addrs.lotteryManager,
                addrs.prizePool,
                addrs.treasury
            );
    }
}
