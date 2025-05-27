// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {PrizePool} from "../../src/core/PrizePool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockLotteryManager} from "../mocks/MockLotteryManager.sol";
import {MockAave} from "../mocks/MockAave.sol";
import {MyToken} from "../mocks/MyToken.sol";
import {MockTreasury} from "../mocks/MockTreasury.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PrizePoolTest
 * @dev Comprehensive test suite for PrizePool contract
 */
contract PrizePoolTest is Test {
    // Contracts
    PrizePool public prizePool;
    MockLotteryManager public lotteryManager;
    MockTreasury public mockTreasury;
    MockAave public aave;
    MyToken public aWeth;

    // Test accounts
    address public owner = address(1);
    address public treasuryAddr = address(2);
    address public feeCollector = address(3);
    address public user1 = address(4);
    address public user2 = address(5);
    address public user3 = address(6);
    address public user4 = address(7);

    // Constants
    uint256 public constant PROTOCOL_FEE = 300; // 3%
    uint256 public constant MAX_PROTOCOL_FEE = 500; // 5%
    uint256 public constant LARGE_AMOUNT = 100 ether;
    uint256 public constant STANDARD_DEPOSIT = 10 ether;

    // Events
    event FundsDeposited(uint256 amount, uint256 feeDeducted);
    event PrizesDistributed(uint256 indexed drawId, uint256 totalAmount);
    event YieldGenerated(address indexed protocol, uint256 yieldAmount);
    event EmergencyWithdraw(address indexed token, uint256 amount);
    event ProtocolFeeUpdated(uint256 newFee);

    function setUp() public {
        // Deploy mocks
        lotteryManager = new MockLotteryManager();
        aave = new MockAave();
        aWeth = new MyToken();

        // Deploy MockTreasury instead of using address
        mockTreasury = new MockTreasury();

        // Add aave as an authorized minter for aWeth
        vm.startPrank(address(this));
        aWeth.addMinter(address(aave));
        vm.stopPrank();

        // Set up aave mock to return aWeth tokens when depositing
        aave.setAToken(address(aWeth));

        // Deploy PrizePool with mocked dependencies
        vm.startPrank(owner);
        prizePool = new PrizePool(
            owner,
            address(lotteryManager),
            address(mockTreasury),
            feeCollector,
            PROTOCOL_FEE
        );

        // Configure yield protocol (replace hardcoded Aave address with our mock)

        vm.stopPrank();

        // Fund accounts
        vm.deal(address(lotteryManager), LARGE_AMOUNT);
        vm.deal(user1, LARGE_AMOUNT);
        vm.deal(user2, LARGE_AMOUNT);
        vm.deal(user3, LARGE_AMOUNT);
        vm.deal(user4, LARGE_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testConstructor() public {
        assertEq(prizePool.owner(), owner);
        assertEq(address(prizePool.lotteryManager()), address(lotteryManager));
        assertEq(prizePool.treasury(), address(mockTreasury));
        assertEq(prizePool.feeCollector(), feeCollector);
        assertEq(prizePool.protocolFee(), PROTOCOL_FEE);
    }

    function testConstructorWithZeroAddresses() public {
        vm.startPrank(owner);

        // Test with zero address for manager
        vm.expectRevert();
        new PrizePool(
            owner,
            address(0),
            address(lotteryManager),
            feeCollector,
            PROTOCOL_FEE
        );

        // Test with zero address for manager
        vm.expectRevert("Invalid fee collector");
        new PrizePool(
            owner,
            address(lotteryManager),
            address(mockTreasury),
            address(0),
            PROTOCOL_FEE
        );

        vm.stopPrank();
    }

    function testConstructorWithExcessiveFees() public {
        vm.startPrank(owner);

        // Test with fee exceeding maximum
        vm.expectRevert(PrizePool.InvalidFeeConfiguration.selector);
        new PrizePool(
            owner,
            address(lotteryManager),
            address(mockTreasury),
            feeCollector,
            MAX_PROTOCOL_FEE + 1
        );

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                           DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function testDeposit() public {
        uint256 depositAmount = STANDARD_DEPOSIT;
        uint256 expectedFee = (depositAmount * PROTOCOL_FEE) /
            prizePool.FEE_DENOMINATOR();
        uint256 expectedNet = depositAmount - expectedFee;

        uint256 feeCollectorBalanceBefore = feeCollector.balance;

        vm.startPrank(address(lotteryManager));

        // Test emitted event
        vm.expectEmit(true, true, true, true);
        emit FundsDeposited(depositAmount, expectedFee);

        // Execute deposit
        prizePool.deposit{value: depositAmount}(depositAmount);
        vm.stopPrank();

        // Verify state changes
        assertEq(prizePool.tokenReserves(address(0)), expectedNet);
        assertEq(feeCollector.balance - feeCollectorBalanceBefore, expectedFee);
    }

    function testDepositOnlyManager() public {
        uint256 depositAmount = STANDARD_DEPOSIT;

        // Try deposit from unauthorized address
        vm.startPrank(user1);
        vm.expectRevert(PrizePool.UnauthorizedManager.selector);
        prizePool.deposit{value: depositAmount}(depositAmount);
        vm.stopPrank();
    }

    function testReceiveFunction() public {
        uint256 amount = 1 ether;

        // Successful transfer from manager
        vm.startPrank(address(lotteryManager));
        (bool success, ) = address(prizePool).call{value: amount}("");
        vm.stopPrank();
        assertTrue(success, "Manager deposit should succeed");

        // Failed transfer from non-manager
        vm.startPrank(user1);
        (bool fail, bytes memory data) = address(prizePool).call{value: amount}(
            ""
        );
        vm.stopPrank();

        assertFalse(fail, "Non-manager deposit should fail");
        assertGt(data.length, 0, "Should have revert data");
    }

    /*//////////////////////////////////////////////////////////////
                       PRIZE DISTRIBUTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testDistributePrizes() public {
        // Setup: deposit funds
        uint256 depositAmount = STANDARD_DEPOSIT;
        vm.startPrank(address(lotteryManager));
        prizePool.deposit{value: depositAmount}(depositAmount);
        vm.stopPrank();

        // Calculate expected distribution
        uint256 feeAmount = (depositAmount * PROTOCOL_FEE) /
            prizePool.FEE_DENOMINATOR();
        uint256 netAmount = depositAmount - feeAmount;
        uint256 grandPrize = (netAmount * 7000) / prizePool.FEE_DENOMINATOR();
        uint256 secondaryPrizes = (netAmount * 2000) /
            prizePool.FEE_DENOMINATOR();
        uint256 daoShare = (netAmount * 1000) / prizePool.FEE_DENOMINATOR();

        // Prepare winners
        address[] memory winners = new address[](3);
        winners[0] = user1;
        winners[1] = user2;
        winners[2] = user3;
        uint256 treasuryBalanceBefore = address(mockTreasury).balance;

        // Test emitted event
        uint256 drawId = 123;
        vm.startPrank(address(lotteryManager));
        vm.expectEmit(true, true, true, true);
        emit PrizesDistributed(drawId, netAmount);

        // Distribute prizes
        prizePool.distributePrizes(drawId, winners);
        vm.stopPrank();

        // Verify DAO share went to treasury
        assertEq(
            address(mockTreasury).balance - treasuryBalanceBefore,
            daoShare
        );

        // Verify prizes are set as unclaimed (not directly transferred)
        assertEq(prizePool.unclaimedPrizes(user1), grandPrize);
        assertEq(prizePool.unclaimedPrizes(user2), secondaryPrizes / 2);
        assertEq(prizePool.unclaimedPrizes(user3), secondaryPrizes / 2);

        // Verify distribution storage
        (
            uint256 storedGrandPrize,
            uint256 storedSecondaryPrizes,
            uint256 storedDaoShare
        ) = prizePool.distributions(drawId);
        assertEq(storedGrandPrize, grandPrize);
        assertEq(storedSecondaryPrizes, secondaryPrizes);
        assertEq(storedDaoShare, daoShare);
    }

    function testDistributePrizesOnlyManager() public {
        address[] memory winners = new address[](1);
        winners[0] = user1;

        // Try distribution from unauthorized address
        vm.startPrank(user1);
        vm.expectRevert(PrizePool.UnauthorizedManager.selector);
        prizePool.distributePrizes(1, winners);
        vm.stopPrank();
    }

    function testDistributePrizesWithSingleWinner() public {
        // Setup: deposit funds
        uint256 depositAmount = STANDARD_DEPOSIT;
        vm.startPrank(address(lotteryManager));
        prizePool.deposit{value: depositAmount}(depositAmount);
        vm.stopPrank();

        // Calculate expected distribution
        uint256 feeAmount = (depositAmount * PROTOCOL_FEE) /
            prizePool.FEE_DENOMINATOR();
        uint256 netAmount = depositAmount - feeAmount;
        uint256 grandPrize = (netAmount * 3000) / prizePool.FEE_DENOMINATOR();
        uint256 daoShare = (netAmount * 3000) / prizePool.FEE_DENOMINATOR();

        // Prepare single winner
        address[] memory winners = new address[](1);
        winners[0] = user1;

        // Record balances before
        uint256 treasuryBalanceBefore = address(mockTreasury).balance;

        // Distribute prizes
        vm.startPrank(address(lotteryManager));
        prizePool.distributePrizes(1, winners);
        vm.stopPrank();

        // Verify balances
        assertEq(prizePool.unclaimedPrizes(user1), grandPrize);
        assertEq(
            address(mockTreasury).balance - treasuryBalanceBefore,
            daoShare
        );
    }

    /*//////////////////////////////////////////////////////////////
                       PRIZE CLAIMING TESTS
    //////////////////////////////////////////////////////////////*/

    function testClaimPrize() public {
        // Setup: deposit and distribute prizes
        uint256 depositAmount = STANDARD_DEPOSIT;
        vm.startPrank(address(lotteryManager));
        prizePool.deposit{value: depositAmount}(depositAmount);

        address[] memory winners = new address[](1);
        winners[0] = user1;
        prizePool.distributePrizes(1, winners);
        vm.stopPrank();

        // Calculate expected prize
        uint256 feeAmount = (depositAmount * PROTOCOL_FEE) /
            prizePool.FEE_DENOMINATOR();
        uint256 netAmount = depositAmount - feeAmount;
        uint256 expectedPrize = (netAmount * 3000) /
            prizePool.FEE_DENOMINATOR();

        // Verify unclaimed prize
        assertEq(prizePool.unclaimedPrizes(user1), expectedPrize);

        // Claim prize
        uint256 balanceBefore = user1.balance;
        vm.prank(user1);
        prizePool.claimPrize();

        // Verify claim
        assertEq(user1.balance - balanceBefore, expectedPrize);
        assertEq(prizePool.unclaimedPrizes(user1), 0);
    }

    /*//////////////////////////////////////////////////////////////
                           ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function testSetProtocolFee() public {
        uint256 newFee = 400; // 4%

        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit ProtocolFeeUpdated(newFee);

        prizePool.setProtocolFee(newFee);
        vm.stopPrank();

        assertEq(prizePool.protocolFee(), newFee);
    }

    function testSetProtocolFeeOnlyOwner() public {
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user1
            )
        );
        prizePool.setProtocolFee(400);
        vm.stopPrank();
    }

    function testSetProtocolFeeExceedingMax() public {
        vm.startPrank(owner);
        vm.expectRevert(PrizePool.InvalidFeeConfiguration.selector);
        prizePool.setProtocolFee(MAX_PROTOCOL_FEE + 1);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        TREASURY YIELD TESTS
    //////////////////////////////////////////////////////////////*/

    function testTreasuryYieldInvestment() public {
        // Test that treasury can invest DAO funds
        uint256 investAmount = 10 ether;

        // Fund the treasury
        vm.deal(address(mockTreasury), investAmount);
        mockTreasury.setMockBalance(investAmount);

        // Set yield multiplier on aave
        aave.setYieldMultiplier(105); // 5% yield

        // Invest DAO funds through treasury
        vm.prank(address(mockTreasury));
        mockTreasury.investDAOFunds(address(aave), 0);

        // Verify investment was made
        assertEq(mockTreasury.getInvestedAmount(address(aWeth)), investAmount);
        assertEq(mockTreasury.mockBalance(), 0); // All funds invested
    }

    function testTreasuryYieldRedemption() public {
        // Setup investment first
        uint256 investAmount = 10 ether;
        vm.deal(address(mockTreasury), investAmount);
        mockTreasury.setMockBalance(investAmount);
        mockTreasury.setMockYieldGenerated(1 ether); // 1 ETH yield

        aave.setYieldMultiplier(105);

        vm.prank(address(mockTreasury));
        mockTreasury.investDAOFunds(address(aave), 0);

        // Now redeem with yield
        vm.prank(address(mockTreasury));
        mockTreasury.redeemDAOYield(address(aave), investAmount, 0);

        // Verify redemption with yield
        assertEq(mockTreasury.mockBalance(), investAmount + 1 ether); // Original + yield
        assertEq(mockTreasury.getInvestedAmount(address(aWeth)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function testScheduleEmergencyWithdraw() public {
        // Setup: deposit funds
        uint256 depositAmount = STANDARD_DEPOSIT;
        vm.startPrank(address(lotteryManager));
        prizePool.deposit{value: depositAmount}(depositAmount);
        vm.stopPrank();

        // Schedule emergency withdrawal
        vm.prank(owner);
        prizePool.scheduleEmergencyWithdraw(address(0)); // ETH

        // Verify schedule
        (uint256 scheduledTime, uint256 amount) = prizePool.emergencySchedules(
            address(0)
        );
        assertGt(scheduledTime, block.timestamp);
        assertGt(amount, 0);
    }

    function testExecuteEmergencyWithdraw() public {
        // Setup: deposit funds and schedule withdrawal
        uint256 depositAmount = STANDARD_DEPOSIT;
        vm.startPrank(address(lotteryManager));
        prizePool.deposit{value: depositAmount}(depositAmount);
        vm.stopPrank();

        vm.prank(owner);
        prizePool.scheduleEmergencyWithdraw(address(0));

        // Fast forward time
        vm.warp(block.timestamp + prizePool.EMERGENCY_DELAY() + 1);

        // Execute withdrawal
        uint256 ownerBalanceBefore = owner.balance;
        vm.prank(owner);
        prizePool.executeEmergencyWithdraw(address(0));

        // Verify withdrawal
        assertGt(owner.balance, ownerBalanceBefore);
    }

    /*//////////////////////////////////////////////////////////////
                          OWNERSHIP TESTS
    //////////////////////////////////////////////////////////////*/

    function testOwnershipTransfer() public {
        vm.startPrank(owner);
        prizePool.transferOwnership(user1);
        vm.stopPrank();

        // Verify pending owner
        vm.startPrank(user1);
        prizePool.acceptOwnership();
        vm.stopPrank();

        assertEq(prizePool.owner(), user1);
    }

    /*//////////////////////////////////////////////////////////////
                          CIRCUIT BREAKER TESTS
    //////////////////////////////////////////////////////////////*/

    function testCircuitBreaker() public {
        // Toggle circuit breaker
        vm.prank(owner);
        prizePool.toggleCircuitBreaker();

        // Try to deposit when contract is paused
        vm.startPrank(address(lotteryManager));
        vm.expectRevert("Contract paused");
        prizePool.deposit{value: 1 ether}(1 ether);
        vm.stopPrank();

        // Reactivate
        vm.prank(owner);
        prizePool.toggleCircuitBreaker();

        // Should work now
        vm.startPrank(address(lotteryManager));
        prizePool.deposit{value: 1 ether}(1 ether);
        vm.stopPrank();
    }
}
