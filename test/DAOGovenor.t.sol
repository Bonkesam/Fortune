// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DAOGovernor} from "../src/core/DAOGovenor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {MyToken} from "./mocks/MyToken.sol";
import {MockLottery} from "./mocks/MockLottery.sol";
import {MockPrizePool} from "./mocks/MockPrizePool.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

contract DAOGovernorTest is Test {
    DAOGovernor governor;
    TimelockController timelock;
    ERC20Votes token;
    MockLottery lottery;
    MockPrizePool prizePool;

    address admin = address(1);
    address voter1 = address(2);
    address voter2 = address(3);

    // Track proposal data
    uint256 proposalId;
    address[] targets;
    uint256[] values;
    bytes[] calldatas;
    bytes32 descriptionHash;

    function setUp() public {
        // Deploy dependencies
        token = new MyToken();
        lottery = new MockLottery();

        prizePool = new MockPrizePool();

        // In OZ v5, the admin needs to be an explicit address with admin rights
        // The admin will then be able to grant roles to others
        timelock = new TimelockController(
            1 days, // min delay
            new address[](0), // initially no proposers
            new address[](0), // initially no executors
            address(this) // This test contract as admin - IMPORTANT!
        );

        // Deploy governor
        governor = new DAOGovernor(
            ERC20Votes(address(token)),
            timelock,
            address(lottery),
            address(prizePool)
        );

        // Now grant roles as admin (which is this contract)
        // Make governor a proposer
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));

        // Set address(0) as executor to allow anyone to execute
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));

        // Set governor as canceller
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        // Setup tokens for voting

        // In setUp() function:

        // Change from 2e18 to 5e22 (50 million tokens)
        deal(address(token), voter1, 5e22);
        deal(address(token), voter2, 3e22);

        // Delegate voting power
        vm.startPrank(voter1);
        token.delegate(voter1);
        vm.stopPrank();

        vm.startPrank(voter2);
        token.delegate(voter2);
        vm.stopPrank();

        // Move the block forward to activate voting power
        // This is crucial in OpenZeppelin v5's ERC20Votes implementation
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        // Set up proposal data for reuse
        targets = new address[](1);
        targets[0] = address(lottery);
        values = new uint256[](1);
        values[0] = 0; // No ETH being sent
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "setTicketPrice(uint256)",
            1 ether
        );
        descriptionHash = keccak256(bytes("Set ticket price"));
    }

    // Helper function to create a valid proposal
    function _createValidProposal() internal returns (uint256) {
        return governor.propose(targets, values, calldatas, "Set ticket price");
    }

    // Test initialization
    function test_Initialization() public {
        // Use a past timestamp for quorum calculation
        uint256 pastTime = block.timestamp - 1;
        vm.warp(pastTime + 1); // Move time forward

        assertEq(
            governor.quorum(pastTime),
            (token.getPastTotalSupply(pastTime) * 400) / 10000
        );
        assertEq(governor.proposalThreshold(), 1e18);
        assertEq(governor.votingDelay(), 1); // 1 block
        assertEq(governor.votingPeriod(), 3 days); // Now checking for 3 days in seconds
        assertEq(address(governor.token()), address(token));
    }
    // Test proposal validation
    function test_ProposalValidation() public {
        // Make sure voter1 has adequate permissions
        assertTrue(
            token.getVotes(voter1) >= governor.proposalThreshold(),
            "Voter1 does not have enough voting power"
        );

        // Valid proposal
        vm.prank(voter1);
        proposalId = _createValidProposal();
        assertTrue(proposalId > 0);

        // Invalid target
        address[] memory invalidTargets = new address[](1);
        invalidTargets[0] = address(this); // this is not a valid target
        uint256[] memory invalidValues = new uint256[](1);
        invalidValues[0] = 0;
        bytes[] memory invalidCalldata = new bytes[](1);
        invalidCalldata[0] = abi.encodeWithSignature(
            "setTicketPrice(uint256)",
            1 ether
        );
        string memory description = "Invalid target";

        vm.prank(voter1);
        vm.expectRevert(DAOGovernor.InvalidTarget.selector);
        governor.propose(
            invalidTargets,
            invalidValues,
            invalidCalldata,
            description
        );
    }

    function test_UnauthorizedFunction() public {
        address[] memory testTargets = new address[](1);
        testTargets[0] = address(lottery);
        uint256[] memory testValues = new uint256[](1);
        testValues[0] = 0;
        bytes[] memory testCalldatas = new bytes[](1);
        testCalldatas[0] = abi.encodeWithSignature("invalidFunction()");
        string memory description = "Invalid function call";

        vm.prank(voter1);
        vm.expectRevert(DAOGovernor.UnauthorizedFunction.selector);
        governor.propose(testTargets, testValues, testCalldatas, description);
    }

    function test_InsufficientVotingPower() public {
        // Create a new address with less than threshold tokens
        address poorVoter = address(0x999);
        deal(address(token), poorVoter, 0.5e18); // Less than threshold

        vm.startPrank(poorVoter);
        token.delegate(poorVoter);
        vm.stopPrank();

        // Advance block to activate voting power (crucial for OZ v5)
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        address[] memory poorTargets = new address[](1);
        poorTargets[0] = address(lottery);
        uint256[] memory poorValues = new uint256[](1);
        poorValues[0] = 0;
        bytes[] memory poorCalldatas = new bytes[](1);
        poorCalldatas[0] = abi.encodeWithSignature(
            "setTicketPrice(uint256)",
            1 ether
        );
        string memory description = "Set ticket price";

        vm.prank(poorVoter); // Use the address with insufficient voting power
        vm.expectRevert(DAOGovernor.InsufficientVotingPower.selector);
        governor.propose(poorTargets, poorValues, poorCalldatas, description);
    }

    // Test full proposal lifecycle - FIXED
    function test_ProposalLifecycle() public {
        // Create proposal
        vm.prank(voter1);
        proposalId = _createValidProposal();

        // Get the starting block and timestamp
        uint256 startBlock = block.number;
        uint256 startTime = block.timestamp;

        // Verify initial state
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Pending),
            "Initial state should be Pending"
        );

        // Get proposal snapshot and deadline
        uint256 proposalSnapshot = governor.proposalSnapshot(proposalId);
        uint256 proposalDeadline = governor.proposalDeadline(proposalId);

        console.log("Proposal snapshot timepoint:", proposalSnapshot);
        console.log("Proposal deadline timepoint:", proposalDeadline);
        console.log("Current timepoint:", governor.clock());

        // Move exactly to the snapshot block
        vm.roll(proposalSnapshot);
        vm.warp(startTime + (proposalSnapshot - startBlock) * 12);

        // Now move to just after the snapshot block to enter Active state
        vm.roll(proposalSnapshot + 1);
        vm.warp(startTime + (proposalSnapshot - startBlock + 1) * 12);

        // Verify active state
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Active),
            "Should be Active after delay"
        );

        // Cast votes - Ensure enough votes to pass quorum
        vm.prank(voter1);
        governor.castVote(proposalId, 1); // For - 2 tokens

        // Important: In OZ v5, voting is more sensitive to exact conditions
        // Let's check voting weight details
        (
            uint256 againstVotes,
            uint256 forVotes,
            uint256 abstainVotes
        ) = governor.proposalVotes(proposalId);
        console.log("Votes FOR:", forVotes);
        console.log("Votes AGAINST:", againstVotes);
        console.log("Votes ABSTAIN:", abstainVotes);

        // Check quorum requirement
        uint256 quorumNeeded = governor.quorum(proposalSnapshot);
        console.log("Quorum required:", quorumNeeded);

        // Move directly to just after the deadline block to complete voting period
        uint256 deadline = governor.proposalDeadline(proposalId);
        vm.warp(deadline + 1); // Move exactly 1 second past deadline

        // Check current state for debugging
        console.log("Current state:", uint256(governor.state(proposalId)));

        // Verify succeeded state
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Succeeded),
            "Should be Succeeded after voting"
        );

        // Queue the proposal
        bytes32 descHash = keccak256(bytes("Set ticket price"));
        governor.queue(targets, values, calldatas, descHash);

        // Verify queued state
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Queued),
            "Should be Queued"
        );

        // Move past the timelock delay
        uint256 minDelay = timelock.getMinDelay();
        vm.warp(block.timestamp + minDelay + 1);

        // Execute the proposal
        governor.execute(targets, values, calldatas, descHash);

        // Final verification
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Executed),
            "Should be Executed"
        );
        assertEq(lottery.ticketPrice(), 1 ether, "Ticket price update failed");
    }

    // Test quorum calculation
    function test_Quorum() public {
        // Need to use a past block number to avoid "future lookup" error in OZ v5
        uint256 timepoint = block.number - 1;
        uint256 expected = (token.getPastTotalSupply(timepoint) * 400) / 10000;
        assertEq(governor.quorum(timepoint), expected);
    }

    // Test cancellation
    function test_CancelProposal() public {
        // In OZ v5, typically only the proposer can cancel their own proposal
        // unless they've lost voting power or a guardian role is set

        // First, create a valid proposal using voter1
        vm.startPrank(voter1);
        proposalId = _createValidProposal();
        vm.stopPrank();

        // Verify the proposal was created successfully
        assertTrue(proposalId > 0);

        // The proposer (voter1) should be able to cancel their own proposal
        vm.prank(voter1);
        governor.cancel(targets, values, calldatas, descriptionHash);

        // Verify the proposal is now in cancelled state
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Canceled),
            "Proposal should be in Canceled state"
        );
    }

    // Test timelock integration - FIXED
    function test_TimelockOperations() public {
        // First, create a proposal using voter1
        vm.prank(voter1);
        proposalId = _createValidProposal();

        // Get the starting block and timestamp
        uint256 startBlock = block.number;
        uint256 startTime = block.timestamp;

        // Verify the proposal was created
        assertTrue(proposalId > 0);

        // Get proposal snapshot and deadline timepoints
        uint256 proposalSnapshot = governor.proposalSnapshot(proposalId);
        uint256 proposalDeadline = governor.proposalDeadline(proposalId);

        console.log("Timelock test - Proposal snapshot:", proposalSnapshot);
        console.log("Timelock test - Proposal deadline:", proposalDeadline);
        console.log("Timelock test - Current timepoint:", governor.clock());

        // Move exactly to the snapshot block
        vm.roll(proposalSnapshot);
        vm.warp(startTime + (proposalSnapshot - startBlock) * 12);

        // Now move to just after the snapshot block to enter Active state
        vm.roll(proposalSnapshot + 1);
        vm.warp(startTime + (proposalSnapshot - startBlock + 1) * 12);

        // Debug information
        console.log(
            "Timelock test - proposal state after delay:",
            uint256(governor.state(proposalId))
        );

        // Cast votes to pass the proposal - voter1 has 2e18 tokens which should be
        // enough to pass the quorum of 4% of the total supply (3e18)
        vm.prank(voter1);
        governor.castVote(proposalId, uint8(1)); // For

        // Print vote counts
        (
            uint256 againstVotes,
            uint256 forVotes,
            uint256 abstainVotes
        ) = governor.proposalVotes(proposalId);
        console.log("Votes FOR:", forVotes);
        console.log("Votes AGAINST:", againstVotes);
        console.log("Votes ABSTAIN:", abstainVotes);

        // Print quorum requirement
        uint256 quorumNeeded = governor.quorum(proposalSnapshot);
        console.log("Quorum required:", quorumNeeded);

        // Debug information
        console.log(
            "Timelock test - after voting - proposal state:",
            uint256(governor.state(proposalId))
        );

        // Skip directly to after the deadline
        vm.roll(proposalDeadline + 1);
        vm.warp(startTime + (proposalDeadline - startBlock + 1) * 12);

        // Debug information
        console.log(
            "Timelock test - after voting period - proposal state:",
            uint256(governor.state(proposalId))
        );

        // Verify the proposal state before queueing
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Succeeded),
            "Proposal should be in Succeeded state before queueing"
        );

        // Queue proposal
        governor.queue(targets, values, calldatas, descriptionHash);

        // In OZ v5, use the specific TimelockController operation hash method
        bytes32 operationId = timelock.hashOperationBatch(
            targets,
            values,
            calldatas,
            bytes32(0), // predecessor
            descriptionHash
        );

        // Verify timelock operation state
        assertTrue(
            timelock.isOperation(operationId),
            "Operation should exist in timelock"
        );
        assertTrue(
            timelock.isOperationPending(operationId),
            "Operation should be pending in timelock"
        );
        assertFalse(
            timelock.isOperationReady(operationId),
            "Operation should not be ready yet"
        );
        assertFalse(
            timelock.isOperationDone(operationId),
            "Operation should not be done yet"
        );

        // Advance time to make operation ready
        vm.warp(block.timestamp + timelock.getMinDelay() + 1);

        // Now operation should be ready
        assertTrue(
            timelock.isOperationReady(operationId),
            "Operation should be ready for execution"
        );

        // Execute the proposal
        governor.execute(targets, values, calldatas, descriptionHash);

        // After execution, operation should be done
        assertTrue(
            timelock.isOperationDone(operationId),
            "Operation should be marked as done"
        );
    }

    // Test clock functions
    function test_ClockFunctions() public {
        // In OZ v5, the clock mode is timestamp
        assertEq(governor.CLOCK_MODE(), "mode=timestamp");
        assertEq(governor.clock(), block.timestamp);
    }
}
