// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

import { BaseTest, IERC20, Vm, console2 } from "../../base/BaseTest.t.sol";

import { IStrategyWrapper } from "../../interfaces/IStrategyWrapper.sol";
import { ICurveLpPool } from "src/interfaces/ICurve.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";

import { ConvexdETHFrxETHStrategyEvents } from "../../helpers/ConvexdETHFrxETHStrategyEvents.sol";

import { BeefythUSDDAIUSDCUSDTStrategyWrapper } from "../../mock/BeefythUSDDAIUSDCUSDTStrategyWrapper.sol";

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { MaxApyVault } from "src/MaxApyVault.sol";
import "src/helpers/AddressBook.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { _1_USDC } from "test/helpers/Tokens.sol";

contract BeefythUSDDAIUSDCUSDTStrategyTest is BaseTest, ConvexdETHFrxETHStrategyEvents {
    using SafeTransferLib for address;

    address public TREASURY;
    IStrategyWrapper public strategy;
    BeefythUSDDAIUSDCUSDTStrategyWrapper public implementation;
    MaxApyVault public vaultDeployment;
    IMaxApyVault public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;

    function setUp() public {
        super._setUp("MAINNET");
        vm.rollFork(21_367_091);

        TREASURY = makeAddr("treasury");

        vaultDeployment = new MaxApyVault(users.alice, USDC_MAINNET, "MaxApyUSDCVault", "maxUSDC", TREASURY);

        vault = IMaxApyVault(address(vaultDeployment));

        proxyAdmin = new ProxyAdmin(users.alice);
        implementation = new BeefythUSDDAIUSDCUSDTStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address,address,address)",
                address(vault),
                keepers,
                bytes32("MaxApy thUSDDAIUSDCUSDT Strategy"),
                users.alice,
                CURVE_THUSD_DAI_USDC_USDT_MAINNET,
                BEEFY_THUSD_DAI_USDC_USDT_MAINNET,
                CURVE_3POOL_POOL_MAINNET,
                CRV3POOL_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));

        strategy = IStrategyWrapper(address(_proxy));
        USDC_MAINNET.safeApprove(address(vault), type(uint256).max);

        vm.label(USDC_MAINNET, "USDC_MAINNET");
    }

    /*==================INITIALIZATION TESTS==================*/

    function testBeefythUSDDAIUSDCUSDT__Initialization() public {
        MaxApyVault _vault = new MaxApyVault(users.alice, USDC_MAINNET, "MaxApyUSDCVault", "maxUSDC", TREASURY);

        ProxyAdmin _proxyAdmin = new ProxyAdmin(users.alice);
        BeefythUSDDAIUSDCUSDTStrategyWrapper _implementation = new BeefythUSDDAIUSDCUSDTStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;

        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(_implementation),
            address(_proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address,address,address)",
                address(_vault),
                keepers,
                bytes32("MaxApy thUSDDAIUSDCUSDT Strategy"),
                users.alice,
                CURVE_THUSD_DAI_USDC_USDT_MAINNET,
                BEEFY_THUSD_DAI_USDC_USDT_MAINNET,
                CURVE_3POOL_POOL_MAINNET,
                CRV3POOL_MAINNET
            )
        );

        IStrategyWrapper _strategy = IStrategyWrapper(address(_proxy));
        assertEq(_strategy.vault(), address(_vault));

        assertEq(_strategy.hasAnyRole(address(_vault), _strategy.VAULT_ROLE()), true);
        assertEq(_strategy.underlyingAsset(), USDC_MAINNET);
        assertEq(IERC20(USDC_MAINNET).allowance(address(_strategy), address(_vault)), type(uint256).max);
        assertEq(_strategy.hasAnyRole(users.keeper, _strategy.KEEPER_ROLE()), true);
        assertEq(_strategy.hasAnyRole(users.alice, _strategy.ADMIN_ROLE()), true);

        assertEq(_strategy.owner(), users.alice);
        assertEq(_strategy.strategyName(), bytes32("MaxApy thUSDDAIUSDCUSDT Strategy"));

        assertEq(_strategy.curveLpPool(), CURVE_THUSD_DAI_USDC_USDT_MAINNET, "hereee");
        assertEq(_strategy.curveTriPool(), CURVE_3POOL_POOL_MAINNET, "hereee");
        assertEq(IERC20(USDC_MAINNET).allowance(address(_strategy), CURVE_3POOL_POOL_MAINNET), type(uint256).max);

        assertEq(_proxyAdmin.owner(), users.alice);
        vm.startPrank(address(_proxyAdmin));
        vm.stopPrank();

        vm.startPrank(users.alice);
    }

    /*==================STRATEGY CONFIGURATION TESTS==================*/

    function testBeefythUSDDAIUSDCUSDT__SetEmergencyExit() public {
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

    function testBeefythUSDDAIUSDCUSDT__SetMinSingleTrade() public {
        vm.stopPrank();
        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setMinSingleTrade(1 * _1_USDC);

        vm.stopPrank();
        vm.startPrank(address(vault));
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setMinSingleTrade(1 * _1_USDC);

        vm.stopPrank();
        vm.startPrank(users.alice);
        vm.expectEmit();
        emit MinSingleTradeUpdated(1 * _1_USDC);
        strategy.setMinSingleTrade(1 * _1_USDC);
        assertEq(strategy.minSingleTrade(), 1 * _1_USDC);
    }

    function testBeefythUSDDAIUSDCUSDT__IsActive() public {
        vault.addStrategy(address(strategy), 10_000, 0, 0, 0);
        assertEq(strategy.isActive(), false);

        deal(USDC_MAINNET, address(strategy), 1 * _1_USDC);
        assertEq(strategy.isActive(), false);

        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
        vm.stopPrank();

        strategy.divest(IERC20(BEEFY_THUSD_DAI_USDC_USDT_MAINNET).balanceOf(address(strategy)));
        vm.startPrank(address(strategy));
        IERC20(USDC_MAINNET).transfer(makeAddr("random"), IERC20(USDC_MAINNET).balanceOf(address(strategy)));
        assertEq(strategy.isActive(), false);

        deal(USDC_MAINNET, address(strategy), 1 * _1_USDC);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
    }

    function testBeefythUSDDAIUSDCUSDT__SetStrategist() public {
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
    function testBeefythUSDDAIUSDCUSDT__InvestmentSlippage() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);

        // Expect revert if output amount is gt amount obtained
        vm.expectRevert(abi.encodeWithSignature("MinOutputAmountNotReached()"));
        strategy.harvest(0, type(uint256).max, address(0), block.timestamp);
    }

    function testBeefythUSDDAIUSDCUSDT__PrepareReturn() public {
        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDC, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        (uint256 unrealizedProfit, uint256 loss, uint256 debtPayment) = strategy.prepareReturn(1 * _1_USDC, 0);

        assertEq(loss, 0);
        assertEq(debtPayment, 1 * _1_USDC);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();
        deal({ token: USDC_MAINNET, to: address(strategy), give: 60 * _1_USDC });

        strategy.adjustPosition();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDC, users.alice);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        assertApproxEq(unrealizedProfit, 60 * _1_USDC, 1 * _1_USDC);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDC, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        strategy.triggerLoss(10 * _1_USDC);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        assertEq(unrealizedProfit, 0);
        assertEq(loss, 10 * _1_USDC);
        assertEq(debtPayment, 0);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        deal({ token: USDC_MAINNET, to: address(strategy), give: 80 * _1_USDC });

        strategy.adjustPosition();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDC, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        assertEq(loss, 0);
        assertEq(debtPayment, 0);
    }

    function testBeefythUSDDAIUSDCUSDT__Invest() public {
        uint256 returned = strategy.invest(0, 0);
        assertEq(returned, 0);
        assertEq(IERC20(BEEFY_THUSD_DAI_USDC_USDT_MAINNET).balanceOf(address(strategy)), 0);

        vm.expectRevert(abi.encodeWithSignature("NotEnoughFundsToInvest()"));
        returned = strategy.invest(1, 0);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);

        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);

        assertApproxEq(
            expectedShares, IERC20(BEEFY_THUSD_DAI_USDC_USDT_MAINNET).balanceOf(address(strategy)), expectedShares / 10
        );
    }

    function testBeefythUSDDAIUSDCUSDT__Divest() public {
        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);

        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);

        assertApproxEq(
            expectedShares, IERC20(BEEFY_THUSD_DAI_USDC_USDT_MAINNET).balanceOf(address(strategy)), expectedShares / 10
        );

        uint256 strategyBalanceBefore = IERC20(USDC_MAINNET).balanceOf(address(strategy));
        uint256 amountDivested = strategy.divest(IERC20(BEEFY_THUSD_DAI_USDC_USDT_MAINNET).balanceOf(address(strategy)));

        assertEq(IERC20(USDC_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + amountDivested);
    }

    function testBeefythUSDDAIUSDCUSDT__LiquidatePosition() public {
        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        (uint256 liquidatedAmount, uint256 loss) = strategy.liquidatePosition(1 * _1_USDC);
        assertEq(liquidatedAmount, 1 * _1_USDC);
        assertEq(loss, 0);

        (liquidatedAmount, loss) = strategy.liquidatePosition(10 * _1_USDC);
        assertEq(liquidatedAmount, 10 * _1_USDC);
        assertEq(loss, 0);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 5 * _1_USDC });
        uint256 invested = strategy.invest(5 * _1_USDC, 0);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });

        (liquidatedAmount, loss) = strategy.liquidatePosition(149 * _1_USDC / 10);

        assertApproxEq(liquidatedAmount, 149 * _1_USDC / 10, 5 * _1_USDC / 1000);
        assertLt(loss, 1 * _1_USDC / 5);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 50 * _1_USDC });
        invested = strategy.invest(50 * _1_USDC, 0);

        (liquidatedAmount, loss) = strategy.liquidatePosition(495 * _1_USDC / 10);

        assertApproxEq(liquidatedAmount, 495 * _1_USDC / 10, 5 * _1_USDC / 100);
        assertLt(loss, 1 * _1_USDC / 5);
    }

    function testBeefythUSDDAIUSDCUSDT__LiquidateAllPositions() public {
        uint256 snapshotId = vm.snapshot();

        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        uint256 shares = strategy.sharesForAmount(10 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);

        assertApproxEq(IERC20(BEEFY_THUSD_DAI_USDC_USDT_MAINNET).balanceOf(address(strategy)), shares, shares / 10);

        uint256 strategyBalanceBefore = IERC20(USDC_MAINNET).balanceOf(address(strategy));
        uint256 amountFreed = strategy.liquidateAllPositions();

        assertApproxEq(amountFreed, 10 * _1_USDC, 3 * _1_USDC / 100);

        assertEq(IERC20(USDC_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + amountFreed);
        assertEq(IERC20(BEEFY_THUSD_DAI_USDC_USDT_MAINNET).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 100 * _1_USDC });
        shares = strategy.sharesForAmount(100 * _1_USDC);

        vm.expectEmit();
        emit Invested(address(strategy), 100 * _1_USDC);
        strategy.invest(100 * _1_USDC, 0);
        assertApproxEq(IERC20(BEEFY_THUSD_DAI_USDC_USDT_MAINNET).balanceOf(address(strategy)), shares, 0.006 ether);

        strategyBalanceBefore = IERC20(USDC_MAINNET).balanceOf(address(strategy));
        amountFreed = strategy.liquidateAllPositions();

        assertApproxEq(amountFreed, 100 * _1_USDC, _1_USDC);

        assertEq(IERC20(USDC_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + amountFreed);
        assertEq(IERC20(BEEFY_THUSD_DAI_USDC_USDT_MAINNET).balanceOf(address(strategy)), 0);
    }

    function testBeefythUSDDAIUSDCUSDT__Harvest() public {
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.harvest(0, 0, address(0), block.timestamp);

        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, uint128(40 * _1_USDC), uint128(40 * _1_USDC), 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);

        strategy.harvest(0, 0, address(0), block.timestamp);

        uint256 expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDC);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 60 * _1_USDC);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(strategy)), 0);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        vm.warp(block.timestamp + 1 days);

        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 60 * _1_USDC);

        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();

        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, uint128(40 * _1_USDC), uint128(40 * _1_USDC), 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);

        strategy.harvest(0, 0, address(0), block.timestamp);

        expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDC);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 60 * _1_USDC);

        vm.startPrank(users.alice);
        strategy.setEmergencyExit(2);

        vm.startPrank(users.keeper);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        vm.warp(block.timestamp + 1 days);

        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 109_971_091);
        assertEq(IERC20(BEEFY_THUSD_DAI_USDC_USDT_MAINNET).balanceOf(address(strategy)), 0);
        vm.revertTo(snapshotId);

        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDC);
        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, uint128(40 * _1_USDC), uint128(40 * _1_USDC), 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        strategy.harvest(0, 0, address(0), block.timestamp);

        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 60 * _1_USDC);

        expectedStrategyShareBalance = strategy.sharesForAmount(10 * _1_USDC);

        vm.startPrank(address(strategy));
        uint256 withdrawn = strategy.divest(expectedStrategyShareBalance);

        IERC20(USDC_MAINNET).transfer(makeAddr("random"), withdrawn);
        vm.startPrank(users.keeper);

        strategy.harvest(0, 0, address(0), block.timestamp);

        StrategyData memory data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3001);
        assertEq(data.strategyDebtRatio, 3001);
    }

    function testBeefythUSDDAIUSDCUSDT__PreviewLiquidate() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);
        vm.startPrank(users.keeper);

        strategy.harvest(0, 0, address(0), block.timestamp);

        vm.stopPrank();
        uint256 expected = strategy.previewLiquidate(30 * _1_USDC);

        vm.startPrank(address(vault));

        uint256 loss = strategy.liquidate(30 * _1_USDC);

        assertLe(expected, 30 * _1_USDC - loss);
    }

    function testBeefythUSDDAIUSDCUSDT__PreviewLiquidateExact() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 requestedAmount = strategy.previewLiquidateExact(30 * _1_USDC);

        vm.startPrank(address(vault));
        uint256 balanceBefore = IERC20(USDC_MAINNET).balanceOf(address(vault));

        strategy.liquidateExact(30 * _1_USDC);
        uint256 withdrawn = IERC20(USDC_MAINNET).balanceOf(address(vault)) - balanceBefore;

        // withdraw exactly what requested
        assertEq(withdrawn, 30 * _1_USDC);
        // losses are equal or fewer than expected
        assertLe(withdrawn - 30 * _1_USDC, requestedAmount - 30 * _1_USDC);
    }

    function testBeefythUSDDAIUSDCUSDT__maxLiquidateExact() public {
        vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 maxLiquidateExact = strategy.maxLiquidateExact();
        uint256 balanceBefore = IERC20(USDC_MAINNET).balanceOf(address(vault));
        uint256 requestedAmount = strategy.previewLiquidateExact(maxLiquidateExact);
        vm.startPrank(address(vault));
        uint256 losses = strategy.liquidateExact(maxLiquidateExact);
        uint256 withdrawn = IERC20(USDC_MAINNET).balanceOf(address(vault)) - balanceBefore;
        // withdraw exactly what requested
        assertEq(withdrawn, maxLiquidateExact);
        // losses are equal or fewer than expected
        assertLe(losses, requestedAmount - maxLiquidateExact);
    }

    function testBeefythUSDDAIUSDCUSDT__MaxLiquidate() public {
        vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 maxWithdraw = strategy.maxLiquidate();
        uint256 balanceBefore = IERC20(USDC_MAINNET).balanceOf(address(vault));
        vm.startPrank(address(vault));
        strategy.liquidate(maxWithdraw);
        uint256 withdrawn = IERC20(USDC_MAINNET).balanceOf(address(vault)) - balanceBefore;
        assertLe(withdrawn, maxWithdraw);
    }

    function testBeefythUSDDAIUSDCUSDT___SimulateHarvest() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);
        vm.startPrank(users.keeper);
        (uint256 expectedBalance, uint256 outputAfterInvestment,,,,) = strategy.simulateHarvest();
        strategy.harvest(expectedBalance, outputAfterInvestment, address(0), block.timestamp);
    }

    function testBeefythUSDDAIUSDCUSDT__PreviewLiquidate__FUZZY(uint256 amount) public {
        vm.assume(amount > 1 * _1_USDC && amount < 100 * _1_USDC);
        deal(USDC_MAINNET, users.alice, amount);
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(amount, users.alice);
        vm.startPrank(users.keeper);

        strategy.harvest(0, 0, address(0), block.timestamp);

        vm.stopPrank();
        uint256 expected = strategy.previewLiquidate(amount / 3);
        vm.startPrank(address(vault));

        uint256 loss = strategy.liquidate(amount / 3);

        assertLe(expected, amount / 3 - loss);
    }

    function testBeefythUSDDAIUSDCUSDT__PreviewLiquidateExact__FUZZY(uint256 amount) public {
        vm.assume(amount > 1 * _1_USDC && amount < 100 * _1_USDC);
        deal(USDC_MAINNET, users.alice, amount);
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(amount, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 requestedAmount = strategy.previewLiquidateExact(amount / 3);

        vm.startPrank(address(vault));
        uint256 balanceBefore = IERC20(USDC_MAINNET).balanceOf(address(vault));

        strategy.liquidateExact(amount / 3);
        uint256 withdrawn = IERC20(USDC_MAINNET).balanceOf(address(vault)) - balanceBefore;

        // withdraw exactly what requested
        assertGe(withdrawn, amount / 3);
        // losses are equal or fewer than expected
        assertLe(withdrawn - (amount / 3), requestedAmount - (amount / 3));
    }

    function testBeefythUSDDAIUSDCUSDT__maxLiquidateExact_FUZZY(uint256 amount) public {
        vm.assume(amount > 1 * _1_USDC && amount < 100 * _1_USDC);
        deal(USDC_MAINNET, users.alice, amount);
        vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
        vault.deposit(amount, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 maxLiquidateExact = strategy.maxLiquidateExact();
        uint256 balanceBefore = IERC20(USDC_MAINNET).balanceOf(address(vault));
        uint256 requestedAmount = strategy.previewLiquidateExact(maxLiquidateExact);
        vm.startPrank(address(vault));
        uint256 losses = strategy.liquidateExact(maxLiquidateExact);
        uint256 withdrawn = IERC20(USDC_MAINNET).balanceOf(address(vault)) - balanceBefore;
        // withdraw exactly what requested
        assertGe(withdrawn, maxLiquidateExact);
        // losses are equal or fewer than expected
        assertLe(losses, requestedAmount - maxLiquidateExact);
    }

    function testBeefythUSDDAIUSDCUSDT__MaxLiquidate_FUZZY(uint256 amount) public {
        vm.assume(amount > 1 * _1_USDC && amount < 100 * _1_USDC);
        deal(USDC_MAINNET, users.alice, amount);
        vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
        vault.deposit(amount, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 maxWithdraw = strategy.maxLiquidate();
        uint256 balanceBefore = IERC20(USDC_MAINNET).balanceOf(address(vault));
        vm.startPrank(address(vault));
        strategy.liquidate(maxWithdraw);
        uint256 withdrawn = IERC20(USDC_MAINNET).balanceOf(address(vault)) - balanceBefore;
        assertLe(withdrawn, maxWithdraw);
    }
}
