// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import { ICellar } from "src/interfaces/ICellar.sol";
import { ICurveLpPool } from "src/interfaces/ICurve.sol";
import { IWETH } from "src/interfaces/IWETH.sol";
import { BaseTest, IERC20, Vm, console2 } from "../../base/BaseTest.t.sol";
import { IStrategyWrapper } from "../../interfaces/IStrategyWrapper.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";
import { SommelierStEthDepositTurboStEthStrategyWrapper } from
    "../../mock/SommelierStEthDepositTurboStEthStrategyWrapper.sol";
import { MaxApyVault } from "src/MaxApyVault.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { SommelierTurboStEthStrategy } from "src/strategies/mainnet/WETH/sommelier/SommelierTurboStEthStrategy.sol";
import { StrategyEvents } from "../../helpers/StrategyEvents.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import "src/helpers/AddressBook.sol";

contract SommelierStEthDepositTurboStEthStrategyTest is BaseTest, StrategyEvents {
    address public constant CELLAR_STETH_MAINNET = SOMMELIER_ST_ETH_DEPOSIT_TURBO_STETH_CELLAR_MAINNET;
    address public constant CURVE_POOL = CURVE_ETH_STETH_POOL_MAINNET;
    address public TREASURY;

    function _dealStEth(address give, uint256 wethIn) internal returns (uint256 stEthOut) {
        vm.deal(give, wethIn);
        stEthOut = ICurveLpPool(CURVE_POOL).exchange{ value: wethIn }(0, 1, wethIn, 0);
        IERC20(STETH_MAINNET).transfer(give, stEthOut >= wethIn ? wethIn : stEthOut);
    }

    IStrategyWrapper public strategy;
    SommelierStEthDepositTurboStEthStrategyWrapper public implementation;
    MaxApyVault public vaultDeployment;
    IMaxApyVault public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;

    function setUp() public {
        super._setUp("MAINNET");

        TREASURY = makeAddr("treasury");

        vaultDeployment = new MaxApyVault(users.alice, WETH_MAINNET, "MaxApyWETHVault", "maxWETH", TREASURY);

        vault = IMaxApyVault(address(vaultDeployment));
        proxyAdmin = new ProxyAdmin(users.alice);
        implementation = new SommelierStEthDepositTurboStEthStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier Strategy")),
                users.alice,
                CELLAR_STETH_MAINNET
            )
        );
        vm.label(CELLAR_STETH_MAINNET, "Cellar");
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "SommelierStEThDeposiTurbStEthStrategy");
        vm.label(WETH_MAINNET, "WETH");
        vm.label(STETH_MAINNET, "StETH");
        vm.label(CURVE_ETH_STETH_POOL_MAINNET, "CurvePool");

        strategy = IStrategyWrapper(address(_proxy));

        IERC20(WETH_MAINNET).approve(address(vault), type(uint256).max);
        vm.rollFork(18_958_838);
    }

    /*==================INITIALIZATION TESTS===================*/

    function testSommelierStEthDeposit_TurboStEth__Initialization() public {
        MaxApyVault _vault = new MaxApyVault(users.alice, WETH_MAINNET, "MaxApyWETHVault", "maxWETH", TREASURY);
        ProxyAdmin _proxyAdmin = new ProxyAdmin(users.alice);
        SommelierStEthDepositTurboStEthStrategyWrapper _implementation =
            new SommelierStEthDepositTurboStEthStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(_implementation),
            address(_proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(_vault),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier Strategy")),
                users.alice,
                CELLAR_STETH_MAINNET
            )
        );

        IStrategyWrapper _strategy = IStrategyWrapper(address(_proxy));

        assertEq(_strategy.vault(), address(_vault));
        assertEq(_strategy.hasAnyRole(_strategy.vault(), _strategy.VAULT_ROLE()), true);
        assertEq(_strategy.underlyingAsset(), WETH_MAINNET);
        assertEq(IERC20(WETH_MAINNET).allowance(address(_strategy), address(_vault)), type(uint256).max);
        assertEq(_strategy.hasAnyRole(users.keeper, _strategy.KEEPER_ROLE()), true);
        assertEq(_strategy.hasAnyRole(users.alice, _strategy.ADMIN_ROLE()), true);
        assertEq(_strategy.strategyName(), bytes32(abi.encode("MaxApy Sommelier Strategy")));
        assertEq(_strategy.cellar(), CELLAR_STETH_MAINNET);
        assertEq(IERC20(STETH_MAINNET).allowance(address(_strategy), CELLAR_STETH_MAINNET), type(uint256).max);
        assertEq(_strategy.maxSingleTrade(), 1000 * 1e18);

        assertEq(_proxyAdmin.owner(), users.alice);
        vm.startPrank(address(_proxyAdmin));
        // assertEq(proxyInit.admin(), address(_proxyAdmin));
        vm.stopPrank();

        vm.startPrank(users.alice);
    }

    /*==================STRATEGY CONFIGURATION TESTS==================*/

    function testSommelierStEthDeposit_TurboStEth__SetEmergencyExit() public {
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

    function testSommelierStEthDeposit_TurboStEth__IsActive() public {
        vault.addStrategy(address(strategy), 10_000, 0, 0, 0);
        assertEq(strategy.isActive(), false);

        deal(WETH_MAINNET, address(strategy), 1 ether);
        assertEq(strategy.isActive(), false);

        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
        vm.stopPrank();

        strategy.divest(ICellar(CELLAR_STETH_MAINNET).balanceOf(address(strategy)));
        vm.startPrank(address(strategy));
        IERC20(WETH_MAINNET).transfer(makeAddr("random"), IERC20(WETH_MAINNET).balanceOf(address(strategy)));
        assertEq(strategy.isActive(), false);

        deal(WETH_MAINNET, address(strategy), 1 ether);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
    }

    function testSommelierStEthDeposit_TurboStEth__SetMaxSingleTrade() public {
        vm.stopPrank();
        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setMaxSingleTrade(1 ether);

        vm.stopPrank();
        vm.startPrank(address(vault));
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setMaxSingleTrade(1 ether);

        vm.stopPrank();
        vm.startPrank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidZeroAmount()"));
        strategy.setMaxSingleTrade(0);

        vm.expectEmit();
        emit MaxSingleTradeUpdated(1 ether);
        strategy.setMaxSingleTrade(1 ether);
        assertEq(strategy.maxSingleTrade(), 1 ether);
    }

    function testSommelierStEthDeposit_TurboStEth__SetMinSingleTrade() public {
        vm.stopPrank();
        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setMinSingleTrade(1 ether);

        vm.stopPrank();
        vm.startPrank(address(vault));
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setMinSingleTrade(1 ether);

        vm.stopPrank();
        vm.startPrank(users.alice);
        vm.expectEmit();
        emit MinSingleTradeUpdated(1 ether);
        strategy.setMinSingleTrade(1 ether);
        assertEq(strategy.minSingleTrade(), 1 ether);
    }

    function testSommelierStEthDeposit_TurboStEth__SetStrategist() public {
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
    function testSommelierStEthDeposit_TurboStEth__InvestmentSlippage() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        vm.startPrank(users.keeper);

        // Expect revert if output amount is gt amount obtained
        vm.expectRevert(abi.encodeWithSignature("MinOutputAmountNotReached()"));
        strategy.harvest(0, type(uint256).max, address(0), block.timestamp);
    }

    function testSommelierStEthDeposit_TurboStEth__PrepareReturn() public {
        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        (uint256 unrealizedProfit, uint256 loss, uint256 debtPayment) = strategy.prepareReturn(1 ether, 0);
        // assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 0);
        assertEq(loss, 0);
        assertEq(debtPayment, 1 ether);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        _dealStEth(address(strategy), 60 ether);
        strategy.investSommelier(60 ether);

        vault.deposit(100 ether, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        uint256 beforeReturnSnapshotId = vm.snapshot();

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        // assertEq(realizedProfit, 59.949949239970347554 ether);
        assertEq(unrealizedProfit, 59.967032154129262745 ether);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        // assertEq(realizedProfit, 5.996703215412926274 ether);
        assertEq(unrealizedProfit, 59.967032154129262745 ether);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        // assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 59.967032154129262745 ether);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        strategy.triggerLoss(10 ether);
        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        // assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 0);
        assertEq(loss, 10 ether);
        assertEq(debtPayment, 0);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        deal({ token: WETH_MAINNET, to: address(strategy), give: 80 ether });

        // Perform initial investment in sommelier from the strategy side
        strategy.adjustPosition();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        strategy.setMaxSingleTrade(1000);

        strategy.mockReport(0, 0, 0, TREASURY);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        // assertEq(realizedProfit, 40 ether + 999);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
    }

    function testSommelierStEthDeposit_TurboStEth__AdjustPosition() public {
        strategy.adjustPosition();
        assertEq(IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), 0);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 expectedShares = strategy.sharesForAmount(10 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 10 ether);
        strategy.adjustPosition();
        // will not get exactly the expected shares because there is a swap in between
        assertApproxEq(expectedShares, IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), expectedShares / 100);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 100 ether });
        expectedShares += strategy.sharesForAmount(100 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 100 ether);
        strategy.adjustPosition();
        assertApproxEq(expectedShares, IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), expectedShares / 100);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 500 ether });
        expectedShares += strategy.sharesForAmount(500 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 500 ether);
        strategy.adjustPosition();
        assertApproxEq(expectedShares, IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), expectedShares / 100);
    }

    function testSommelierStEthDeposit_TurboStEth__Invest() public {
        uint256 returned = strategy.invest(0, 0);
        assertEq(returned, 0);
        assertEq(IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), 0);

        vm.expectRevert(abi.encodeWithSignature("NotEnoughFundsToInvest()"));
        returned = strategy.invest(1, 0);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 expectedShares = strategy.sharesForAmount(10 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 10 ether);
        strategy.invest(10 ether, 0);
        // will not get exactly the expected shares because there is a swap in between
        assertApproxEq(IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), expectedShares, expectedShares / 100);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        expectedShares += strategy.sharesForAmount(10 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 10 ether);
        strategy.invest(10 ether, 0);
        assertApproxEq(expectedShares, IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), expectedShares / 100);
    }

    function testSommelierStEthDeposit_TurboStEth__Invest_CellarIsShutdown() public {
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 snapshotId = vm.snapshot();
        _shutDownCellar();
        // if cellar is shut down no funds are invested
        assertEq(strategy.invest(10 ether, 0), 0);
        vm.revertTo(snapshotId);
        assertGt(strategy.invest(10 ether, 0), 0);
    }

    function testSommelierStEthDeposit_TurboStEth__Invest_CellarIsPaused() public {
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 snapshotId = vm.snapshot();
        _pauseCellar();
        // if cellar is shut down no funds are invested
        assertEq(strategy.invest(10 ether, 0), 0);
        vm.revertTo(snapshotId);
        assertGt(strategy.invest(10 ether, 0), 0);
    }

    function testSommelierStEthDeposit_TurboStEth__Divest() public {
        deal({ token: WETH_MAINNET, to: address(strategy), give: 1000 ether });
        uint256 expectedShares = strategy.sharesForAmount(1000 ether);

        strategy.invest(1000 ether, 0);

        uint256 expectedAssets = strategy.shareValue(expectedShares);
        assertApproxEq(expectedShares, IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), expectedShares / 100);

        uint256 strategyBalanceBefore = IERC20(WETH_MAINNET).balanceOf(address(strategy));
        uint256 amountDivested = strategy.divest(expectedShares * 99 / 100);
        assertApproxEq(amountDivested, expectedAssets, expectedAssets / 100);
        assertApproxEq(
            IERC20(WETH_MAINNET).balanceOf(address(strategy)),
            strategyBalanceBefore + expectedAssets,
            expectedAssets / 100
        );
    }

    function testSommelierStEthDeposit_TurboStEth__Divest_CellarIsPaused() public {
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        strategy.invest(10 ether, 0);
        uint256 snapshotId = vm.snapshot();
        _pauseCellar();
        // if cellar is paused no funds are divested
        assertEq(strategy.divest(1 ether), 0);
        vm.revertTo(snapshotId);
        assertGt(strategy.divest(1 ether), 0);
    }

    // TODO: remove dev comments
    function testSommelierStEthDeposit_TurboStEth__LiquidatePosition() public {
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        (uint256 liquidatedAmount, uint256 loss) = strategy.liquidatePosition(1 ether);
        assertEq(liquidatedAmount, 1 ether);
        assertEq(loss, 0);

        (liquidatedAmount, loss) = strategy.liquidatePosition(10 ether);
        assertEq(liquidatedAmount, 10 ether);
        assertEq(loss, 0);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 5 ether });
        strategy.invest(5 ether, 0);
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });

        uint256 expectedLiquidatedAmount = 10 ether + strategy.shareValue(strategy.sharesForAmount(5 ether));
        (liquidatedAmount, loss) = strategy.liquidatePosition(15 ether);
        // will  not be exactly the same becasue there is a swap in between
        assertApproxEq(liquidatedAmount, expectedLiquidatedAmount, expectedLiquidatedAmount / 100);
        assertApproxEq(loss, 15 ether - expectedLiquidatedAmount, expectedLiquidatedAmount / 100);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 1000 ether });
        strategy.invest(1000 ether, 0);
        deal({ token: WETH_MAINNET, to: address(strategy), give: 500 ether });

        expectedLiquidatedAmount = 500 ether + strategy.shareValue(strategy.sharesForAmount(500 ether));

        (liquidatedAmount, loss) = strategy.liquidatePosition(1000 ether);

        assertApproxEq(liquidatedAmount, expectedLiquidatedAmount, expectedLiquidatedAmount / 100);
    }

    function testSommelierStEthDeposit_TurboStEth__LiquidateAllPositions() public {
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 expectedShares = strategy.sharesForAmount(10 ether);
        strategy.invest(10 ether, 0);
        assertApproxEq(expectedShares, IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), expectedShares / 100);

        uint256 expectedAmountFreed = strategy.shareValue(expectedShares);
        uint256 amountFreed = strategy.liquidateAllPositions();
        assertApproxEq(amountFreed, expectedAmountFreed, expectedAmountFreed / 100);
        assertApproxEq(
            IERC20(WETH_MAINNET).balanceOf(address(strategy)), expectedAmountFreed, expectedAmountFreed / 100
        );
        assertEq(IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), 0);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 500 ether });
        expectedShares = strategy.sharesForAmount(500 ether);
        strategy.invest(500 ether, 0);
        assertApproxEq(expectedShares, IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), expectedShares / 100);

        uint256 strategyBalanceBefore = IERC20(WETH_MAINNET).balanceOf(address(strategy));
        expectedAmountFreed = strategy.shareValue(expectedShares);
        amountFreed = strategy.liquidateAllPositions();
        assertApproxEq(amountFreed, expectedAmountFreed, expectedAmountFreed / 100);
        assertApproxEq(
            IERC20(WETH_MAINNET).balanceOf(address(strategy)),
            strategyBalanceBefore + expectedAmountFreed,
            expectedAmountFreed / 100
        );
        assertEq(IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), 0);
    }

    function testSommelierStEthDeposit_TurboStEth__Harvest() public {
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.harvest(0, 0, address(0), block.timestamp);

        uint256 snapshotId = vm.snapshot();

        vault.deposit(100 ether, users.alice);
        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, 40 ether, 40 ether, 4000);
        vm.stopPrank();
        vm.startPrank(users.keeper);
        uint256 expectedStrategyShareBalance = strategy.sharesForAmount(40 ether);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        // strategy takes 40 eth
        strategy.harvest(0, 0, address(0), block.timestamp);

        // there are 60 eth left in the vault
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), 0);
        // strategy has expectedStrategyShareBalance cellar shares
        assertApproxEq(
            IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)),
            expectedStrategyShareBalance,
            expectedStrategyShareBalance / 100
        );

        // strategy gets 10 eth more as profit
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });

        vm.expectEmit();
        // debt: 40 eth
        emit StrategyReported(address(strategy), 10 ether, 0, 0, 10 ether, 0, 40 ether, 0, 4000);
        vm.expectEmit();
        emit Harvested(10 ether, 0, 0, 0);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();

        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, 40 ether, 40 ether, 4000);

        expectedStrategyShareBalance = strategy.sharesForAmount(40 ether);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        strategy.harvest(0, 0, address(0), block.timestamp);

        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertApproxEq(
            IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)),
            expectedStrategyShareBalance,
            expectedStrategyShareBalance / 100
        );

        vm.startPrank(users.alice);
        strategy.setEmergencyExit(2);

        vm.startPrank(users.keeper);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });

        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            0,
            // unrealised vault gain is 0 because we dont want to assess fees
            0.013830253026478812 ether,
            39.986169746973521188 ether,
            0,
            0.013830253026478812 ether,
            0,
            0,
            3999
        );

        vm.expectEmit();
        emit Harvested(0, 0.013830253026478812 ether, 49.970026864837587483 ether, 0);

        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 109.970026864837587483 ether);
        assertEq(IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);

        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, 40 ether, 40 ether, 4000);
        expectedStrategyShareBalance = strategy.sharesForAmount(40 ether);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        strategy.harvest(0, 0, address(0), block.timestamp);

        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertApproxEq(
            IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)),
            expectedStrategyShareBalance,
            expectedStrategyShareBalance / 100
        );

        uint256 expectedShares = strategy.sharesForAmount(10 ether);

        vm.startPrank(address(strategy));
        IERC20(CELLAR_STETH_MAINNET).transfer(makeAddr("random"), expectedShares);

        vm.startPrank(users.keeper);
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            0,
            9.994505359021543791 ether,
            0,
            0,
            9.994505359021543791 ether,
            30.005494640978456209 ether,
            0,
            3001
        );

        vm.expectEmit();
        emit Harvested(0, 9.994505359021543791 ether, 0, 2.994845699220821501 ether);
        strategy.harvest(0, 0, address(0), block.timestamp);

        StrategyData memory data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3001);
        assertEq(vault.totalDebt(), 30.005494640978456209 ether);
        assertEq(data.strategyDebtRatio, 3001);
        assertEq(data.strategyTotalDebt, 30.005494640978456209 ether);
        assertEq(data.strategyTotalLoss, 9.994505359021543791 ether);
    }

    function testSommelierStEthDeposit_TurboStEth__Harvest_CellarIsShutdown_Paused() public {
        uint256 snapshotId = vm.snapshot();
        // cellar is paused
        _pauseCellar();

        vm.startPrank(users.alice);
        vault.deposit(100 ether, users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, 40 ether, 40 ether, 4000);
        vm.stopPrank();
        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        // strategy takes 40 eth
        strategy.harvest(0, 0, address(0), block.timestamp);

        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertEq(IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);

        // cellar is shutdown
        _shutDownCellar();

        vm.startPrank(users.alice);
        vault.deposit(100 ether, users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, 40 ether, 40 ether, 4000);
        vm.stopPrank();
        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        // strategy takes 40 eth
        strategy.harvest(0, 0, address(0), block.timestamp);

        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertEq(IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);

        vm.startPrank(users.alice);
        vault.deposit(100 ether, users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, 40 ether, 40 ether, 4000);
        vm.stopPrank();
        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        // strategy takes 40 eth
        strategy.harvest(0, 0, address(0), block.timestamp);

        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertGt(IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), 0);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });

        _pauseCellar();

        vm.expectEmit();
        // debt: 40 eth
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, 40 ether, 0, 4000);
        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);

        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), 10 ether);

        vm.revertTo(snapshotId);

        vm.startPrank(users.alice);
        vault.deposit(100 ether, users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, 40 ether, 40 ether, 4000);
        vm.stopPrank();
        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        // strategy takes 40 eth
        strategy.harvest(0, 0, address(0), block.timestamp);

        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertGt(IERC20(CELLAR_STETH_MAINNET).balanceOf(address(strategy)), 0);
    }

    function testSommelierStEthDeposit_TurboStEth__PreviewLiquidate() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 ether, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 expected = strategy.previewLiquidate(30 ether);
        vm.startPrank(address(vault));
        uint256 loss = strategy.liquidate(30 ether);
        // expect the Sommelier's {previewRedeem} to be fully precise
        assertEq(expected, 30 ether - loss);
    }

    function testSommelierStEthDeposit_TurboStEth__PreviewLiquidateExact() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 ether, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 requestedAmount = strategy.previewLiquidateExact(30 ether);
        vm.startPrank(address(vault));
        uint256 balanceBefore = IERC20(WETH_MAINNET).balanceOf(address(vault));
        strategy.liquidateExact(30 ether);
        uint256 withdrawn = IERC20(WETH_MAINNET).balanceOf(address(vault)) - balanceBefore;
        // withdraw exactly what requested
        assertEq(withdrawn, 30 ether);
        // losses are equal or fewer than expected
        assertLe(withdrawn - 30 ether, requestedAmount - 30 ether);
    }

    function testSommelierStEthDeposit_TurboStEth__maxLiquidateExact() public {
        vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
        vault.deposit(100 ether, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 maxLiquidateExact = strategy.maxLiquidateExact();
        uint256 balanceBefore = IERC20(WETH_MAINNET).balanceOf(address(vault));
        uint256 requestedAmount = strategy.previewLiquidateExact(maxLiquidateExact);
        vm.startPrank(address(vault));
        uint256 losses = strategy.liquidateExact(maxLiquidateExact);
        uint256 withdrawn = IERC20(WETH_MAINNET).balanceOf(address(vault)) - balanceBefore;
        // withdraw exactly what requested
        assertEq(withdrawn, maxLiquidateExact);
        // losses are equal or fewer than expected
        assertLe(losses, requestedAmount - maxLiquidateExact);
    }

    function testSommelierStEthDeposit_TurboStEth__MaxLiquidate() public {
        vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
        vault.deposit(100 ether, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 maxWithdraw = strategy.maxLiquidate();
        uint256 balanceBefore = IERC20(WETH_MAINNET).balanceOf(address(vault));
        vm.startPrank(address(vault));
        strategy.liquidate(maxWithdraw);
        uint256 withdrawn = IERC20(WETH_MAINNET).balanceOf(address(vault)) - balanceBefore;
        assertLe(withdrawn, maxWithdraw);
    }

    function _pauseCellar() internal {
        // change the value of mapping isCallerPaused(address=>bool) in the registry
        vm.store(
            0xEED68C267E9313a6ED6ee08de08c9F68dee44476,
            keccak256(abi.encode(address(CELLAR_STETH_MAINNET), uint256(6))),
            bytes32(uint256(uint8(1)))
        );
    }

    function _shutDownCellar() internal {
        // keep the other values of the slot the same
        vm.store(
            CELLAR_STETH_MAINNET,
            bytes32(uint256(6)),
            bytes32(abi.encodePacked(0x69592e6f9d21989a043646fE8225da2600e5A0f7, false, true, false, false, uint32(10)))
        );
    }

    function testSommelierStEthDeposit_TurboStEth__SimulateHarvest() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 ether, users.alice);

        vm.startPrank(users.keeper);
        (uint256 expectedBalance, uint256 outputAfterInvestment) = strategy.simulateHarvest();

        strategy.harvest(expectedBalance, outputAfterInvestment, address(0), block.timestamp);
    }
}
