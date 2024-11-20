// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

import { BaseTest, IERC20, Vm, console2 } from "../../base/BaseTest.t.sol";

import { StrategyEvents } from "../../helpers/StrategyEvents.sol";
import { ICompoundV3StrategyWrapper } from "../../interfaces/ICompoundV3StrategyWrapper.sol";
import { CompoundV3USDTStrategyWrapper } from "../../mock/CompoundV3USDTStrategyWrapper.sol";
import { MaxApyVault } from "src/MaxApyVault.sol";

import "src/helpers/AddressBook.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";

import { _1_USDC } from "test/helpers/Tokens.sol";

contract CompoundV3USDTStrategyTest is BaseTest, StrategyEvents {
    address public TREASURY;

    ICompoundV3StrategyWrapper public strategy;
    CompoundV3USDTStrategyWrapper public implementation;
    MaxApyVault public vaultDeployment;
    IMaxApyVault public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;

    function setUp() public {
        super._setUp("MAINNET");
        vm.rollFork(20_790_660);

        TREASURY = makeAddr("treasury");

        vaultDeployment = new MaxApyVault(users.alice, USDC_MAINNET, "MaxApyUSDCVault", "maxUSDC", TREASURY);

        vault = IMaxApyVault(address(vaultDeployment));
        proxyAdmin = new ProxyAdmin(users.alice);
        implementation = new CompoundV3USDTStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address,address,address)",
                address(vault),
                keepers,
                bytes32("MaxApy USDT Strategy"),
                users.alice,
                COMPOUND_USDT_V3_COMMET_MAINNET,
                COMPOUND_USDT_V3_REWARDS_MAINNET,
                USDT_MAINNET,
                UNISWAP_V3_ROUTER_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(COMPOUND_USDT_V3_COMMET_MAINNET, "CompoundV3USDT");
        vm.label(address(proxy), "CompoundV3USDTStrategy");
        vm.label(address(USDC_MAINNET), "USDC");

        strategy = ICompoundV3StrategyWrapper(address(_proxy));

        IERC20(USDC_MAINNET).approve(address(vault), type(uint256).max);
    }

    /*==================INITIALIZATION TESTS==================*/

    function testCompoundV3USDT__Initialization() public {
        MaxApyVault _vault = new MaxApyVault(users.alice, USDC_MAINNET, "MaxApyUSDCVault", "maxUSDC", TREASURY);
        ProxyAdmin _proxyAdmin = new ProxyAdmin(users.alice);
        CompoundV3USDTStrategyWrapper _implementation = new CompoundV3USDTStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(_implementation),
            address(_proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address,address,address)",
                address(_vault),
                keepers,
                bytes32("MaxApy USDT Strategy"),
                users.alice,
                COMPOUND_USDT_V3_COMMET_MAINNET,
                COMPOUND_USDT_V3_REWARDS_MAINNET,
                USDT_MAINNET,
                UNISWAP_V3_ROUTER_MAINNET
            )
        );

        ICompoundV3StrategyWrapper _strategy = ICompoundV3StrategyWrapper(address(_proxy));

        assertEq(_strategy.vault(), address(_vault));
        assertEq(_strategy.hasAnyRole(_strategy.vault(), _strategy.VAULT_ROLE()), true);
        assertEq(_strategy.underlyingAsset(), USDC_MAINNET);
        assertEq(IERC20(USDC_MAINNET).allowance(address(_strategy), address(_vault)), type(uint256).max);
        assertEq(_strategy.hasAnyRole(users.keeper, _strategy.KEEPER_ROLE()), true);
        assertEq(_strategy.hasAnyRole(users.alice, _strategy.ADMIN_ROLE()), true);

        assertEq(_strategy.owner(), users.alice);
        assertEq(_strategy.strategyName(), bytes32("MaxApy USDT Strategy"));
        assertEq(_strategy.cometRewards(), COMPOUND_USDT_V3_REWARDS_MAINNET, "hereee");

        assertEq(_proxyAdmin.owner(), users.alice);
        vm.startPrank(address(_proxyAdmin));
        vm.stopPrank();

        vm.startPrank(users.alice);
    }

    /*==================STRATEGY CONFIGURATION TESTS==================*/

    function testCompoundV3USDT__SetEmergencyExit() public {
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

    function testCompoundV3USDT__SetMinSingleTrade() public {
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

    function testCompoundV3USDT__IsActive() public {
        vault.addStrategy(address(strategy), 10_000, 0, 0, 0);
        assertEq(strategy.isActive(), false);

        deal(USDC_MAINNET, address(strategy), 1 * _1_USDC);
        assertEq(strategy.isActive(), false);

        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
        vm.stopPrank();

        strategy.divest(IERC20(COMPOUND_USDT_V3_COMMET_MAINNET).balanceOf(address(strategy)), 0, true);
        vm.startPrank(address(strategy));
        IERC20(USDC_MAINNET).transfer(makeAddr("random"), IERC20(USDC_MAINNET).balanceOf(address(strategy)));

        assertEq(strategy.isActive(), false);

        deal(USDC_MAINNET, address(strategy), 1 * _1_USDC);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
    }

    function testCompoundV3USDT__SetStrategist() public {
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
    // function testCompoundV3USDT__InvestmentSlippage() public {
    //     vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

    //     vault.deposit(100 * _1_USDC, users.alice);

    //     vm.startPrank(users.keeper);

    //     // Expect revert if output amount is gt amount obtained
    //     vm.expectRevert(abi.encodeWithSignature("MinOutputAmountNotReached()"));
    //     strategy.harvest(0, type(uint256).max, address(0), block.timestamp);
    // }

    function testCompoundV3USDT__PrepareReturn() public {
        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDC, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        (uint256 unrealizedProfit, uint256 loss, uint256 debtPayment) = strategy.prepareReturn(1 * _1_USDC, 0);

        assertEq(unrealizedProfit, 0);
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

        deal({ token: USDC_MAINNET, to: address(strategy), give: 80 * _1_USDC });

        strategy.adjustPosition();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDC, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        assertEq(loss, 0);
        assertEq(debtPayment, 0);
    }

    function testCompoundV3USDT__Invest() public {
        uint256 returned = strategy.invest(0, 0);
        assertEq(returned, 0);
        assertEq(IERC20(COMPOUND_USDT_V3_COMMET_MAINNET).balanceOf(address(strategy)), 0);

        vm.expectRevert(abi.encodeWithSignature("NotEnoughFundsToInvest()"));
        returned = strategy.invest(1, 0);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedUSDCAmount = strategy.convertUsdcToBaseAsset(10 * _1_USDC);

        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        uint256 investedUSDCAmount = strategy.invest(10 * _1_USDC, 0);

        assertApproxEq(expectedUSDCAmount, IERC20(COMPOUND_USDT_V3_COMMET_MAINNET).balanceOf(address(strategy)), 2);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        expectedUSDCAmount += strategy.convertUsdcToBaseAsset(10 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);
        assertApproxEq(expectedUSDCAmount, IERC20(COMPOUND_USDT_V3_COMMET_MAINNET).balanceOf(address(strategy)), 4);
    }

    function testCompoundV3USDT__Divest() public {
        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedUSDCAmount = strategy.convertUsdcToBaseAsset(10 * _1_USDC);
        uint256 investedUSDCAmount = strategy.invest(10 * _1_USDC, 0);

        assertApproxEq(expectedUSDCAmount, IERC20(COMPOUND_USDT_V3_COMMET_MAINNET).balanceOf(address(strategy)), 2);

        // Simulate 3 days passing
        vm.warp(block.timestamp + 30 days);

        uint256 strategyBalanceBefore = IERC20(USDC_MAINNET).balanceOf(address(strategy));
        // vm.expectEmit();
        // emit Divested(address(strategy), investedUSDCAmount, investedUSDCAmount);
        uint256 amountDivested = strategy.divest(investedUSDCAmount, 0, true);

        assertApproxEq(amountDivested, investedUSDCAmount, 5 * _1_USDC / 10_000);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + amountDivested);
    }

    function testCompoundV3USDT__LiquidatePosition() public {
        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        (uint256 liquidatedAmount, uint256 loss) = strategy.liquidatePosition(1 * _1_USDC);
        assertEq(liquidatedAmount, 1 * _1_USDC);
        assertEq(loss, 0);

        (liquidatedAmount, loss) = strategy.liquidatePosition(10 * _1_USDC);
        assertEq(liquidatedAmount, 10 * _1_USDC);
        assertEq(loss, 0);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 5 * _1_USDC });
        strategy.invest(5 * _1_USDC, 0);
        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        (liquidatedAmount, loss) = strategy.liquidatePosition(15 * _1_USDC);
        assertApproxEq(liquidatedAmount, 15 * _1_USDC, 5 * _1_USDC / 100);
        assertLt(loss, 5 * _1_USDC / 100);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 50 * _1_USDC });
        strategy.invest(50 * _1_USDC, 0);

        (liquidatedAmount, loss) = strategy.liquidatePosition(50 * _1_USDC);
        assertApproxEq(liquidatedAmount, 50 * _1_USDC, 40 * _1_USDC / 100);
        assertLt(loss, _1_USDC / 2);
    }

    function testCompoundV3USDT__LiquidateAllPositions() public {
        uint256 snapshotId = vm.snapshot();

        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedUSDCAmount = strategy.convertUsdcToBaseAsset(10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);
        assertApproxEq(expectedUSDCAmount, IERC20(COMPOUND_USDT_V3_COMMET_MAINNET).balanceOf(address(strategy)), 2);

        uint256 strategyBalanceBefore = IERC20(USDC_MAINNET).balanceOf(address(strategy));
        uint256 amountFreed = strategy.liquidateAllPositions();
        assertApproxEq(amountFreed, 10 * _1_USDC, 3 * _1_USDC / 1000);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + amountFreed);
        assertEq(IERC20(COMPOUND_USDT_V3_COMMET_MAINNET).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 500 * _1_USDC });
        expectedUSDCAmount = strategy.convertUsdcToBaseAsset(500 * _1_USDC);
        strategy.invest(500 * _1_USDC, 0);
        assertApproxEq(expectedUSDCAmount, IERC20(COMPOUND_USDT_V3_COMMET_MAINNET).balanceOf(address(strategy)), 2);

        strategyBalanceBefore = IERC20(USDC_MAINNET).balanceOf(address(strategy));
        amountFreed = strategy.liquidateAllPositions();
        assertApproxEq(amountFreed, 500 * _1_USDC, 1 * _1_USDC / 10);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + amountFreed);
        assertEq(IERC20(COMPOUND_USDT_V3_COMMET_MAINNET).balanceOf(address(strategy)), 0);
    }

    function testCompoundV3USDT__Harvest() public {
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

        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 60 * _1_USDC);

        vm.startPrank(users.alice);
        strategy.setEmergencyExit(2);

        vm.startPrank(users.keeper);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        vm.warp(block.timestamp + 1 days);

        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 110_002_427);
        assertEq(IERC20(COMPOUND_USDT_V3_COMMET_MAINNET).balanceOf(address(strategy)), 0);
        vm.revertTo(snapshotId);

        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, uint128(40 * _1_USDC), uint128(40 * _1_USDC), 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        strategy.harvest(0, 0, address(0), block.timestamp);

        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 60 * _1_USDC);

        uint256 expectedUSDCAmount = strategy.convertUsdcToBaseAsset(10 * _1_USDC);

        vm.startPrank(address(strategy));
        uint256 withdrawn = strategy.divest(expectedUSDCAmount, 0, true);

        IERC20(USDC_MAINNET).transfer(makeAddr("random"), withdrawn);
        vm.startPrank(users.keeper);

        strategy.harvest(0, 0, address(0), block.timestamp);

        StrategyData memory data = vault.strategies(address(strategy));

        assertApproxEq(vault.debtRatio(), 3000, 1);
        assertApproxEq(data.strategyDebtRatio, 3000, 1);
    }

    function testCompoundV3USDT__PreviewLiquidate() public {
        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 expected = strategy.previewLiquidate(30 * _1_USDC);
        vm.startPrank(address(vault));
        uint256 loss = strategy.liquidate(30 * _1_USDC);

        assertLe(expected, 30 * _1_USDC - loss);

        vm.revertTo(snapshotId);

        // vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        // vault.deposit(100 * _1_USDC, users.alice);
        // vm.startPrank(users.keeper);
        // strategy.harvest(0, 0, address(0), block.timestamp);

        // vm.warp(block.timestamp + 2 days);
        // strategy.harvest(0, 0, address(0), block.timestamp);
        // vm.stopPrank();
        // uint256 expected = strategy.previewLiquidate(45 * _1_USDC);
        // vm.startPrank(address(vault));
        // uint256 loss = strategy.liquidate(45 * _1_USDC);
    }

    // function testCompoundV3USDT__PreviewLiquidateExact() public {
    //     vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
    //     vault.deposit(100 * _1_USDC, users.alice);
    //     vm.startPrank(users.keeper);
    //     strategy.harvest(0, 0, address(0), block.timestamp);
    //     vm.stopPrank();
    //     uint256 requestedAmount = strategy.previewLiquidateExact(30 * _1_USDC);
    //     vm.startPrank(address(vault));
    //     uint256 balanceBefore = IERC20(USDC_MAINNET).balanceOf(address(vault));
    //     strategy.liquidateExact(30 * _1_USDC);
    //     uint256 withdrawn = IERC20(USDC_MAINNET).balanceOf(address(vault)) - balanceBefore;
    //     // withdraw exactly what requested
    //     assertEq(withdrawn, 30 * _1_USDC);
    //     // losses are equal or fewer than expected
    //     assertLe(withdrawn - 30 * _1_USDC, requestedAmount - 30 * _1_USDC);
    // }

    function testCompoundV3USDT__maxLiquidateExact() public {
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

    function testCompoundV3USDT__MaxLiquidate() public {
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

    function testCompoundV3USDT__SimulateHarvest() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);
        (uint256 expectedBalance, uint256 outputAfterInvestment,,,,) = strategy.simulateHarvest();

        strategy.harvest(expectedBalance, outputAfterInvestment, address(0), block.timestamp);
    }
}
