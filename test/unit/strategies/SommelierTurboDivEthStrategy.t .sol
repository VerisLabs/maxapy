// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";

import { BaseTest, IERC20, Vm, console2 } from "../../base/BaseTest.t.sol";
import { IStrategyWrapper } from "../../interfaces/IStrategyWrapper.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";
import { ICellar } from "src/interfaces/ICellar.sol";
import { SommelierTurboDivEthStrategyWrapper } from "../../mock/SommelierTurboDivEthStrategyWrapper.sol";
import { MaxApyVault } from "src/MaxApyVault.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { SommelierTurboDivEthStrategy } from "src/strategies/mainnet/WETH/sommelier/SommelierTurboDivEthStrategy.sol";
import { StrategyEvents } from "../../helpers/StrategyEvents.sol";
import "src/helpers/AddressBook.sol";

contract SommelierTurboDivEthStrategyTest is BaseTest, StrategyEvents {
    address public constant CELLAR_BAL_MAINNET = SOMMELIER_TURBO_DIV_ETH_CELLAR_MAINNET;
    address public BAL_LP_TOKEN = 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276;
    address public TREASURY;

    IStrategyWrapper public strategy;
    SommelierTurboDivEthStrategyWrapper public implementation;
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
        implementation = new SommelierTurboDivEthStrategyWrapper();

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
                CELLAR_BAL_MAINNET
            )
        );
        vm.label(CELLAR_BAL_MAINNET, "Cellar");
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "SommelierTurboDivEthStrategy");
        vm.label(address(WETH_MAINNET), "WETH");

        strategy = IStrategyWrapper(address(_proxy));

        IERC20(WETH_MAINNET).approve(address(vault), type(uint256).max);
        vm.rollFork(19_417_251);
    }

    /*==================INITIALIZATION TESTS===================*/

    function testSommelierTurboDivEth__Initialization() public {
        MaxApyVault _vault = new MaxApyVault(users.alice, WETH_MAINNET, "MaxApyWETHVault", "maxWETH", TREASURY);
        ProxyAdmin _proxyAdmin = new ProxyAdmin(users.alice);
        SommelierTurboDivEthStrategyWrapper _implementation = new SommelierTurboDivEthStrategyWrapper();

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
                CELLAR_BAL_MAINNET
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
        assertEq(_strategy.cellar(), CELLAR_BAL_MAINNET);
        assertEq(IERC20(BAL_LP_TOKEN).allowance(address(_strategy), CELLAR_BAL_MAINNET), type(uint256).max);

        assertEq(_proxyAdmin.owner(), users.alice);
        vm.startPrank(address(_proxyAdmin));
        // assertEq(proxyInit.admin(), address(_proxyAdmin));
        vm.stopPrank();

        vm.startPrank(users.alice);
    }

    /*==================STRATEGY CONFIGURATION TESTS==================*/

    function testSommelierTurboDivEth__SetEmergencyExit() public {
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

    function testSommelierTurboDivEth__IsActive() public {
        vault.addStrategy(address(strategy), 10_000, 0, 0, 0);
        assertEq(strategy.isActive(), false);

        deal(WETH_MAINNET, address(strategy), 1 ether);
        assertEq(strategy.isActive(), false);

        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
        vm.stopPrank();

        strategy.divest(ICellar(CELLAR_BAL_MAINNET).balanceOf(address(strategy)));
        vm.startPrank(address(strategy));
        IERC20(WETH_MAINNET).transfer(makeAddr("random"), IERC20(WETH_MAINNET).balanceOf(address(strategy)));
        assertEq(strategy.isActive(), false);

        deal(WETH_MAINNET, address(strategy), 1 ether);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
    }

    function testSommelierTurboDivEth__SetStrategist() public {
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
    function testSommelierTurboDivEth__InvestmentSlippage() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        vm.startPrank(users.keeper);

        // Expect revert if output amount is gt amount obtained
        vm.expectRevert(abi.encodeWithSignature("MinOutputAmountNotReached()"));
        strategy.harvest(0, type(uint256).max, address(0), block.timestamp);
    }

    function testSommelierTurboDivEth__PrepareReturn() public {
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

        deal({ token: BAL_LP_TOKEN, to: address(strategy), give: 60 ether });
        strategy.investSommelier(60 ether);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        uint256 beforeReturnSnapshotId = vm.snapshot();

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);
        // ~60 ETH - losses from the previous 10 ETH investment
        // assertEq(realizedProfit, 61.702638366407749256 ether); // ~60 ETH
        assertEq(unrealizedProfit, 61.747018291901829621 ether); // ~60 ETH
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);
        // assertEq(realizedProfit, 6.174701829190182962 ether); // ~6 ETH
        assertEq(unrealizedProfit, 61.747018291901829621 ether); // ~60 ETH
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);
        // assertEq(realizedProfit, 0); // 0
        assertEq(unrealizedProfit, 61.747018291901829621 ether); // ~60 ETH
        assertEq(loss, 0);
        assertEq(debtPayment, 0);

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
    }

    function testSommelierTurboDivEth__AdjustPosition() public {
        strategy.adjustPosition();
        assertEq(IERC20(CELLAR_BAL_MAINNET).balanceOf(address(strategy)), 0);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 expectedShares = strategy.sharesForAmount(10 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 10 ether);
        strategy.adjustPosition();
        assertGe(IERC20(CELLAR_BAL_MAINNET).balanceOf(address(strategy)), expectedShares);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 100 ether });
        expectedShares += strategy.sharesForAmount(100 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 100 ether);
        strategy.adjustPosition();
        assertGe(IERC20(CELLAR_BAL_MAINNET).balanceOf(address(strategy)), expectedShares);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 500 ether });
        expectedShares += strategy.sharesForAmount(500 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 500 ether);
        strategy.adjustPosition();
        assertGe(IERC20(CELLAR_BAL_MAINNET).balanceOf(address(strategy)), expectedShares);
    }

    function testSommelierTurboDivEth__Invest() public {
        uint256 returned = strategy.invest(0, 0);
        assertEq(returned, 0);
        assertEq(IERC20(CELLAR_BAL_MAINNET).balanceOf(address(strategy)), 0);

        vm.expectRevert(abi.encodeWithSignature("NotEnoughFundsToInvest()"));
        returned = strategy.invest(1, 0);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 expectedShares = strategy.sharesForAmount(10 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 10 ether);
        strategy.invest(10 ether, 0);
        // minted shares should not be lesser than expected
        assertGe(IERC20(CELLAR_BAL_MAINNET).balanceOf(address(strategy)), expectedShares);
    }

    function testSommelierTurboDivEth__Invest_CellarIsShutdown() public {
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 snapshotId = vm.snapshot();
        _shutDownCellar();
        // if cellar is shut down no funds are invested
        assertEq(strategy.invest(10 ether, 0), 0);
        vm.revertTo(snapshotId);
        assertGt(strategy.invest(10 ether, 0), 0);
    }

    function testSommelierTurboDivEth__Invest_CellarIsPaused() public {
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 snapshotId = vm.snapshot();
        _pauseCellar();
        // if cellar is shut down no funds are invested
        assertEq(strategy.invest(10 ether, 0), 0);
        vm.revertTo(snapshotId);
        assertGt(strategy.invest(10 ether, 0), 0);
    }

    function testSommelierTurboDivEth__Divest() public {
        deal({ token: WETH_MAINNET, to: address(strategy), give: 1000 ether });
        uint256 expectedShares = strategy.sharesForAmount(1000 ether);
        uint256 amountExpectedFromShares = strategy.shareValue(expectedShares);
        strategy.invest(1000 ether, 0);
        assertGe(IERC20(CELLAR_BAL_MAINNET).balanceOf(address(strategy)), expectedShares);

        uint256 strategyBalanceBefore = IERC20(WETH_MAINNET).balanceOf(address(strategy));
        /*   vm.expectEmit();
        emit Divested(address(strategy), expectedShares, amountExpectedFromShares); */
        uint256 amountDivested = strategy.divest(IERC20(CELLAR_BAL_MAINNET).balanceOf(address(strategy)));
        // We dont have full precision, but it should not divest less than expected
        assertGe(amountDivested, amountExpectedFromShares, "shares");
        assertGe(IERC20(WETH_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + amountDivested);
    }

    function testSommelierTurboDivEth__Divest_CellarIsPaused() public {
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
    function testSommelierTurboDivEth__LiquidatePosition() public {
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        (uint256 liquidatedAmount, uint256 loss) = strategy.liquidatePosition(1 ether);
        assertEq(liquidatedAmount, 1 ether);
        assertEq(loss, 0);

        (liquidatedAmount, loss) = strategy.liquidatePosition(10 ether);
        assertEq(liquidatedAmount, 10 ether);
        assertEq(loss, 0);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 5 ether });
        //
        strategy.invest(5 ether, 0);
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });

        (liquidatedAmount, loss) = strategy.liquidatePosition(15 ether);

        uint256 expectedLiquidatedAmount = 10 ether + strategy.shareValue(strategy.sharesForAmount(5 ether));
        // should not liquidate less than expected
        assertGe(liquidatedAmount, expectedLiquidatedAmount);
        assertLe(loss, 15 ether - expectedLiquidatedAmount);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 1000 ether });
        strategy.invest(1000 ether, 0);
        deal({ token: WETH_MAINNET, to: address(strategy), give: 500 ether });
        (liquidatedAmount, loss) = strategy.liquidatePosition(1000 ether);

        expectedLiquidatedAmount = 500 ether + strategy.shareValue(strategy.sharesForAmount(500 ether));
        assertGe(liquidatedAmount, expectedLiquidatedAmount);
        assertLe(loss, 1000 ether - expectedLiquidatedAmount);
    }

    function testSommelierTurboDivEth__LiquidateAllPositions() public {
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 expectedShares = strategy.sharesForAmount(10 ether);
        strategy.invest(10 ether, 0);
        assertGe(IERC20(CELLAR_BAL_MAINNET).balanceOf(address(strategy)), expectedShares);

        uint256 strategyBalanceBefore = IERC20(WETH_MAINNET).balanceOf(address(strategy));
        uint256 amountFreed = strategy.liquidateAllPositions();
        uint256 expectedAmountFreed = strategy.shareValue(strategy.sharesForAmount(10 ether));
        assertGe(amountFreed, expectedAmountFreed);
        assertGe(IERC20(WETH_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + expectedAmountFreed);
        assertGe(IERC20(CELLAR_BAL_MAINNET).balanceOf(address(strategy)), 0);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 500 ether });
        expectedShares = strategy.sharesForAmount(500 ether);
        strategy.invest(500 ether, 0);
        assertGe(IERC20(CELLAR_BAL_MAINNET).balanceOf(address(strategy)), expectedShares);

        strategyBalanceBefore = IERC20(WETH_MAINNET).balanceOf(address(strategy));
        amountFreed = strategy.liquidateAllPositions();
        expectedAmountFreed = strategy.shareValue(strategy.sharesForAmount(500 ether));
        assertGe(amountFreed, expectedAmountFreed);
        assertGe(IERC20(WETH_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + expectedAmountFreed);
        assertGe(IERC20(CELLAR_BAL_MAINNET).balanceOf(address(strategy)), 0);
    }

    function testSommelierTurboDivEth__Harvest() public {
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
        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        // strategy takes 40 eth
        strategy.harvest(0, 0, address(0), block.timestamp);

        uint256 expectedStrategyShareBalance = strategy.sharesForAmount(40 ether);
        // there are 60 eth left in the vault
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), 0);
        // strategy has expectedStrategyShareBalance cellar shares
        assertGe(IERC20(CELLAR_BAL_MAINNET).balanceOf(address(strategy)), expectedStrategyShareBalance);

        // strategy gets 10 eth more as profit
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });

        vm.expectEmit();
        emit StrategyReported(address(strategy), 10 ether, 0, 0, 10 ether, 0, 40 ether, 0, 4000);

        vm.expectEmit();
        emit Harvested(10 ether, 0, 0, 0);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), 0);
        expectedStrategyShareBalance = strategy.sharesForAmount(40 ether + 10 ether);
        assertGe(IERC20(CELLAR_BAL_MAINNET).balanceOf(address(strategy)), expectedStrategyShareBalance);

        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();

        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, 40 ether, 40 ether, 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);

        strategy.harvest(0, 0, address(0), block.timestamp);

        expectedStrategyShareBalance = strategy.sharesForAmount(40 ether);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertGe(IERC20(CELLAR_BAL_MAINNET).balanceOf(address(strategy)), expectedStrategyShareBalance);

        vm.startPrank(users.alice);
        strategy.setEmergencyExit(2);

        vm.startPrank(users.keeper);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 40 ether, 0, 0, 0, 0, 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 49.984161994500442878 ether, 0);

        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 109.984161994500442878 ether);
        assertEq(IERC20(CELLAR_BAL_MAINNET).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);

        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, 40 ether, 40 ether, 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        strategy.harvest(0, 0, address(0), block.timestamp);

        expectedStrategyShareBalance = strategy.sharesForAmount(40 ether);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertGe(IERC20(CELLAR_BAL_MAINNET).balanceOf(address(strategy)), expectedStrategyShareBalance);

        uint256 expectedShares = strategy.sharesForAmount(10 ether);

        vm.startPrank(address(strategy));
        IERC20(CELLAR_BAL_MAINNET).transfer(makeAddr("random"), expectedShares);

        vm.startPrank(users.keeper);
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            // vault realized gain
            0,
            // vault unrealized gain
            9.960039999999999999 ether,
            0,
            0,
            9.960039999999999999 ether,
            30.039960000000000001 ether,
            0,
            3004
        );

        vm.expectEmit();
        emit Harvested(0, 9.960039999999999999 ether, 0, 2_991_956_016_000_000_001);
        // only losses , no effect
        strategy.harvest(0, 0, address(0), block.timestamp);

        StrategyData memory data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3004);
        assertEq(vault.totalDebt(), 30.039960000000000001 ether);
        assertEq(data.strategyDebtRatio, 3004);
        assertEq(data.strategyTotalDebt, 30.039960000000000001 ether);
        assertEq(data.strategyTotalLoss, 9.960039999999999999 ether);
    }

    function testSommelierTurboDivEth__Harvest_CellarIsShutdown_Paused() public {
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
        assertEq(IERC20(CELLAR_BAL_MAINNET).balanceOf(address(strategy)), 0);

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
        assertEq(IERC20(CELLAR_BAL_MAINNET).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);

        vm.startPrank(users.alice);
        vault.deposit(100 ether, users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, 40 ether, 40 ether, 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        vm.stopPrank();
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);

        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertGt(IERC20(CELLAR_BAL_MAINNET).balanceOf(address(strategy)), 0);

        // strategy makes profit but cannot harvest because cellar is paused
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
        assertGt(IERC20(CELLAR_BAL_MAINNET).balanceOf(address(strategy)), 0);
    }

    function testSommelierTurboDivEth__PreviewLiquidate() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 ether, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 expected = strategy.previewLiquidate(30 ether);
        vm.startPrank(address(vault));
        uint256 loss = strategy.liquidate(30 ether);
        assertGe(30 ether - loss, expected);
    }

    function testSommelierTurboDivEth__PreviewLiquidateExact() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 ether, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 requestedAmount = strategy.previewLiquidateExact(30 ether);
        vm.startPrank(address(vault));
        uint256 balanceBefore = IERC20(WETH_MAINNET).balanceOf(address(vault));
        uint256 losses = strategy.liquidateExact(30 ether);
        uint256 withdrawn = IERC20(WETH_MAINNET).balanceOf(address(vault)) - balanceBefore;
        // withdraw exactly what requested
        assertEq(withdrawn, 30 ether);
        // losses are equal or fewer than expected
        assertLe(losses, requestedAmount - 30 ether);
    }

    function testSommelierTurboDivEth__maxLiquidateExact() public {
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

    function testSommelierTurboDivEth__MaxLiquidate() public {
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
            keccak256(abi.encode(address(CELLAR_BAL_MAINNET), uint256(6))),
            bytes32(uint256(uint8(1)))
        );
    }

    uint32 constant holdingPosition = uint32(7_000_003);

    function _shutDownCellar() internal {
        // keep the other values of the slot the same
        vm.store(
            CELLAR_BAL_MAINNET,
            bytes32(uint256(7)),
            bytes32(
                abi.encodePacked(
                    uint192(6_277_101_735_386_680_763_835_789_423_207_666_416_102_355_444_464_034_512_895),
                    false,
                    true,
                    false,
                    false,
                    holdingPosition
                )
            )
        );
    }

    function testSommelierTurboDivEth__SimulateHarvest() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 ether, users.alice);

        vm.startPrank(users.keeper);
        (uint256 expectedBalance, uint256 outputAfterInvestment) = strategy.simulateHarvest();

        strategy.harvest(expectedBalance, outputAfterInvestment, address(0), block.timestamp);
    }
}
