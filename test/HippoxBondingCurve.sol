// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Test} from "forge-std/Test.sol";
import {HippoxBondingCurve} from "../src/HippoxBondingCurve.sol";
import {IHippoxBondingCurve} from "../src/interfaces/IHippoxBondingCurve.sol";
/// @title HippoxBondingCurveTest
/// @notice Tests for the pump.fun-style launchpad.
contract HippoxBondingCurveTest is Test {
    HippoxBondingCurve launch;
    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address treasury = makeAddr("treasury");
    // Virtual reserves: 30 SOL and 1,000,000,000 tokens.
    uint256 constant V_SOL = 30e18;
    uint256 constant V_TOKEN = 1_000_000_000e18;
    // Real tokens available to sell: 800,000,000 tokens.
    uint256 constant REAL_TOKEN = 800_000_000e18;
    // Graduate at 85 SOL of real reserves.
    uint256 constant GRAD_THRESHOLD = 85e18;
    function setUp() public {
        launch = new HippoxBondingCurve("Hippox Meme", "HIPM", owner);
        vm.prank(owner);
        launch.configure(V_SOL, V_TOKEN, REAL_TOKEN, GRAD_THRESHOLD, treasury);
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
    }
    // Configuration
    function testConfigureSetsParams() public view {
        assertEq(launch.virtualSolReserves(), V_SOL);
        assertEq(launch.virtualTokenReserves(), V_TOKEN);
        assertEq(launch.realTokenReserves(), REAL_TOKEN);
        assertEq(launch.graduationSolThreshold(), GRAD_THRESHOLD);
        assertEq(launch.treasury(), treasury);
    }
    function testConfigureTwiceReverts() public {
        vm.prank(owner);
        vm.expectRevert("ALREADY_CONFIGURED");
        launch.configure(V_SOL, V_TOKEN, REAL_TOKEN, GRAD_THRESHOLD, treasury);
    }
    function testConfigureOnlyOwner() public {
        HippoxBondingCurve l2 = new HippoxBondingCurve("X", "X", owner);
        vm.prank(alice);
        vm.expectRevert("ONLY_OWNER");
        l2.configure(V_SOL, V_TOKEN, REAL_TOKEN, GRAD_THRESHOLD, treasury);
    }
    function testConfigureRealExceedsVirtualReverts() public {
        HippoxBondingCurve l2 = new HippoxBondingCurve("X", "X", owner);
        vm.prank(owner);
        vm.expectRevert("REAL_GT_VIRTUAL");
        l2.configure(V_SOL, V_TOKEN, V_TOKEN + 1, GRAD_THRESHOLD, treasury);
    }
    // Pricing
    function testInitialPrice() public view {
        // Contract returns virtualSolReserves / virtualTokenReserves.
        // 30e18 / 1e9e18 = 0 due to integer division. Test the raw formula.
        assertEq(launch.currentPrice(), V_SOL / V_TOKEN);
    }
    function testQuoteBuySingleToken() public view {
        uint256 cost = launch.quoteBuy(1e18);
        assertGt(cost, 0, "cost > 0");
        assertLt(cost, 1e12, "cost is small");
    }
    function testQuoteBuyIncreasesWithSize() public view {
        uint256 costSmall = launch.quoteBuy(1_000_000e18);
        uint256 costLarge = launch.quoteBuy(10_000_000e18);
        assertGt(costLarge, costSmall * 10, "larger buy costs more than 10x");
    }
    function testQuoteSellRoughlyInverseOfBuy() public view {
        uint256 tokenAmount = 1_000_000e18;
        uint256 buyCost = launch.quoteBuy(tokenAmount);
        uint256 sellRefund = launch.quoteSell(tokenAmount);
        assertGt(sellRefund, 0, "sell refund > 0");
        assertLt(sellRefund, buyCost, "sell refund < buy cost");
    }
    function testQuoteBuyExceedsRealReservesReverts() public {
        vm.expectRevert("EXCEEDS_REAL_RESERVES");
        launch.quoteBuy(REAL_TOKEN + 1);
    }
    function testQuoteBuyZeroReverts() public {
        vm.expectRevert("ZERO_AMOUNT");
        launch.quoteBuy(0);
    }
    // Buy
    function testBuyMintsTokens() public {
        uint256 tokenAmount = 1_000_000e18;
        uint256 cost = launch.quoteBuy(tokenAmount);
        uint256 before = alice.balance;
        vm.prank(alice);
        launch.buy{value: cost}(tokenAmount);
        assertEq(launch.balanceOf(alice), tokenAmount, "tokens minted");
        assertEq(alice.balance, before - cost, "SOL spent");
        assertEq(launch.realSolReserves(), cost, "real SOL updated");
    }
    function testBuyEmitsEvent() public {
        uint256 tokenAmount = 1_000_000e18;
        uint256 cost = launch.quoteBuy(tokenAmount);
        vm.prank(alice);
        vm.expectEmit(true, false, false, true, address(launch));
        emit IHippoxBondingCurve.TokensPurchased(
            alice,
            tokenAmount,
            cost,
            V_SOL + cost,
            V_TOKEN - tokenAmount
        );
        launch.buy{value: cost}(tokenAmount);
    }
    function testBuyRefundsOverpayment() public {
        uint256 tokenAmount = 1_000_000e18;
        uint256 cost = launch.quoteBuy(tokenAmount);
        uint256 before = alice.balance;
        vm.prank(alice);
        launch.buy{value: cost + 1 ether}(tokenAmount);
        assertEq(alice.balance, before - cost, "overpayment refunded");
    }
    function testBuyInsufficientReverts() public {
        uint256 tokenAmount = 1_000_000e18;
        uint256 cost = launch.quoteBuy(tokenAmount);
        vm.prank(alice);
        vm.expectRevert("INSUFFICIENT_SOL");
        launch.buy{value: cost - 1}(tokenAmount);
    }
    function testBuyZeroReverts() public {
        vm.prank(alice);
        vm.expectRevert("ZERO_AMOUNT");
        launch.buy{value: 1 ether}(0);
    }
    function testBuyIncreasesPrice() public {
        uint256 solBefore = launch.virtualSolReserves();
        uint256 tokenBefore = launch.virtualTokenReserves();
        uint256 tokenAmount = 10_000_000e18;
        uint256 cost = launch.quoteBuy(tokenAmount);
        vm.prank(alice);
        launch.buy{value: cost}(tokenAmount);
        assertGt(launch.virtualSolReserves(), solBefore, "vSol increased");
        assertLt(
            launch.virtualTokenReserves(),
            tokenBefore,
            "vToken decreased"
        );
        assertGt(
            launch.virtualSolReserves() * tokenBefore,
            solBefore * launch.virtualTokenReserves(),
            "price rose"
        );
    }
    // Sell
    function testSellReturnsSOL() public {
        uint256 tokenAmount = 1_000_000e18;
        uint256 cost = launch.quoteBuy(tokenAmount);
        vm.prank(alice);
        launch.buy{value: cost}(tokenAmount);
        uint256 refund = launch.quoteSell(tokenAmount);
        uint256 before = alice.balance;
        vm.prank(alice);
        launch.sell(tokenAmount);
        assertEq(alice.balance, before + refund, "SOL returned");
        assertEq(launch.balanceOf(alice), 0, "tokens burned");
    }
    function testSellEqualsBuyWithoutFees() public {
        uint256 tokenAmount = 1_000_000e18;
        uint256 cost = launch.quoteBuy(tokenAmount);
        vm.prank(alice);
        launch.buy{value: cost}(tokenAmount);
        uint256 refund = launch.quoteSell(tokenAmount);
        assertApproxEqAbs(refund, cost, 1e6, "refund ~= cost without fees");
    }
    function testSellWithoutBalanceReverts() public {
        vm.prank(alice);
        vm.expectRevert("INSUFFICIENT_BALANCE");
        launch.sell(1e18);
    }
    function testSellZeroReverts() public {
        vm.prank(alice);
        vm.expectRevert("ZERO_AMOUNT");
        launch.sell(0);
    }
    // Graduation
    function testGraduatesAtThreshold() public {
        uint256 tokenAmount = 100_000_000e18;
        uint256 cost = launch.quoteBuy(tokenAmount);
        while (cost < GRAD_THRESHOLD) {
            tokenAmount += 10_000_000e18;
            cost = launch.quoteBuy(tokenAmount);
        }
        vm.prank(alice);
        launch.buy{value: cost}(tokenAmount);
        assertTrue(launch.graduated(), "should graduate");
        assertGe(
            launch.realSolReserves(),
            GRAD_THRESHOLD,
            "real SOL >= threshold"
        );
    }
    function testBuyAfterGraduationReverts() public {
        uint256 tokenAmount = 100_000_000e18;
        uint256 cost = launch.quoteBuy(tokenAmount);
        while (cost < GRAD_THRESHOLD) {
            tokenAmount += 10_000_000e18;
            cost = launch.quoteBuy(tokenAmount);
        }
        vm.prank(alice);
        launch.buy{value: cost}(tokenAmount);
        vm.prank(bob);
        vm.expectRevert("GRADUATED");
        launch.buy{value: 1 ether}(1e18);
    }
    function testSellAfterGraduationReverts() public {
        uint256 tokenAmount = 100_000_000e18;
        uint256 cost = launch.quoteBuy(tokenAmount);
        while (cost < GRAD_THRESHOLD) {
            tokenAmount += 10_000_000e18;
            cost = launch.quoteBuy(tokenAmount);
        }
        vm.prank(alice);
        launch.buy{value: cost}(tokenAmount);
        vm.prank(alice);
        vm.expectRevert("GRADUATED");
        launch.sell(1e18);
    }
    // Withdraw
    function testWithdrawProceeds() public {
        uint256 tokenAmount = 1_000_000e18;
        uint256 cost = launch.quoteBuy(tokenAmount);
        vm.prank(alice);
        launch.buy{value: cost}(tokenAmount);
        uint256 treasuryBefore = treasury.balance;
        vm.prank(owner);
        launch.withdrawProceeds(treasury, cost);
        assertEq(treasury.balance, treasuryBefore + cost, "treasury received");
        assertEq(launch.realSolReserves(), 0, "real SOL drained");
    }
    function testWithdrawOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert("ONLY_OWNER");
        launch.withdrawProceeds(treasury, 1e18);
    }
    function testWithdrawExceedsRealSolReverts() public {
        vm.prank(owner);
        vm.expectRevert("EXCEEDS_REAL_SOL");
        launch.withdrawProceeds(treasury, 1e18);
    }
    function testWithdrawToZeroReverts() public {
        vm.prank(owner);
        vm.expectRevert("ZERO_TO");
        launch.withdrawProceeds(address(0), 1e18);
    }
    // Pause
    function testPauseBlocksBuy() public {
        vm.prank(owner);
        launch.setPaused(true);
        vm.prank(alice);
        vm.expectRevert("PAUSED");
        launch.buy{value: 1 ether}(1e18);
    }
    function testPauseBlocksSell() public {
        uint256 tokenAmount = 1_000_000e18;
        uint256 cost = launch.quoteBuy(tokenAmount);
        vm.prank(alice);
        launch.buy{value: cost}(tokenAmount);
        vm.prank(owner);
        launch.setPaused(true);
        vm.prank(alice);
        vm.expectRevert("PAUSED");
        launch.sell(tokenAmount);
    }
    function testUnpauseAllowsBuy() public {
        vm.startPrank(owner);
        launch.setPaused(true);
        launch.setPaused(false);
        vm.stopPrank();
        uint256 tokenAmount = 1_000_000e18;
        uint256 cost = launch.quoteBuy(tokenAmount);
        vm.prank(alice);
        launch.buy{value: cost}(tokenAmount);
        assertEq(launch.balanceOf(alice), tokenAmount);
    }
    function testPauseOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert("ONLY_OWNER");
        launch.setPaused(true);
    }
    // Ownership
    function testTransferOwnership() public {
        vm.prank(owner);
        launch.transferOwnership(alice);
        assertEq(launch.owner(), alice);
        vm.prank(owner);
        vm.expectRevert("ONLY_OWNER");
        launch.setPaused(true);
    }
    function testTransferOwnershipToZeroReverts() public {
        vm.prank(owner);
        vm.expectRevert("ZERO_NEW_OWNER");
        launch.transferOwnership(address(0));
    }
    // Extreme / multi-buyer
    function testMultipleBuyers() public {
        uint256 tokenAmount = 1_000_000e18;
        uint256 cost1 = launch.quoteBuy(tokenAmount);
        vm.prank(alice);
        launch.buy{value: cost1}(tokenAmount);
        uint256 cost2 = launch.quoteBuy(tokenAmount);
        vm.prank(bob);
        launch.buy{value: cost2}(tokenAmount);
        assertGt(cost2, cost1, "second buyer pays more");
        assertEq(launch.balanceOf(alice), tokenAmount);
        assertEq(launch.balanceOf(bob), tokenAmount);
    }
    function testManySmallBuys() public {
        for (uint256 i = 0; i < 10; i++) {
            uint256 tokenAmount = 100_000e18;
            uint256 cost = launch.quoteBuy(tokenAmount);
            vm.prank(alice);
            launch.buy{value: cost}(tokenAmount);
        }
        assertEq(launch.balanceOf(alice), 1_000_000e18);
    }
    function testBuySellBuy() public {
        uint256 tokenAmount = 1_000_000e18;
        uint256 cost1 = launch.quoteBuy(tokenAmount);
        vm.startPrank(alice);
        launch.buy{value: cost1}(tokenAmount);
        launch.sell(tokenAmount);
        uint256 cost2 = launch.quoteBuy(tokenAmount);
        launch.buy{value: cost2}(tokenAmount);
        vm.stopPrank();
        assertEq(
            launch.balanceOf(alice),
            tokenAmount,
            "tokens after round trip"
        );
    }
    function testReceiveRevertsWhenPaused() public {
        vm.prank(owner);
        launch.setPaused(true);
        vm.prank(alice);
        vm.expectRevert("PAUSED");
        (bool ok, ) = address(launch).call{value: 1 ether}("");
        ok;
    }
    function testReceiveRevertsWhenGraduated() public {
        uint256 tokenAmount = 100_000_000e18;
        uint256 cost = launch.quoteBuy(tokenAmount);
        while (cost < GRAD_THRESHOLD) {
            tokenAmount += 10_000_000e18;
            cost = launch.quoteBuy(tokenAmount);
        }
        vm.prank(alice);
        launch.buy{value: cost}(tokenAmount);
        assertTrue(launch.graduated());
        vm.prank(alice);
        vm.expectRevert("GRADUATED");
        (bool ok, ) = address(launch).call{value: 1 ether}("");
        ok;
    }
}
