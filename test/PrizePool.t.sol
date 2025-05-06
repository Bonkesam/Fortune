// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {PrizePool} from "../src/core/PrizePool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockLotteryManager} from "./mocks/MockLotteryManager.sol";
import {MockAave} from "./mocks/MockAave.sol";
import {MyToken} from "./mocks/MyToken.sol";

/**
 * @title PrizePoolTest
 * @dev Comprehensive test suite for PrizePool contract
 */
contract PrizePoolTest is Test {
    // Contracts
    PrizePool public prizePool;
    MockLotteryManager public lotteryManager;
    MockAave public aave;
    MyToken public aWeth;

    // Test accounts
    address public owner = address(1);
    address public treasury = address(2);
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

        // Set up aave mock to return aWeth tokens when depositing
        aave.setAToken(address(aWeth));

        // Deploy PrizePool with mocked dependencies
        vm.startPrank(owner);
        prizePool = new PrizePool(
            owner,
            address(lotteryManager),
            treasury,
            feeCollector,
            PROTOCOL_FEE
        );

        // Configure yield protocol (replace hardcoded Aave address with our mock)
        address currentAavePool = prizePool.AAVE_POOL();
        prizePool.setYieldProtocol(address(aave), address(aWeth), true);
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
        assertEq(prizePool.treasury(), treasury);
        assertEq(prizePool.feeCollector(), feeCollector);
        assertEq(prizePool.protocolFee(), PROTOCOL_FEE);
    }

    function testConstructorWithZeroAddresses() public {
        vm.startPrank(owner);

        // Test with zero address for manager
        vm.expectRevert();
        new PrizePool(owner, address(0), treasury, feeCollector, PROTOCOL_FEE);

        // Test with zero address for treasury
        vm.expectRevert("Invalid treasury");
        new PrizePool(
            owner,
            address(lotteryManager),
            address(0),
            feeCollector,
            PROTOCOL_FEE
        );

        // Test with zero address for fee collector
        vm.expectRevert("Invalid fee collector");
        new PrizePool(
            owner,
            address(lotteryManager),
            treasury,
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
            treasury,
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

        // Sending ETH from lottery manager should work
        vm.startPrank(address(lotteryManager));
        (bool success, ) = address(prizePool).call{value: amount}("");
        vm.stopPrank();
        assertTrue(success);

        // Sending ETH from any other address should fail
        vm.startPrank(user1);
        vm.expectRevert(PrizePool.UnauthorizedManager.selector);
        (bool fail, ) = address(prizePool).call{value: amount}("");
        vm.stopPrank();
        assertEq(success, false);
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

        // Record balances before
        uint256 user1BalanceBefore = user1.balance;
        uint256 user2BalanceBefore = user2.balance;
        uint256 user3BalanceBefore = user3.balance;
        uint256 treasuryBalanceBefore = treasury.balance;

        // Test emitted event
        uint256 drawId = 123;
        vm.startPrank(address(lotteryManager));
        vm.expectEmit(true, true, true, true);
        emit PrizesDistributed(drawId, netAmount);

        // Distribute prizes
        prizePool.distributePrizes(drawId, winners);
        vm.stopPrank();

        // Verify balances
        assertEq(user1.balance - user1BalanceBefore, grandPrize);
        assertEq(user2.balance - user2BalanceBefore, secondaryPrizes / 2);
        assertEq(user3.balance - user3BalanceBefore, secondaryPrizes / 2);
        assertEq(treasury.balance - treasuryBalanceBefore, daoShare);
        assertEq(prizePool.tokenReserves(address(0)), 0);

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
        uint256 grandPrize = (netAmount * 7000) / prizePool.FEE_DENOMINATOR();
        uint256 daoShare = (netAmount * 1000) / prizePool.FEE_DENOMINATOR();

        // Prepare single winner
        address[] memory winners = new address[](1);
        winners[0] = user1;

        // Record balances before
        uint256 user1BalanceBefore = user1.balance;
        uint256 treasuryBalanceBefore = treasury.balance;

        // Distribute prizes
        vm.startPrank(address(lotteryManager));
        prizePool.distributePrizes(1, winners);
        vm.stopPrank();

        // Verify balances
        assertEq(user1.balance - user1BalanceBefore, grandPrize);
        assertEq(treasury.balance - treasuryBalanceBefore, daoShare);
        assertEq(prizePool.tokenReserves(address(0)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                       YIELD GENERATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testInvestInYield() public {
        // Setup: deposit funds
        uint256 depositAmount = STANDARD_DEPOSIT;
        vm.startPrank(address(lotteryManager));
        prizePool.deposit{value: depositAmount}(depositAmount);
        vm.stopPrank();

        uint256 feeAmount = (depositAmount * PROTOCOL_FEE) /
            prizePool.FEE_DENOMINATOR();
        uint256 netAmount = depositAmount - feeAmount;

        // Configure mock aave to return 105% of deposited amount
        uint256 expectedYield = (netAmount * 105) / 100;
        aave.setYieldMultiplier(105);

        // Test emitted event
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit YieldGenerated(address(aave), 0);

        // Execute investment
        uint256 minAmountOut = netAmount; // 1:1 minimum to prevent slippage
        prizePool.investInYield(address(aave), minAmountOut);
        vm.stopPrank();

        // Verify state changes
        assertEq(prizePool.tokenReserves(address(0)), 0);
        assertEq(prizePool.tokenReserves(address(aWeth)), expectedYield);
        assertEq(aWeth.balanceOf(address(prizePool)), expectedYield);
    }

    function testInvestInYieldOnlyOwner() public {
        // Try to invest from unauthorized address
        vm.startPrank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        prizePool.investInYield(address(aave), 0);
        vm.stopPrank();
    }

    function testInvestInYieldWithInvalidProtocol() public {
        // Setup: deposit funds
        uint256 depositAmount = STANDARD_DEPOSIT;
        vm.startPrank(address(lotteryManager));
        prizePool.deposit{value: depositAmount}(depositAmount);
        vm.stopPrank();

        // Try to invest in non-whitelisted protocol
        vm.startPrank(owner);
        vm.expectRevert(PrizePool.YieldProtocolNotWhitelisted.selector);
        prizePool.investInYield(address(0x123), 0);
        vm.stopPrank();
    }

    function testInvestInYieldWithNoLiquidity() public {
        // Try to invest with no funds in contract
        vm.startPrank(owner);
        vm.expectRevert(PrizePool.InsufficientLiquidity.selector);
        prizePool.investInYield(address(aave), 0);
        vm.stopPrank();
    }

    function testInvestInYieldWithSlippage() public {
        // Setup: deposit funds
        uint256 depositAmount = STANDARD_DEPOSIT;
        vm.startPrank(address(lotteryManager));
        prizePool.deposit{value: depositAmount}(depositAmount);
        vm.stopPrank();

        uint256 feeAmount = (depositAmount * PROTOCOL_FEE) /
            prizePool.FEE_DENOMINATOR();
        uint256 netAmount = depositAmount - feeAmount;

        // Set yield but require high minimum
        aave.setYieldMultiplier(105);

        // Should revert due to slippage protection
        vm.startPrank(owner);
        vm.expectRevert(PrizePool.ExcessiveSlippage.selector);
        prizePool.investInYield(address(aave), netAmount * 2);
        vm.stopPrank();
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

    function testSetYieldProtocol() public {
        address newProtocol = address(0xABCD);
        address newToken = address(0xDEF0);
        bool active = true;

        vm.startPrank(owner);
        prizePool.setYieldProtocol(newProtocol, newToken, active);
        vm.stopPrank();

        // Correctly destructure the tuple return values
        (
            address storedToken,
            address storedProtocol,
            bool storedActive
        ) = prizePool.yieldStrategies(newProtocol);

        assertEq(storedToken, newToken);
        assertEq(storedProtocol, newProtocol);
        assertEq(storedActive, active);
    }

    function testSetYieldProtocolOnlyOwner() public {
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user1
            )
        );
        prizePool.setYieldProtocol(address(0x123), address(0x456), true);
        vm.stopPrank();
    }

    function testSetYieldProtocolWithZeroAddress() public {
        vm.startPrank(owner);
        vm.expectRevert();
        prizePool.setYieldProtocol(address(0), address(0x456), true);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function testEmergencyWithdrawETH() public {
        // Setup: deposit funds
        uint256 depositAmount = STANDARD_DEPOSIT;
        vm.startPrank(address(lotteryManager));
        prizePool.deposit{value: depositAmount}(depositAmount);
        vm.stopPrank();

        uint256 feeAmount = (depositAmount * PROTOCOL_FEE) /
            prizePool.FEE_DENOMINATOR();
        uint256 netAmount = depositAmount - feeAmount;

        uint256 ownerBalanceBefore = owner.balance;

        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit EmergencyWithdraw(address(0), netAmount);

        prizePool.emergencyWithdraw(address(0));
        vm.stopPrank();

        assertEq(owner.balance - ownerBalanceBefore, netAmount);
    }

    function testEmergencyWithdrawToken() public {
        // Setup: mint tokens to contract
        uint256 tokenAmount = 1000 ether;
        aWeth.mint(address(prizePool), tokenAmount);

        uint256 ownerTokenBalanceBefore = aWeth.balanceOf(owner);

        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit EmergencyWithdraw(address(aWeth), tokenAmount);

        prizePool.emergencyWithdraw(address(aWeth));
        vm.stopPrank();

        assertEq(aWeth.balanceOf(owner) - ownerTokenBalanceBefore, tokenAmount);
    }

    function testEmergencyWithdrawOnlyOwner() public {
        vm.startPrank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        prizePool.emergencyWithdraw(address(0));
        vm.stopPrank();
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
}
