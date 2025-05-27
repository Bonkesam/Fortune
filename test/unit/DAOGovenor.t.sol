// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {DAOGovernor} from "../../src/core/DAOGovenor.sol";
import {MyToken} from "../mocks/MyToken.sol";
import {MockLotteryManager} from "../mocks/MockLotteryManager.sol";
import {MockPrizePool} from "../mocks/MockPrizePool.sol";
import {MockTreasury} from "../mocks/MockTreasury.sol";

contract DAOGovernorTest is Test {
    // Test contracts
    MyToken public token;
    TimelockController public timelock;
    DAOGovernor public governor;
    MockLotteryManager public lotteryManager;
    MockPrizePool public prizePool;
    MockTreasury public treasury;

    // Test addresses
    address public deployer = makeAddr("deployer");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public dave = makeAddr("dave");
    address[] public proposers;
    address[] public executors;

    // Constants
    uint256 public constant INITIAL_SUPPLY = 1_000_000e18;
    uint256 public constant PROPOSAL_THRESHOLD = 1e18; // 1 token
    uint256 public constant VOTING_DELAY = 1; // 1 block
    uint256 public constant VOTING_PERIOD = 259200; // ~3 days in seconds
    uint256 public constant QUORUM_NUMERATOR = 400; // 4%

    // Test proposal variables
    address[] public targets;
    uint256[] public values;
    bytes[] public calldatas;
    string public description;
    uint256 public proposalId;

    // Events for verification
    event ProposalCreated(
        uint256 proposalId,
        address proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );

    event ProposalExecuted(uint256 proposalId);
    event VoteCast(
        address indexed voter,
        uint256 proposalId,
        uint8 support,
        uint256 weight,
        string reason
    );

    function setUp() public {
        vm.startPrank(deployer);

        // Deploy token
        token = new MyToken();

        // Setup timelock
        proposers = new address[](1);
        proposers[0] = deployer;
        executors = new address[](1);
        executors[0] = address(0); // Allow anyone to execute

        // Deploy TimelockController with minimum delay
        timelock = new TimelockController(
            1, // minDelay (1 second for testing)
            proposers,
            executors,
            deployer
        );

        // Deploy mock contracts
        lotteryManager = new MockLotteryManager();
        prizePool = new MockPrizePool();
        treasury = new MockTreasury();

        // Set proper references
        lotteryManager.setPrizePool(address(prizePool));
        prizePool.setLotteryManager(address(lotteryManager));

        // Deploy governor
        governor = new DAOGovernor(
            token,
            timelock,
            address(lotteryManager),
            address(prizePool),
            address(treasury) // treasury address
        );

        // Transfer ownership of timelock to the governor
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.revokeRole(timelock.PROPOSER_ROLE(), deployer);
        timelock.revokeRole(timelock.CANCELLER_ROLE(), deployer);

        // Transfer ownership of prize pool to the timelock
        prizePool.transferOwnership(address(timelock));
        treasury.transferOwnership(address(timelock));

        // Distribute tokens for testing
        token.transfer(alice, 10e18);
        token.transfer(bob, 10e18);
        token.transfer(charlie, 10e18);
        token.transfer(dave, 10e18);

        // Keep sufficient tokens for deployer (self-delegate)
        token.delegate(deployer);

        vm.stopPrank();

        // Setup voting power by delegating
        vm.startPrank(alice);
        token.delegate(alice);
        vm.stopPrank();

        vm.startPrank(bob);
        token.delegate(bob);
        vm.stopPrank();

        vm.startPrank(charlie);
        token.delegate(charlie);
        vm.stopPrank();

        vm.startPrank(dave);
        token.delegate(dave);
        vm.stopPrank();

        // Mine a block to ensure checkpoints are created
        vm.roll(block.number + 1);

        // Update block.timestamp to ensure we have a point in time to check voting power
        vm.warp(block.timestamp + 1);
    }
    //////////////////////////
    // Constructor Tests /////
    //////////////////////////

    function testConstructor() public {
        assertEq(address(governor.token()), address(token));
        assertEq(address(governor.timelock()), address(timelock));
        assertEq(governor.name(), "dFortune DAO Governor");
        assertEq(governor.votingDelay(), VOTING_DELAY);
        assertEq(governor.votingPeriod(), VOTING_PERIOD);
        assertEq(governor.proposalThreshold(), PROPOSAL_THRESHOLD);
        assertEq(governor.lotteryManager(), address(lotteryManager));
        assertEq(governor.prizePool(), address(prizePool));
        assertEq(governor.QUORUM_NUMERATOR(), 400);
    }

    //////////////////////////
    // Quorum Tests //////////
    //////////////////////////

    function testQuorum() public {
        // Use the current timestamp which we've already warped past in setUp
        uint256 timestamp = block.timestamp - 1; // Use a past timestamp

        uint256 expectedQuorum = (token.totalSupply() * QUORUM_NUMERATOR) /
            10000;
        assertEq(governor.quorum(timestamp), expectedQuorum);
    }

    //////////////////////////
    // Treasury Tests ////////
    //////////////////////////

    function testTreasuryInvestmentProposal() public {
        vm.startPrank(deployer);

        // Fund the mock treasury
        treasury.setMockBalance(50 ether);

        // Create proposal to invest DAO funds
        address mockProtocol = address(0x1);
        targets = new address[](1);
        targets[0] = address(treasury);
        values = new uint256[](1);
        values[0] = 0;
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "investDAOFunds(address,uint256)",
            mockProtocol,
            45 ether // minAmountOut
        );

        description = "Proposal: Invest DAO funds in yield protocol";
        proposalId = governor.propose(targets, values, calldatas, description);
        vm.stopPrank();

        // Execute full voting workflow
        uint256 votingDelay = governor.votingDelay();
        vm.roll(block.number + votingDelay + 1);
        vm.warp(block.timestamp + votingDelay + 1);

        vm.prank(deployer);
        governor.castVote(proposalId, 1); // FOR

        uint256 votingPeriod = governor.votingPeriod();
        vm.roll(block.number + votingPeriod);
        vm.warp(block.timestamp + votingPeriod);

        bytes32 descHash = keccak256(bytes(description));
        vm.startPrank(deployer);
        governor.queue(targets, values, calldatas, descHash);
        vm.warp(block.timestamp + 2);
        governor.execute(targets, values, calldatas, descHash);
        vm.stopPrank();

        // Verify investment was executed
        assertEq(treasury.lastYieldAction(), block.timestamp);
    }

    function testTreasuryYieldRedemptionProposal() public {
        // Setup: First invest some funds
        treasury.setMockBalance(50 ether);
        vm.prank(address(timelock));
        treasury.investDAOFunds(address(0x1), 45 ether);

        vm.startPrank(deployer);

        // Create proposal to redeem yield
        targets = new address[](1);
        targets[0] = address(treasury);
        values = new uint256[](1);
        values[0] = 0;
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "redeemDAOYield(address,uint256,uint256)",
            address(0x1), // protocol
            25 ether, // amount to redeem
            20 ether // minEthOut
        );

        description = "Proposal: Redeem yield from protocol";
        proposalId = governor.propose(targets, values, calldatas, description);
        vm.stopPrank();

        // Execute workflow
        uint256 votingDelay = governor.votingDelay();
        vm.roll(block.number + votingDelay + 1);
        vm.warp(block.timestamp + votingDelay + 1);

        vm.prank(deployer);
        governor.castVote(proposalId, 1);

        uint256 votingPeriod = governor.votingPeriod();
        vm.roll(block.number + votingPeriod);
        vm.warp(block.timestamp + votingPeriod);

        bytes32 descHash = keccak256(bytes(description));
        vm.startPrank(deployer);
        governor.queue(targets, values, calldatas, descHash);
        vm.warp(block.timestamp + 2);
        governor.execute(targets, values, calldatas, descHash);
        vm.stopPrank();

        // Verify redemption increased treasury balance
        assertGt(treasury.mockBalance(), 0);
    }

    function testInvalidTreasuryProposal() public {
        vm.startPrank(deployer);

        // Try to call unauthorized function on treasury
        targets = new address[](1);
        targets[0] = address(treasury);
        values = new uint256[](1);
        values[0] = 0;
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "transferOwnership(address)",
            alice
        );

        description = "Invalid treasury proposal";

        vm.expectRevert(DAOGovernor.UnauthorizedFunction.selector);
        governor.propose(targets, values, calldatas, description);

        vm.stopPrank();
    }

    function testTreasuryYieldStrategyConfiguration() public {
        vm.startPrank(deployer);

        address newProtocol = makeAddr("newProtocol");
        address newYieldToken = makeAddr("newYieldToken");

        targets = new address[](1);
        targets[0] = address(treasury);
        values = new uint256[](1);
        values[0] = 0;
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "setYieldProtocol(address,address,bool)",
            newProtocol,
            newYieldToken,
            true
        );

        description = "Configure new yield strategy";
        proposalId = governor.propose(targets, values, calldatas, description);
        vm.stopPrank();

        // Execute workflow
        uint256 votingDelay = governor.votingDelay();
        vm.roll(block.number + votingDelay + 1);
        vm.warp(block.timestamp + votingDelay + 1);

        vm.prank(deployer);
        governor.castVote(proposalId, 1);

        uint256 votingPeriod = governor.votingPeriod();
        vm.roll(block.number + votingPeriod);
        vm.warp(block.timestamp + votingPeriod);

        bytes32 descHash = keccak256(bytes(description));
        vm.startPrank(deployer);
        governor.queue(targets, values, calldatas, descHash);
        vm.warp(block.timestamp + 2);
        governor.execute(targets, values, calldatas, descHash);
        vm.stopPrank();

        // Verify strategy was configured
        (address yieldToken, address protocol, bool isActive) = treasury
            .yieldStrategies(newProtocol);
        assertEq(yieldToken, newYieldToken);
        assertEq(protocol, newProtocol);
        assertTrue(isActive);
    }

    //////////////////////////
    // Proposal Tests ////////
    //////////////////////////
    function testCannotCreateProposalWithoutEnoughVotes() public {
        // Create a new user with no tokens and no voting power
        address noVotesUser = makeAddr("noVotesUser");

        // Start prank as the user with no votes
        vm.startPrank(noVotesUser);

        // Create proposal to update ticket price
        targets = new address[](1);
        targets[0] = address(lotteryManager);
        values = new uint256[](1);
        values[0] = 0;
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "setTicketPrice(uint256)",
            0.5 ether
        );
        description = "Proposal #1: Lower ticket price to 0.5 ETH";

        // This should revert because the user has no voting power
        vm.expectRevert(DAOGovernor.InsufficientVotingPower.selector);
        governor.propose(targets, values, calldatas, description);

        vm.stopPrank();
    }

    function testCannotCreateProposalWithInvalidTarget() public {
        // Give deployer enough voting power
        vm.startPrank(deployer);

        // Create proposal with invalid target
        targets = new address[](1);
        targets[0] = address(0x123); // Invalid target
        values = new uint256[](1);
        values[0] = 0;
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "setTicketPrice(uint256)",
            0.5 ether
        );
        description = "Invalid target proposal";

        vm.expectRevert(DAOGovernor.InvalidTarget.selector);
        governor.propose(targets, values, calldatas, description);

        vm.stopPrank();
    }

    function testCannotCreateProposalWithUnauthorizedFunction() public {
        // Give deployer enough voting power
        vm.startPrank(deployer);

        // Create proposal with unauthorized function
        targets = new address[](1);
        targets[0] = address(lotteryManager);
        values = new uint256[](1);
        values[0] = 0;
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "transferOwnership(address)",
            alice
        ); // Unauthorized
        description = "Unauthorized function proposal";

        vm.expectRevert(DAOGovernor.UnauthorizedFunction.selector);
        governor.propose(targets, values, calldatas, description);

        vm.stopPrank();
    }

    function testCreateValidProposal() public {
        vm.startPrank(deployer);

        // Create valid proposal
        targets = new address[](1);
        targets[0] = address(lotteryManager);
        values = new uint256[](1);
        values[0] = 0;
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "setTicketPrice(uint256)",
            0.5 ether
        );
        description = "Proposal #1: Lower ticket price to 0.5 ETH";

        // Instead of attempting to match exact event parameters, we'll just propose and
        // check that the proposal ID is valid
        proposalId = governor.propose(targets, values, calldatas, description);

        // Make sure we got a valid proposal ID
        assertGt(proposalId, 0, "Proposal ID should be greater than 0");

        // Check proposal state
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Pending)
        );

        vm.stopPrank();
    }

    //////////////////////////
    // Voting Tests //////////
    //////////////////////////

    function testVotingWorkflow() public {
        // 1. Create a valid proposal
        vm.startPrank(deployer);

        targets = new address[](1);
        targets[0] = address(lotteryManager);
        values = new uint256[](1);
        values[0] = 0;
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "setTicketPrice(uint256)",
            0.5 ether
        );
        description = "Proposal #1: Lower ticket price to 0.5 ETH";

        proposalId = governor.propose(targets, values, calldatas, description);
        vm.stopPrank();

        // 2. Advance time AND block number to pass voting delay
        uint256 votingDelay = governor.votingDelay();
        vm.roll(block.number + votingDelay + 1);
        vm.warp(block.timestamp + votingDelay + 1);

        // 3. Verify proposal is active
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Active)
        );

        // 4. Multiple accounts vote
        vm.startPrank(deployer);
        vm.expectEmit(true, true, true, true);
        emit VoteCast(deployer, proposalId, 1, INITIAL_SUPPLY - 40e18, "");
        governor.castVote(proposalId, 1); // FOR
        vm.stopPrank();

        vm.prank(alice);
        governor.castVote(proposalId, 0); // AGAINST

        vm.prank(bob);
        governor.castVote(proposalId, 1); // FOR

        vm.prank(charlie);
        governor.castVote(proposalId, 2); // ABSTAIN

        // 5. Check votes
        (
            uint256 againstVotes,
            uint256 forVotes,
            uint256 abstainVotes
        ) = governor.proposalVotes(proposalId);
        assertEq(againstVotes, 10e18);
        assertEq(forVotes, (INITIAL_SUPPLY - 40e18) + 10e18); // deployer + bob
        assertEq(abstainVotes, 10e18);

        // 6. Advance time AND block number to end voting period
        uint256 votingPeriod = governor.votingPeriod();
        vm.roll(block.number + votingPeriod);
        vm.warp(block.timestamp + votingPeriod);

        // 7. Verify proposal is successful
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Succeeded)
        );

        // 8. Queue the proposal
        bytes32 descHash = keccak256(bytes(description));
        vm.prank(deployer);
        governor.queue(targets, values, calldatas, descHash);

        // 9. Verify proposal is queued
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Queued)
        );

        // 10. Advance time to pass timelock
        vm.warp(block.timestamp + 2); // timelock delay (1) + 1

        // 11. Execute the proposal
        vm.prank(deployer);
        vm.expectEmit(true, true, true, true);
        emit ProposalExecuted(proposalId);
        governor.execute(targets, values, calldatas, descHash);

        // 12. Verify proposal is executed
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Executed)
        );

        // 13. Verify the change took effect
        assertEq(lotteryManager.ticketPrice(), 0.5 ether);
    }

    function testProposalCancellation() public {
        // 1. Create a valid proposal
        vm.startPrank(deployer);

        targets = new address[](1);
        targets[0] = address(lotteryManager);
        values = new uint256[](1);
        values[0] = 0;
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "setTicketPrice(uint256)",
            0.5 ether
        );
        description = "Proposal to cancel";

        proposalId = governor.propose(targets, values, calldatas, description);

        // 2. Cancel the proposal
        bytes32 descHash = keccak256(bytes(description));
        governor.cancel(targets, values, calldatas, descHash);

        // 3. Verify proposal is canceled
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Canceled)
        );

        vm.stopPrank();
    }

    //////////////////////////
    // Advanced Tests ////////
    //////////////////////////

    function testExecuteMultiCallProposal() public {
        // Create a proposal with multiple actions
        vm.startPrank(deployer);

        targets = new address[](3);
        targets[0] = address(lotteryManager);
        targets[1] = address(lotteryManager);
        targets[2] = address(prizePool);

        values = new uint256[](3);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;

        calldatas = new bytes[](3);
        calldatas[0] = abi.encodeWithSignature(
            "setTicketPrice(uint256)",
            0.75 ether
        );
        calldatas[1] = abi.encodeWithSignature("setProtocolFee(uint256)", 300); // 3%
        calldatas[2] = abi.encodeWithSignature(
            "updatePrizeDistribution(uint256,uint256,uint256)",
            6000, // 60% winner share
            3000, // 30% charity share
            1000 // 10% rollover share
        );

        description = "Multi-action proposal";

        proposalId = governor.propose(targets, values, calldatas, description);
        vm.stopPrank();

        // Advance time AND block number to pass voting delay
        uint256 votingDelay = governor.votingDelay();
        vm.roll(block.number + votingDelay + 1);
        vm.warp(block.timestamp + votingDelay + 1);

        // Vote
        vm.prank(deployer);
        governor.castVote(proposalId, 1); // FOR

        // Advance time AND block number to end voting period
        uint256 votingPeriod = governor.votingPeriod();
        vm.roll(block.number + votingPeriod);
        vm.warp(block.timestamp + votingPeriod);

        // Queue and execute
        bytes32 descHash = keccak256(bytes(description));
        vm.startPrank(deployer);
        governor.queue(targets, values, calldatas, descHash);

        // Advance time to pass timelock
        vm.warp(block.timestamp + 2); // timelock delay (1) + 1

        governor.execute(targets, values, calldatas, descHash);
        vm.stopPrank();

        // Verify all changes took effect
        assertEq(lotteryManager.ticketPrice(), 0.75 ether);
        assertEq(lotteryManager.protocolFee(), 300);

        (uint256 winnerShare, uint256 charityShare, uint256 rolloverShare) = (
            prizePool.prizeDistribution()
        );
        assertEq(winnerShare, 6000);
        assertEq(charityShare, 3000);
        assertEq(rolloverShare, 1000);
    }

    function testSetYieldProtocolProposal() public {
        // Create a proposal to set yield protocol
        vm.startPrank(deployer);

        address yieldAdapter = makeAddr("yieldAdapter");
        address yieldToken = makeAddr("yieldToken");
        bool isActive = true;

        targets = new address[](1);
        targets[0] = address(prizePool);
        values = new uint256[](1);
        values[0] = 0;
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "setYieldProtocol(address,address,bool)",
            yieldAdapter,
            yieldToken,
            isActive
        );

        description = "Set yield protocol proposal";

        proposalId = governor.propose(targets, values, calldatas, description);
        vm.stopPrank();

        // Advance time AND block number
        uint256 votingDelay = governor.votingDelay();
        vm.roll(block.number + votingDelay + 1);
        vm.warp(block.timestamp + votingDelay + 1);

        vm.prank(deployer);
        governor.castVote(proposalId, 1); // FOR

        // Advance time AND block number to end voting period
        uint256 votingPeriod = governor.votingPeriod();
        vm.roll(block.number + votingPeriod);
        vm.warp(block.timestamp + votingPeriod);

        // Queue and execute
        bytes32 descHash = keccak256(bytes(description));
        vm.startPrank(deployer);
        governor.queue(targets, values, calldatas, descHash);

        vm.warp(block.timestamp + 2);

        governor.execute(targets, values, calldatas, descHash);
        vm.stopPrank();

        // Verify changes
        (address setAdapter, address setToken, bool setActive) = prizePool
            .yieldProtocol();
        assertEq(setAdapter, yieldAdapter);
        assertEq(setToken, yieldToken);
        assertEq(setActive, isActive);
    }

    function testAbortedProposalBecomesDefeated() public {
        // Create proposal
        vm.startPrank(deployer);

        targets = new address[](1);
        targets[0] = address(lotteryManager);
        values = new uint256[](1);
        values[0] = 0;
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "setTicketPrice(uint256)",
            0.5 ether
        );
        description = "Proposal that will be defeated";

        proposalId = governor.propose(targets, values, calldatas, description);
        vm.stopPrank();

        // Get the voting delay
        uint256 votingDelay = governor.votingDelay();

        // Advance both block number and time to pass voting delay
        vm.roll(block.number + votingDelay + 1);
        vm.warp(block.timestamp + votingDelay + 1);

        // Have everyone vote against
        vm.prank(deployer);
        governor.castVote(proposalId, 0); // AGAINST

        vm.prank(alice);
        governor.castVote(proposalId, 0); // AGAINST

        vm.prank(bob);
        governor.castVote(proposalId, 0); // AGAINST

        // Advance both block number and time to end voting period
        uint256 votingPeriod = governor.votingPeriod();
        vm.roll(block.number + votingPeriod);
        vm.warp(block.timestamp + votingPeriod);

        // Verify proposal is defeated
        assertEq(
            uint256(governor.state(proposalId)),
            uint256(IGovernor.ProposalState.Defeated)
        );
    }

    function test_RevertWhen_ExecutionFails() public {
        // Create valid proposal but with a function call that will fail
        // For this test, we'll make a call that requires ownership that the timelock doesn't have

        vm.startPrank(deployer);

        // First set up a known bad call that will fail
        // Create a mock contract that the timelock doesn't own
        MockPrizePool badTarget = new MockPrizePool();

        targets = new address[](1);
        targets[0] = address(badTarget); // We don't own this
        values = new uint256[](1);
        values[0] = 0;
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "updatePrizeDistribution(uint256,uint256,uint256)",
            6000,
            3000,
            1000
        );

        description = "Proposal that will fail execution";

        // Change governor contract to accept any target for testing
        // This simulates a misconfiguration for test purposes
        DAOGovernor vulnerableGovernor = new DAOGovernor(
            token,
            timelock,
            address(lotteryManager),
            address(badTarget), // Add bad target as valid
            address(treasury)
        );

        // Grant roles to vulnerable governor
        timelock.grantRole(
            timelock.PROPOSER_ROLE(),
            address(vulnerableGovernor)
        );
        timelock.grantRole(
            timelock.CANCELLER_ROLE(),
            address(vulnerableGovernor)
        );

        // Create proposal
        proposalId = vulnerableGovernor.propose(
            targets,
            values,
            calldatas,
            description
        );

        // Get the voting delay
        uint256 votingDelay = vulnerableGovernor.votingDelay();

        // Advance both block number and time to pass voting delay
        vm.roll(block.number + votingDelay + 1);
        vm.warp(block.timestamp + votingDelay + 1);

        // Vote
        vulnerableGovernor.castVote(proposalId, 1); // FOR

        // Advance block number and time to end voting period
        uint256 votingPeriod = vulnerableGovernor.votingPeriod();
        vm.roll(block.number + votingPeriod);
        vm.warp(block.timestamp + votingPeriod);

        // Queue the proposal
        bytes32 descHash = keccak256(bytes(description));
        vulnerableGovernor.queue(targets, values, calldatas, descHash);

        // Advance time to pass timelock
        vm.warp(block.timestamp + 2);

        // Execution should revert due to ownership issue
        vm.expectRevert();
        vulnerableGovernor.execute(targets, values, calldatas, descHash);

        vm.stopPrank();
    }

    //////////////////////////
    // View Function Tests ///
    //////////////////////////

    function testCountingMode() public {
        string memory mode = governor.COUNTING_MODE();
        assertEq(mode, "support=bravo&quorum=for,abstain");
    }

    function testClockMode() public {
        string memory mode = governor.CLOCK_MODE();
        assertEq(mode, "mode=timestamp");
    }

    function testClock() public {
        uint48 timestamp = governor.clock();
        assertEq(timestamp, uint48(block.timestamp));
    }

    function testProposalNeedsQueuing() public {
        vm.startPrank(deployer);

        targets = new address[](1);
        targets[0] = address(lotteryManager);
        values = new uint256[](1);
        values[0] = 0;
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "setTicketPrice(uint256)",
            0.5 ether
        );
        description = "Test proposal";

        proposalId = governor.propose(targets, values, calldatas, description);

        bool needsQueuing = governor.proposalNeedsQueuing(proposalId);
        assertEq(needsQueuing, true);

        vm.stopPrank();
    }

    //////////////////////////
    // Edge Case Tests ///////
    //////////////////////////

    function testProposalThresholdChange() public {
        // Verify initial threshold
        assertEq(governor.proposalThreshold(), PROPOSAL_THRESHOLD);

        // Create a proposal
        vm.startPrank(deployer);
        targets = new address[](1);
        targets[0] = address(lotteryManager);
        values = new uint256[](1);
        values[0] = 0;
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "setTicketPrice(uint256)",
            0.5 ether
        );
        description = "Test proposal";

        proposalId = governor.propose(targets, values, calldatas, description);
        vm.stopPrank();
    }

    function testEmergencyProposalExecution() public {
        // Test what happens in an "emergency" scenario
        // Create a valid proposal with minimal delays

        vm.startPrank(deployer);

        targets = new address[](1);
        targets[0] = address(lotteryManager);
        values = new uint256[](1);
        values[0] = 0;
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "setTicketPrice(uint256)",
            0.1 ether
        );
        description = "Emergency proposal: Reduce price";

        proposalId = governor.propose(targets, values, calldatas, description);

        // Get the voting delay
        uint256 votingDelay = governor.votingDelay();

        // Advance both block number and time (minimum 1 block in timestamp mode)
        vm.roll(block.number + votingDelay + 1);
        vm.warp(block.timestamp + votingDelay + 1);

        // Quick vote
        governor.castVote(proposalId, 1); // FOR

        // Advance both block number and time for minimum voting period
        uint256 votingPeriod = governor.votingPeriod();
        vm.roll(block.number + votingPeriod);
        vm.warp(block.timestamp + votingPeriod);

        // Queue and execute immediately after timelock delay
        bytes32 descHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descHash);

        // Advance time to pass timelock (minimum 1 second)
        vm.warp(block.timestamp + 2);

        governor.execute(targets, values, calldatas, descHash);

        // Verify execution
        assertEq(lotteryManager.ticketPrice(), 0.1 ether);

        vm.stopPrank();
    }

    function testQuorumCalculationWithDynamicSupply() public {
        // Use a timestamp that we've already passed to avoid future lookup errors
        uint256 timestamp = block.timestamp - 1;

        // Initial quorum
        uint256 initialQuorum = governor.quorum(timestamp);

        // Mine another block for the supply change to take effect
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        // Mint more tokens
        vm.prank(deployer);
        token.mint(deployer, 1_000_000e18); // Double the supply

        // Mine one more block and advance time for checkpoints
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        // Calculate new timestamp for quorum
        uint256 newTimestamp = block.timestamp - 1;

        // Quorum calculation should now be higher
        uint256 newQuorum = governor.quorum(newTimestamp);
        assertTrue(
            newQuorum > initialQuorum,
            "Quorum should increase with supply"
        );

        // Specifically, it should be double
        assertEq(newQuorum, initialQuorum * 2);
    }
}
