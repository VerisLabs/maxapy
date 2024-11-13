// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

import { BaseTest, IERC20, Vm, console2 } from "../../base/BaseTest.t.sol";

import { StrategyEvents } from "../../helpers/StrategyEvents.sol";
import { IStrategyWrapper } from "../../interfaces/IStrategyWrapper.sol";
import { SommelierTurboGHOStrategyWrapper } from "../../mock/SommelierTurboGHOStrategyWrapper.sol";
import { MaxApyVault } from "src/MaxApyVault.sol";

import "src/helpers/AddressBook.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { ICellar } from "src/interfaces/ICellar.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";

import { SommelierTurboGHOStrategy } from "src/strategies/mainnet/USDC/sommelier/SommelierTurboGHOStrategy.sol";
import { _1_USDC } from "test/helpers/Tokens.sol";

contract SommelierTurboGHOStrategyTest is BaseTest, StrategyEvents {
    address public constant CELLAR_USDC_MAINNET = SOMMELIER_TURBO_GHO_CELLAR_MAINNET;
    address public TREASURY;

    IStrategyWrapper public strategy;
    SommelierTurboGHOStrategyWrapper public implementation;
    MaxApyVault public vaultDeployment;
    IMaxApyVault public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;

    function setUp() public {
        super._setUp("MAINNET");
        vm.rollFork(21_019_709);

        TREASURY = makeAddr("treasury");

        vaultDeployment = new MaxApyVault(users.alice, USDC_MAINNET, "MaxApyUSDCVault", "maxApy", TREASURY);

        vault = IMaxApyVault(address(vaultDeployment));
        proxyAdmin = new ProxyAdmin(users.alice);
        implementation = new SommelierTurboGHOStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32("MaxApy Real USD Strategy"),
                users.alice,
                CELLAR_USDC_MAINNET
            )
        );
        vm.label(CELLAR_USDC_MAINNET, "Cellar");
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "SommelierTurboGHOStrategy");
        vm.label(address(USDC_MAINNET), "USDC");

        strategy = IStrategyWrapper(address(_proxy));

        IERC20(USDC_MAINNET).approve(address(vault), 0);
        IERC20(USDC_MAINNET).approve(address(vault), type(uint256).max);
        vm.rollFork(19_289_445);
    }

    /*==================INITIALIZATION TESTS===================*/

    function testSommelierTurboGHO__Initialization() public {
        MaxApyVault _vault = new MaxApyVault(users.alice, USDC_MAINNET, "MaxApyUSDCVault", "maxUSDC", TREASURY);
        ProxyAdmin _proxyAdmin = new ProxyAdmin(users.alice);
        SommelierTurboGHOStrategyWrapper _implementation = new SommelierTurboGHOStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(_implementation),
            address(_proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(_vault),
                keepers,
                bytes32("MaxApy Sommelier Strategy"),
                users.alice,
                CELLAR_USDC_MAINNET
            )
        );

        IStrategyWrapper _strategy = IStrategyWrapper(address(_proxy));

        assertEq(_strategy.vault(), address(_vault));
        assertEq(_strategy.hasAnyRole(_strategy.vault(), _strategy.VAULT_ROLE()), true);
        assertEq(_strategy.underlyingAsset(), USDC_MAINNET);
        assertEq(IERC20(USDC_MAINNET).allowance(address(_strategy), address(_vault)), type(uint256).max);
        assertEq(_strategy.hasAnyRole(users.keeper, _strategy.KEEPER_ROLE()), true);
        assertEq(_strategy.hasAnyRole(users.alice, _strategy.ADMIN_ROLE()), true);
        assertEq(_strategy.strategyName(), bytes32("MaxApy Sommelier Strategy"));
        assertEq(_strategy.cellar(), CELLAR_USDC_MAINNET);
        assertEq(IERC20(USDC_MAINNET).allowance(address(_strategy), CELLAR_USDC_MAINNET), type(uint256).max);

        assertEq(_proxyAdmin.owner(), users.alice);
        vm.startPrank(address(_proxyAdmin));
        // assertEq(proxyInit.admin(), address(_proxyAdmin));
        vm.stopPrank();

        vm.startPrank(users.alice);
    }

    /*==================STRATEGY CONFIGURATION TESTS==================*/

    function testSommelierTurboGHO__SetEmergencyExit() public {
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

    function testSommelierTurboGHO__IsActive() public {
        vault.addStrategy(address(strategy), 10_000, 0, 0, 0);
        assertEq(strategy.isActive(), false);

        deal(USDC_MAINNET, address(strategy), 1 * _1_USDC);
        assertEq(strategy.isActive(), false);

        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
        vm.stopPrank();

        strategy.divest(ICellar(CELLAR_USDC_MAINNET).balanceOf(address(strategy)));
        vm.startPrank(address(strategy));
        IERC20(USDC_MAINNET).transfer(makeAddr("random"), IERC20(USDC_MAINNET).balanceOf(address(strategy)));
        assertEq(strategy.isActive(), false);

        deal(USDC_MAINNET, address(strategy), 1 * _1_USDC);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
    }

    function testSommelierTurboGHO__SetStrategist() public {
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
    function testSommelierTurboGHO__InvestmentSlippage() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);

        // Expect revert if output amount is gt amount obtained
        vm.expectRevert(abi.encodeWithSignature("MinOutputAmountNotReached()"));
        strategy.harvest(0, type(uint256).max, address(0), block.timestamp);
    }

    function testSommelierTurboGHO__PrepareReturn() public {
        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDC, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        (uint256 unrealizedProfit, uint256 loss, uint256 debtPayment) = strategy.prepareReturn(1 * _1_USDC, 0);
        // assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 0);
        assertEq(loss, 0);
        assertEq(debtPayment, _1_USDC);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        deal({ token: USDC_MAINNET, to: address(strategy), give: 60 * _1_USDC });
        strategy.investSommelier(60 * _1_USDC);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDC, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        uint256 beforeReturnSnapshotId = vm.snapshot();

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);
        // 60 USDC - losses from the previous 10 USDC investment
        // assertEq(realizedProfit, 59_973_277); // 59.97 USDC
        assertEq(unrealizedProfit, 59_979_953); // 59.97 USDC
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);
        // assertEq(realizedProfit, 5_997_995); // 5.97 USDC
        assertEq(unrealizedProfit, 59_979_953); // 58.97 USDC
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);
        // assertEq(realizedProfit, 0); // 0
        assertEq(unrealizedProfit, 59_979_953); // 58.97 USDC
        assertEq(loss, 0);
        assertEq(debtPayment, 0);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();
        vm.startPrank(users.alice);
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDC, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        strategy.triggerLoss(10 * _1_USDC);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        // assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 0);
        assertEq(loss, 10 * _1_USDC);
        assertEq(debtPayment, 0);

        vm.revertTo(snapshotId);
    }

    function testSommelierTurboGHO__AdjustPosition() public {
        strategy.adjustPosition();
        assertEq(IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)), 0);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.adjustPosition();
        assertEq(expectedShares, IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)));

        deal({ token: USDC_MAINNET, to: address(strategy), give: 100 * _1_USDC });
        expectedShares += strategy.sharesForAmount(100 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 100 * _1_USDC);
        strategy.adjustPosition();
        assertEq(expectedShares, IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)));

        deal({ token: USDC_MAINNET, to: address(strategy), give: 500 * _1_USDC });
        expectedShares += strategy.sharesForAmount(500 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 500 * _1_USDC);
        strategy.adjustPosition();
        assertEq(expectedShares, IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)));
    }

    function testSommelierTurboGHO__Invest() public {
        uint256 returned = strategy.invest(0, 0);
        assertEq(returned, 0);
        assertEq(IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)), 0);

        vm.expectRevert(abi.encodeWithSignature("NotEnoughFundsToInvest()"));
        returned = strategy.invest(1, 0);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)));
    }

    function testSommelierTurboGHO__Divest() public {
        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);
        uint256 amountExpectedFromShares = strategy.shareValue(expectedShares);
        strategy.invest(10 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)));

        uint256 strategyBalanceBefore = IERC20(USDC_MAINNET).balanceOf(address(strategy));
        uint256 expectedAmountDivested = strategy.previewLiquidate(amountExpectedFromShares);
        uint256 amountDivested = strategy.divest(strategy.sharesForAmount(amountExpectedFromShares));
        assertEq(amountDivested, expectedAmountDivested, "divested");
        assertEq(
            IERC20(USDC_MAINNET).balanceOf(address(strategy)) - strategyBalanceBefore, expectedAmountDivested, "balance"
        );
    }

    function testSommelierTurboGHO__LiquidatePosition() public {
        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        (uint256 liquidatedAmount, uint256 loss) = strategy.liquidatePosition(1 * _1_USDC);
        assertEq(liquidatedAmount, 1 * _1_USDC);
        assertEq(loss, 0);

        (liquidatedAmount, loss) = strategy.liquidatePosition(10 * _1_USDC);
        assertEq(liquidatedAmount, 10 * _1_USDC);
        assertEq(loss, 0);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 5 * _1_USDC });
        //
        strategy.invest(5 * _1_USDC, 0);
        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });

        (liquidatedAmount, loss) = strategy.liquidatePosition(15 * _1_USDC);

        uint256 expectedLiquidatedAmount = 10 * _1_USDC + strategy.shareValue(strategy.sharesForAmount(5 * _1_USDC));
        assertEq(liquidatedAmount, expectedLiquidatedAmount);
        assertEq(loss, 15 * _1_USDC - expectedLiquidatedAmount);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 1000 * _1_USDC });
        strategy.invest(1000 * _1_USDC, 0);
        deal({ token: USDC_MAINNET, to: address(strategy), give: 500 * _1_USDC });
        (liquidatedAmount, loss) = strategy.liquidatePosition(1000 * _1_USDC);

        expectedLiquidatedAmount = 500 * _1_USDC + strategy.shareValue(strategy.sharesForAmount(500 * _1_USDC));
        assertEq(liquidatedAmount, expectedLiquidatedAmount);
        assertEq(loss, 1000 * _1_USDC - expectedLiquidatedAmount);
    }

    function testSommelierTurboGHO__LiquidateAllPositions() public {
        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)));

        uint256 strategyBalanceBefore = IERC20(USDC_MAINNET).balanceOf(address(strategy));

        uint256 amountFreed = strategy.liquidateAllPositions();
        uint256 expectedAmountFreed = strategy.shareValue(strategy.sharesForAmount(10 * _1_USDC));
        assertEq(amountFreed, expectedAmountFreed);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + expectedAmountFreed);
        assertEq(IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)), 0);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 500 * _1_USDC });
        expectedShares = strategy.sharesForAmount(500 * _1_USDC);
        strategy.invest(500 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)));

        strategyBalanceBefore = IERC20(USDC_MAINNET).balanceOf(address(strategy));
        amountFreed = strategy.liquidateAllPositions();
        expectedAmountFreed = strategy.shareValue(strategy.sharesForAmount(500 * _1_USDC));
        assertEq(amountFreed, expectedAmountFreed);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + expectedAmountFreed);
        assertEq(IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)), 0);
    }

    function testSommelierTurboGHO__Harvest() public {
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.harvest(0, 0, address(0), block.timestamp);

        uint256 snapshotId = vm.snapshot();

        vault.deposit(100 * _1_USDC, users.alice);
        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vm.expectEmit();
        // esto para cuando haces harvest
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, uint128(40 * _1_USDC), uint128(40 * _1_USDC), 4000);

        vm.stopPrank();
        vm.startPrank(users.keeper);
        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        uint256 expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDC);
        // strategy takes 40 USDC
        strategy.harvest(0, 0, address(0), block.timestamp);

        // there are 60 USDC left in the vault
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 60 * _1_USDC);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(strategy)), 0);
        // strategy has expectedStrategyShareBalance cellar shares
        assertEq(IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)), expectedStrategyShareBalance, "here 1");

        // strategy gets 10 USDC more as profit
        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });

        vm.expectEmit();
        emit StrategyReported(
            address(strategy), 10 * _1_USDC, 0, 0, uint128(10 * _1_USDC), 0, uint128(40 * _1_USDC), 0, 4000
        );

        vm.expectEmit();
        emit Harvested(10 * _1_USDC, 0, 0, 0);

        strategy.harvest(0, 0, address(0), block.timestamp);
        expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDC + (10 * _1_USDC));
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 60 * _1_USDC);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(strategy)), 0);
        assertEq(IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)), expectedStrategyShareBalance - 1);

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
        expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDC);
        strategy.harvest(0, 0, address(0), block.timestamp);

        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 60 * _1_USDC);
        assertEq(IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)), expectedStrategyShareBalance);

        vm.startPrank(users.alice);
        strategy.setEmergencyExit(2);

        vm.startPrank(users.keeper);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 40 * _1_USDC, uint128(0), 0, uint128(0), 0, 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 49_986_635, 0);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 109_986_635); // 109.99 USDC
        assertEq(IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);

        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, uint128(40 * _1_USDC), uint128(40 * _1_USDC), 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);

        expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDC);
        strategy.harvest(0, 0, address(0), block.timestamp);

        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 60 * _1_USDC);
        assertEq(IERC20(CELLAR_USDC_MAINNET).balanceOf(address(strategy)), expectedStrategyShareBalance);

        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);

        vm.startPrank(address(strategy));
        IERC20(CELLAR_USDC_MAINNET).transfer(makeAddr("random"), expectedShares);

        vm.startPrank(users.keeper);
        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 9_996_658, 0, 0, 9_996_658, 30_003_342, 0, 3001);

        vm.expectEmit();
        emit Harvested(0, 9_996_658, 0, 2_993_340);
        strategy.harvest(0, 0, address(0), block.timestamp);

        StrategyData memory data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3001);
        assertEq(vault.totalDebt(), 30_003_342);
        assertEq(data.strategyDebtRatio, 3001);
        assertEq(data.strategyTotalLoss, 9_996_658);
        assertEq(data.strategyTotalDebt, 30_003_342);
    }

    function testSommelierTurboGHO__PreviewLiquidate() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 expected = strategy.previewLiquidate(30 * _1_USDC);
        vm.startPrank(address(vault));
        uint256 loss = strategy.liquidate(30 * _1_USDC);
        // expect the Sommelier's {previewRedeem} to be fully precise
        assertEq(expected, 30 * _1_USDC - loss);
    }

    function testSommelierTurboGHO__PreviewLiquidateExact() public {
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

    function testSommelierTurboGHO__maxLiquidateExact() public {
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

    function testSommelierTurboGHO__MaxLiquidate() public {
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

    function testSommelierTurboGHO___SimulateHarvest() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);
        (uint256 expectedBalance, uint256 outputAfterInvestment,,,,) = strategy.simulateHarvest();

        strategy.harvest(expectedBalance, outputAfterInvestment, address(0), block.timestamp);
    }
}
