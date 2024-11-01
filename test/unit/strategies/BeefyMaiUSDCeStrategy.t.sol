// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";

import { BaseTest, IERC20, Vm, console2 } from "../../base/BaseTest.t.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";
import { ICurveLpPool } from "src/interfaces/ICurve.sol";
import { IStrategyWrapper } from "../../interfaces/IStrategyWrapper.sol";

import { MaxApyVault } from "src/MaxApyVault.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { ConvexdETHFrxETHStrategyEvents } from "../../helpers/ConvexdETHFrxETHStrategyEvents.sol";
import "src/helpers/AddressBook.sol";
import { BeefyMaiUSDCeStrategyWrapper } from "../../mock/BeefyMaiUSDCeStrategyWrapper.sol";
import { _1_USDCE } from "test/helpers/Tokens.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

contract BeefyMaiUSDCeStrategyTest is BaseTest, ConvexdETHFrxETHStrategyEvents {
    using SafeTransferLib for address;

    address public TREASURY;
    IStrategyWrapper public strategy;
    BeefyMaiUSDCeStrategyWrapper public implementation;
    MaxApyVault public vaultDeployment;
    IMaxApyVault public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;

    function setUp() public {
        super._setUp("POLYGON");
        vm.rollFork(61_767_099);

        TREASURY = makeAddr("treasury");

        vaultDeployment = new MaxApyVault(users.alice, USDCE_POLYGON, "MaxApyUSDCEVault", "maxUSDCE", TREASURY);

        vault = IMaxApyVault(address(vaultDeployment));

        proxyAdmin = new ProxyAdmin(users.alice);
        implementation = new BeefyMaiUSDCeStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address)",
                address(vault),
                keepers,
                bytes32("MaxApy MAI<>USDCe Strategy"),
                users.alice,
                CURVE_MAI_USDCE_POOL_POLYGON,
                BEEFY_MAI_USDCE_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));

        strategy = IStrategyWrapper(address(_proxy));
        USDCE_POLYGON.safeApprove(address(vault), type(uint256).max);

        vm.label(USDCE_POLYGON, "USDCE_POLYGON");
    }

    /*==================INITIALIZATION TESTS==================*/

    function testBeefyMaiUSDCe__Initialization() public {
        MaxApyVault _vault = new MaxApyVault(users.alice, USDCE_POLYGON, "MaxApyUSDCEVault", "maxUSDCE", TREASURY);

        ProxyAdmin _proxyAdmin = new ProxyAdmin(users.alice);
        BeefyMaiUSDCeStrategyWrapper _implementation = new BeefyMaiUSDCeStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;

        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(_implementation),
            address(_proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address)",
                address(_vault),
                keepers,
                bytes32(abi.encode("MaxApy MAI<>USDCe Strategy")),
                users.alice,
                CURVE_MAI_USDCE_POOL_POLYGON,
                BEEFY_MAI_USDCE_POLYGON
            )
        );

        IStrategyWrapper _strategy = IStrategyWrapper(address(_proxy));
        assertEq(_strategy.vault(), address(_vault));

        assertEq(_strategy.hasAnyRole(address(_vault), _strategy.VAULT_ROLE()), true);
        assertEq(_strategy.underlyingAsset(), USDCE_POLYGON);
        assertEq(IERC20(USDCE_POLYGON).allowance(address(_strategy), address(_vault)), type(uint256).max);
        assertEq(_strategy.hasAnyRole(users.keeper, _strategy.KEEPER_ROLE()), true);
        assertEq(_strategy.hasAnyRole(users.alice, _strategy.ADMIN_ROLE()), true);

        assertEq(_strategy.owner(), users.alice);
        assertEq(_strategy.strategyName(), bytes32(abi.encode("MaxApy MAI<>USDCe Strategy")));

        assertEq(_strategy.curveLpPool(), CURVE_MAI_USDCE_POOL_POLYGON, "hereee");
        assertEq(IERC20(USDCE_POLYGON).allowance(address(_strategy), CURVE_MAI_USDCE_POOL_POLYGON), type(uint256).max);

        assertEq(_proxyAdmin.owner(), users.alice);
        vm.startPrank(address(_proxyAdmin));
        vm.stopPrank();

        vm.startPrank(users.alice);
    }

    /*==================STRATEGY CONFIGURATION TESTS==================*/

    function testBeefyMaiUSDCE__SetEmergencyExit() public {
        vm.stopPrank();
        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setEmergencyExit(2);
        vm.stopPrank();
        vm.startPrank(address(vault));
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setEmergencyExit(2);

        vm.stopPrank();
        vm.startPrank(users.alice);
        vm.expectEmit();
        emit StrategyEmergencyExitUpdated(address(strategy), 2);
        strategy.setEmergencyExit(2);
    }

    function testBeefyMaiUSDCE__SetMinSingleTrade() public {
        vm.stopPrank();
        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setMinSingleTrade(1 * _1_USDCE);

        vm.stopPrank();
        vm.startPrank(address(vault));
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setMinSingleTrade(1 * _1_USDCE);

        vm.stopPrank();
        vm.startPrank(users.alice);
        vm.expectEmit();
        emit MinSingleTradeUpdated(1 * _1_USDCE);
        strategy.setMinSingleTrade(1 * _1_USDCE);
        assertEq(strategy.minSingleTrade(), 1 * _1_USDCE);
    }

    function testBeefyMaiUSDCE__IsActive() public {
        vault.addStrategy(address(strategy), 10_000, 0, 0, 0);
        assertEq(strategy.isActive(), false);

        deal(USDCE_POLYGON, address(strategy), 1 * _1_USDCE);
        assertEq(strategy.isActive(), false);

        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
        vm.stopPrank();

        strategy.divest(IERC20(BEEFY_MAI_USDCE_POLYGON).balanceOf(address(strategy)));
        vm.startPrank(address(strategy));
        IERC20(USDCE_POLYGON).transfer(makeAddr("random"), IERC20(USDCE_POLYGON).balanceOf(address(strategy)));
        assertEq(strategy.isActive(), false);

        deal(USDCE_POLYGON, address(strategy), 1 * _1_USDCE);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
    }

    function testBeefyMaiUSDCE__SetStrategist() public {
        // Negatives
        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setStrategist(address(0));

        vm.startPrank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidZeroAddress()"));
        strategy.setStrategist(address(0));

        // Positives
        address random = makeAddr("random");
        vm.expectEmit();
        emit StrategistUpdated(address(strategy), random);
        strategy.setStrategist(random);
        assertEq(strategy.strategist(), random);
    }

    /*==================STRATEGY CORE LOGIC TESTS==================*/
    function testBeefyMaiUSDCE__InvestmentSlippage() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDCE, users.alice);

        vm.startPrank(users.keeper);

        // Expect revert if output amount is gt amount obtained
        vm.expectRevert(abi.encodeWithSignature("MinOutputAmountNotReached()"));
        strategy.harvest(0, type(uint256).max, address(0), block.timestamp);
    }

    function testBeefyMaiUSDCE__PrepareReturn() public {
        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDCE, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        (uint256 unrealizedProfit, uint256 loss, uint256 debtPayment) = strategy.prepareReturn(1 * _1_USDCE, 0);

        assertEq(loss, 0);
        assertEq(debtPayment, 1 * _1_USDCE);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 60 * _1_USDCE });

        strategy.adjustPosition();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDCE, users.alice);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        assertApproxEq(unrealizedProfit, 60 * _1_USDCE, _1_USDCE);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDCE, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        strategy.triggerLoss(10 * _1_USDCE);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        assertEq(unrealizedProfit, 0);
        assertEq(loss, 10 * _1_USDCE);
        assertEq(debtPayment, 0);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 80 * _1_USDCE });

        strategy.adjustPosition();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDCE, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        assertEq(loss, 0);
        assertEq(debtPayment, 0);
    }

    function testBeefyMaiUSDCE__Invest() public {
        uint256 returned = strategy.invest(0, 0);
        assertEq(returned, 0);
        assertEq(IERC20(BEEFY_MAI_USDCE_POLYGON).balanceOf(address(strategy)), 0);

        vm.expectRevert(abi.encodeWithSignature("NotEnoughFundsToInvest()"));
        returned = strategy.invest(1, 0);

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDCE });
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDCE);

        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDCE);
        strategy.invest(10 * _1_USDCE, 0);

        assertApproxEq(
            expectedShares, IERC20(BEEFY_MAI_USDCE_POLYGON).balanceOf(address(strategy)), expectedShares / 100
        );
    }

    function testBeefyMaiUSDCE__Divest() public {
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDCE });
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDCE);

        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDCE);
        strategy.invest(10 * _1_USDCE, 0);

        assertApproxEq(
            expectedShares, IERC20(BEEFY_MAI_USDCE_POLYGON).balanceOf(address(strategy)), expectedShares / 100
        );

        uint256 strategyBalanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(strategy));
        uint256 amountDivested = strategy.divest(IERC20(BEEFY_MAI_USDCE_POLYGON).balanceOf(address(strategy)));

        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(strategy)), strategyBalanceBefore + amountDivested);
    }

    function testBeefyMaiUSDCE__LiquidatePosition() public {
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDCE });
        (uint256 liquidatedAmount, uint256 loss) = strategy.liquidatePosition(1 * _1_USDCE);
        assertEq(liquidatedAmount, 1 * _1_USDCE);
        assertEq(loss, 0);

        (liquidatedAmount, loss) = strategy.liquidatePosition(10 * _1_USDCE);
        assertEq(liquidatedAmount, 10 * _1_USDCE);
        assertEq(loss, 0);

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 5 * _1_USDCE });
        uint256 invested = strategy.invest(5 * _1_USDCE, 0);

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDCE });

        (liquidatedAmount, loss) = strategy.liquidatePosition(149 * _1_USDCE / 10);

        assertEq(liquidatedAmount, 149 * _1_USDCE / 10);
        assertLt(loss, _1_USDCE / 5);

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 50 * _1_USDCE });
        invested = strategy.invest(50 * _1_USDCE, 0);

        (liquidatedAmount, loss) = strategy.liquidatePosition(498 * _1_USDCE / 10);

        assertEq(liquidatedAmount, 498 * _1_USDCE / 10);
        assertLt(loss, _1_USDCE / 5);
    }

    function testBeefyMaiUSDCE__LiquidateAllPositions() public {
        uint256 snapshotId = vm.snapshot();

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDCE });
        uint256 shares = strategy.sharesForAmount(10 * _1_USDCE);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDCE);
        strategy.invest(10 * _1_USDCE, 0);

        assertApproxEq(IERC20(BEEFY_MAI_USDCE_POLYGON).balanceOf(address(strategy)), shares, shares / 100);

        uint256 strategyBalanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(strategy));
        uint256 amountFreed = strategy.liquidateAllPositions();

        assertApproxEq(amountFreed, 10 * _1_USDCE, 3 * _1_USDCE / 100);

        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(strategy)), strategyBalanceBefore + amountFreed);
        assertEq(IERC20(BEEFY_MAI_USDCE_POLYGON).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 500 * _1_USDCE });
        shares = strategy.sharesForAmount(500 * _1_USDCE);

        vm.expectEmit();
        emit Invested(address(strategy), 500 * _1_USDCE);
        strategy.invest(500 * _1_USDCE, 0);

        assertApproxEq(IERC20(BEEFY_MAI_USDCE_POLYGON).balanceOf(address(strategy)), shares, 1.5 ether);

        strategyBalanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(strategy));
        amountFreed = strategy.liquidateAllPositions();

        assertApproxEq(amountFreed, 500 * _1_USDCE, 2 * _1_USDCE);

        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(strategy)), strategyBalanceBefore + amountFreed);
        assertEq(IERC20(BEEFY_MAI_USDCE_POLYGON).balanceOf(address(strategy)), 0);
    }

    function testBeefyMaiUSDCE__Harvest() public {
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.harvest(0, 0, address(0), block.timestamp);

        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDCE, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, uint128(40 * _1_USDCE), uint128(40 * _1_USDCE), 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);

        strategy.harvest(0, 0, address(0), block.timestamp);

        uint256 expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDCE);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 60 * _1_USDCE);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(strategy)), 0);

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDCE });
        vm.warp(block.timestamp + 1 days);

        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 60 * _1_USDCE);

        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();

        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDCE, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, uint128(40 * _1_USDCE), uint128(40 * _1_USDCE), 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);

        strategy.harvest(0, 0, address(0), block.timestamp);

        expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDCE);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 60 * _1_USDCE);

        vm.startPrank(users.alice);
        strategy.setEmergencyExit(2);

        vm.startPrank(users.keeper);

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDCE });
        vm.warp(block.timestamp + 1 days);

        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 109_884_609);
        assertEq(IERC20(BEEFY_MAI_USDCE_POLYGON).balanceOf(address(strategy)), 0);
        vm.revertTo(snapshotId);

        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDCE);
        vault.deposit(100 * _1_USDCE, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, uint128(40 * _1_USDCE), uint128(40 * _1_USDCE), 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        strategy.harvest(0, 0, address(0), block.timestamp);

        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 60 * _1_USDCE);

        expectedStrategyShareBalance = strategy.sharesForAmount(10 * _1_USDCE);

        vm.startPrank(address(strategy));
        uint256 withdrawn = strategy.divest(expectedStrategyShareBalance);

        IERC20(USDCE_POLYGON).transfer(makeAddr("random"), withdrawn);
        vm.startPrank(users.keeper);

        strategy.harvest(0, 0, address(0), block.timestamp);

        StrategyData memory data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3000);
        assertEq(data.strategyDebtRatio, 3000);
    }

    function testBeefyMaiUSDCE__PreviewLiquidate() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDCE, users.alice);
        vm.startPrank(users.keeper);

        strategy.harvest(0, 0, address(0), block.timestamp);

        vm.stopPrank();
        uint256 expected = strategy.previewLiquidate(30 * _1_USDCE);
        vm.startPrank(address(vault));

        uint256 loss = strategy.liquidate(30 * _1_USDCE);

        assertLe(expected, 30 * _1_USDCE - loss);
    }

    function testBeefyMaiUSDCE__PreviewLiquidate__FUZZY(uint256 amount) public {
        vm.assume(amount > _1_USDCE && amount < 1_000_000 * _1_USDCE);
        deal(USDCE_POLYGON, users.alice, amount);
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(amount, users.alice);
        vm.startPrank(users.keeper);

        strategy.harvest(0, 0, address(0), block.timestamp);

        vm.stopPrank();
        uint256 expected = strategy.previewLiquidate(amount / 3);
        vm.startPrank(address(vault));

        uint256 loss = strategy.liquidate(amount / 3);

        assertLe(expected, ((amount/3) - loss));  
    }

    function testBeefyMaiUSDCE__PreviewLiquidateExact() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDCE, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 requestedAmount = strategy.previewLiquidateExact(30 * _1_USDCE);

        vm.startPrank(address(vault));
        uint256 balanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(vault));

        strategy.liquidateExact(30 * _1_USDCE);
        uint256 withdrawn = IERC20(USDCE_POLYGON).balanceOf(address(vault)) - balanceBefore;

        // withdraw exactly what requested
        assertEq(withdrawn, 30 * _1_USDCE);
        // losses are equal or fewer than expected
        assertLe(withdrawn - 30 * _1_USDCE, requestedAmount - 30 * _1_USDCE);
    }

    function testBeefyMaiUSDCE__maxLiquidateExact() public {
        vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDCE, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 maxLiquidateExact = strategy.maxLiquidateExact();
        uint256 balanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(vault));
        uint256 requestedAmount = strategy.previewLiquidateExact(maxLiquidateExact);
        vm.startPrank(address(vault));
        uint256 losses = strategy.liquidateExact(maxLiquidateExact);
        uint256 withdrawn = IERC20(USDCE_POLYGON).balanceOf(address(vault)) - balanceBefore;
        // withdraw exactly what requested
        assertEq(withdrawn, maxLiquidateExact);
        // losses are equal or fewer than expected
        assertLe(losses, requestedAmount - maxLiquidateExact);
    }

    function testBeefyMaiUSDCE__MaxLiquidate() public {
        vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDCE, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 maxWithdraw = strategy.maxLiquidate();
        uint256 balanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(vault));
        vm.startPrank(address(vault));
        strategy.liquidate(maxWithdraw);
        uint256 withdrawn = IERC20(USDCE_POLYGON).balanceOf(address(vault)) - balanceBefore;
        assertLe(withdrawn, maxWithdraw);
    }

    function testBeefyMaiUSDCE___SimulateHarvest() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDCE, users.alice);
        vm.startPrank(users.keeper);
        (uint256 expectedBalance, uint256 outputAfterInvestment,,,,) = strategy.simulateHarvest();
        strategy.harvest(expectedBalance, outputAfterInvestment, address(0), block.timestamp);
    }
}
