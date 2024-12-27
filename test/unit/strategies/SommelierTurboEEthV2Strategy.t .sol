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
import { SommelierTurboEEthV2StrategyWrapper } from "../../mock/SommelierTurboEEthV2StrategyWrapper.sol";
import { MaxApyVault } from "src/MaxApyVault.sol";
import "src/helpers/AddressBook.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { ICellar } from "src/interfaces/ICellar.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";

import { SommelierTurboEEthV2Strategy } from "src/strategies/mainnet/WETH/sommelier/SommelierTurboEEthV2Strategy.sol";

contract SommelierTurboEEthV2StrategyTest is BaseTest, StrategyEvents {
    address public constant CELLAR_WETH_MAINNET = SOMMELIER_TURBO_EETHV2_CELLAR_MAINNET;
    address public TREASURY;

    IStrategyWrapper public strategy;
    SommelierTurboEEthV2StrategyWrapper public implementation;
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
        implementation = new SommelierTurboEEthV2StrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32("MaxApy Sommelier Strategy"),
                users.alice,
                CELLAR_WETH_MAINNET
            )
        );
        vm.label(CELLAR_WETH_MAINNET, "Cellar");
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "SommelierTurbStEthStrategy");
        vm.label(address(WETH_MAINNET), "WETH");

        strategy = IStrategyWrapper(address(_proxy));

        IERC20(WETH_MAINNET).approve(address(vault), type(uint256).max);
        vm.rollFork(19_417_251);
    }

    /*==================INITIALIZATION TESTS===================*/

    function testSommelierTurboEEthV2__Initialization() public {
        MaxApyVault _vault = new MaxApyVault(users.alice, WETH_MAINNET, "MaxApyWETHVault", "maxWETH", TREASURY);
        ProxyAdmin _proxyAdmin = new ProxyAdmin(users.alice);
        SommelierTurboEEthV2StrategyWrapper _implementation = new SommelierTurboEEthV2StrategyWrapper();

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
                CELLAR_WETH_MAINNET
            )
        );

        IStrategyWrapper _strategy = IStrategyWrapper(address(_proxy));

        assertEq(_strategy.vault(), address(_vault));
        assertEq(_strategy.hasAnyRole(_strategy.vault(), _strategy.VAULT_ROLE()), true);
        assertEq(_strategy.underlyingAsset(), WETH_MAINNET);
        assertEq(IERC20(WETH_MAINNET).allowance(address(_strategy), address(_vault)), type(uint256).max);
        assertEq(_strategy.hasAnyRole(users.keeper, _strategy.KEEPER_ROLE()), true);
        assertEq(_strategy.hasAnyRole(users.alice, _strategy.ADMIN_ROLE()), true);
        assertEq(_strategy.strategyName(), bytes32("MaxApy Sommelier Strategy"));
        assertEq(_strategy.cellar(), CELLAR_WETH_MAINNET);
        assertEq(IERC20(WETH_MAINNET).allowance(address(_strategy), CELLAR_WETH_MAINNET), type(uint256).max);

        assertEq(_proxyAdmin.owner(), users.alice);
        vm.startPrank(address(_proxyAdmin));
        // assertEq(proxyInit.admin(), address(_proxyAdmin));
        vm.stopPrank();

        vm.startPrank(users.alice);
    }

    /*==================STRATEGY CONFIGURATION TESTS==================*/

    function testSommelierTurboEEthV2__SetEmergencyExit() public {
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

    function testSommelierTurboEEthV2__IsActive() public {
        vault.addStrategy(address(strategy), 10_000, 0, 0, 0);
        assertEq(strategy.isActive(), false);

        deal(WETH_MAINNET, address(strategy), 1 ether);
        assertEq(strategy.isActive(), false);

        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
        vm.stopPrank();

        strategy.divest(ICellar(CELLAR_WETH_MAINNET).balanceOf(address(strategy)));
        vm.startPrank(address(strategy));
        IERC20(WETH_MAINNET).transfer(makeAddr("random"), IERC20(WETH_MAINNET).balanceOf(address(strategy)));
        assertEq(strategy.isActive(), false);

        deal(WETH_MAINNET, address(strategy), 1 ether);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
    }

    function testSommelierTurboEEthV2__SetStrategist() public {
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
    function testSommelierTurboEEthV2__InvestmentSlippage() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        vm.startPrank(users.keeper);

        // Expect revert if output amount is gt amount obtained
        vm.expectRevert(abi.encodeWithSignature("MinOutputAmountNotReached()"));
        strategy.harvest(0, type(uint256).max, address(0), block.timestamp);
    }

    function testSommelierTurboEEthV2__PrepareReturn() public {
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

        deal({ token: WETH_MAINNET, to: address(strategy), give: 60 ether });
        strategy.investSommelier(60 ether);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        uint256 beforeReturnSnapshotId = vm.snapshot();

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);
        // 60 ETH - losses from the previous 10 ETH investment
        // assertEq(realizedProfit, 59.928542750254091025 ether); // 59.92 ETH
        assertEq(unrealizedProfit, 59.946371111970176828 ether); // 59.94 ETH
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);
        // assertEq(realizedProfit, 5.994637111197017682 ether); // 5.9 ETH
        assertEq(unrealizedProfit, 59.946371111970176828 ether); // 59.94 ETH
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);
        // assertEq(realizedProfit, 0); // 0
        assertEq(unrealizedProfit, 59.946371111970176828 ether); // 59.94 ETH
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

    function testSommelierTurboEEthV2__AdjustPosition() public {
        strategy.adjustPosition();
        assertEq(IERC20(CELLAR_WETH_MAINNET).balanceOf(address(strategy)), 0);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 expectedShares = strategy.sharesForAmount(10 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 10 ether);
        strategy.adjustPosition();
        assertEq(expectedShares, IERC20(CELLAR_WETH_MAINNET).balanceOf(address(strategy)));

        deal({ token: WETH_MAINNET, to: address(strategy), give: 100 ether });
        expectedShares += strategy.sharesForAmount(100 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 100 ether);
        strategy.adjustPosition();
        assertEq(expectedShares, IERC20(CELLAR_WETH_MAINNET).balanceOf(address(strategy)));

        deal({ token: WETH_MAINNET, to: address(strategy), give: 500 ether });
        expectedShares += strategy.sharesForAmount(500 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 500 ether);
        strategy.adjustPosition();
        assertEq(expectedShares, IERC20(CELLAR_WETH_MAINNET).balanceOf(address(strategy)));
    }

    function testSommelierTurboEEthV2__Invest() public {
        uint256 returned = strategy.invest(0, 0);
        assertEq(returned, 0);
        assertEq(IERC20(CELLAR_WETH_MAINNET).balanceOf(address(strategy)), 0);

        vm.expectRevert(abi.encodeWithSignature("NotEnoughFundsToInvest()"));
        returned = strategy.invest(1, 0);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 expectedShares = strategy.sharesForAmount(10 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 10 ether);
        strategy.invest(10 ether, 0);
        assertEq(expectedShares, IERC20(CELLAR_WETH_MAINNET).balanceOf(address(strategy)));
    }

    function testSommelierTurboEEthV2__Invest_CellarIsShutdown() public {
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 snapshotId = vm.snapshot();
        _shutDownCellar();
        // if cellar is shut down no funds are invested
        assertEq(strategy.invest(10 ether, 0), 0);
        vm.revertTo(snapshotId);
        assertGt(strategy.invest(10 ether, 0), 0);
    }

    function testSommelierTurboEEthV2__Invest_CellarIsPaused() public {
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 snapshotId = vm.snapshot();
        _pauseCellar();
        // if cellar is shut down no funds are invested
        assertEq(strategy.invest(10 ether, 0), 0);
        vm.revertTo(snapshotId);
        assertGt(strategy.invest(10 ether, 0), 0);
    }

    function testSommelierTurboEEthV2__Divest() public {
        deal({ token: WETH_MAINNET, to: address(strategy), give: 1000 ether });
        uint256 expectedShares = strategy.sharesForAmount(1000 ether);
        uint256 amountExpectedFromShares = strategy.shareValue(expectedShares);
        strategy.invest(1000 ether, 0);
        assertEq(expectedShares, IERC20(CELLAR_WETH_MAINNET).balanceOf(address(strategy)));

        uint256 strategyBalanceBefore = IERC20(WETH_MAINNET).balanceOf(address(strategy));
        vm.expectEmit();
        emit Divested(address(strategy), expectedShares, amountExpectedFromShares);
        uint256 amountDivested = strategy.divest(expectedShares);
        assertEq(amountDivested, amountExpectedFromShares);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + amountDivested);
    }

    function testSommelierTurboEEthV2__Divest_CellarIsPaused() public {
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
    function testSommelierTurboEEthV2__LiquidatePosition() public {
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
        assertEq(liquidatedAmount, expectedLiquidatedAmount);
        assertEq(loss, 15 ether - expectedLiquidatedAmount);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 1000 ether });
        strategy.invest(1000 ether, 0);
        deal({ token: WETH_MAINNET, to: address(strategy), give: 500 ether });
        (liquidatedAmount, loss) = strategy.liquidatePosition(1000 ether);

        expectedLiquidatedAmount = 500 ether + strategy.shareValue(strategy.sharesForAmount(500 ether));
        assertEq(liquidatedAmount, expectedLiquidatedAmount);
        assertEq(loss, 1000 ether - expectedLiquidatedAmount);
    }

    function testSommelierTurboEEthV2__LiquidateAllPositions() public {
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 expectedShares = strategy.sharesForAmount(10 ether);
        strategy.invest(10 ether, 0);
        assertEq(expectedShares, IERC20(CELLAR_WETH_MAINNET).balanceOf(address(strategy)));

        uint256 strategyBalanceBefore = IERC20(WETH_MAINNET).balanceOf(address(strategy));
        uint256 amountFreed = strategy.liquidateAllPositions();
        uint256 expectedAmountFreed = strategy.shareValue(strategy.sharesForAmount(10 ether));
        assertEq(amountFreed, expectedAmountFreed);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + expectedAmountFreed);
        assertEq(IERC20(CELLAR_WETH_MAINNET).balanceOf(address(strategy)), 0);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 500 ether });
        expectedShares = strategy.sharesForAmount(500 ether);
        strategy.invest(500 ether, 0);
        assertEq(expectedShares, IERC20(CELLAR_WETH_MAINNET).balanceOf(address(strategy)));

        strategyBalanceBefore = IERC20(WETH_MAINNET).balanceOf(address(strategy));
        amountFreed = strategy.liquidateAllPositions();
        expectedAmountFreed = strategy.shareValue(strategy.sharesForAmount(500 ether));
        assertEq(amountFreed, expectedAmountFreed);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + expectedAmountFreed);
        assertEq(IERC20(CELLAR_WETH_MAINNET).balanceOf(address(strategy)), 0);
    }

    function testSommelierTurboEEthV2__Harvest() public {
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.harvest(0, 0, address(0), block.timestamp);

        uint256 snapshotId = vm.snapshot();

        vault.deposit(100 ether, users.alice);
        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vm.expectEmit();

        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, 40 ether, 40 ether, 4000);
        vm.stopPrank();
        uint256 expectedStrategyShareBalance = strategy.sharesForAmount(40 ether);
        vm.startPrank(users.keeper);
        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        // strategy takes 40 eth
        strategy.harvest(0, 0, address(0), block.timestamp);

        // there are 60 eth left in the vault
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), 0);
        // strategy has expectedStrategyShareBalance cellar shares
        assertEq(IERC20(CELLAR_WETH_MAINNET).balanceOf(address(strategy)), expectedStrategyShareBalance);

        // strategy gets 10 eth more as profit
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });

        vm.expectEmit();
        emit StrategyReported(address(strategy), 10 ether, 0, 0, 10 ether, 0, 40 ether, 0, 4000);

        vm.expectEmit();
        uint256 newExpectedStrategyShareBalance = expectedStrategyShareBalance + strategy.sharesForAmount(10 ether);
        emit Harvested(10 ether, 0, 0, 0);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), 0);
        assertEq(IERC20(CELLAR_WETH_MAINNET).balanceOf(address(strategy)), newExpectedStrategyShareBalance);

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
        assertEq(IERC20(CELLAR_WETH_MAINNET).balanceOf(address(strategy)), expectedStrategyShareBalance);

        vm.startPrank(users.alice);
        strategy.setEmergencyExit(2);

        vm.startPrank(users.keeper);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 40 ether, 0, 0, 0, 0, 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 49.964247407980117886 ether, 0);

        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 109.964247407980117886 ether);
        assertEq(IERC20(CELLAR_WETH_MAINNET).balanceOf(address(strategy)), 0);

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
        assertEq(IERC20(CELLAR_WETH_MAINNET).balanceOf(address(strategy)), expectedStrategyShareBalance);

        uint256 expectedShares = strategy.sharesForAmount(10 ether);

        vm.startPrank(address(strategy));
        IERC20(CELLAR_WETH_MAINNET).transfer(makeAddr("random"), expectedShares);

        vm.startPrank(users.keeper);
        vm.expectEmit();
        emit StrategyReported(
            address(strategy),
            // vault realized gain
            0,
            // vault unrealized gain
            9.991061851995029472 ether,
            0,
            0,
            9.991061851995029472 ether,
            30.008938148004970528 ether,
            0,
            3001
        );

        vm.expectEmit();
        emit Harvested(0, 9.991061851995029472 ether, 0, 2_997_255_809_788_678_873);
        // only losses , no effect
        strategy.harvest(0, 0, address(0), block.timestamp);

        StrategyData memory data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3001);
        assertEq(vault.totalDebt(), 30.008938148004970528 ether);
        assertEq(data.strategyDebtRatio, 3001);
        assertEq(data.strategyTotalDebt, 30.008938148004970528 ether);
        assertEq(data.strategyTotalLoss, 9.991061851995029472 ether);
    }

    function testSommelierTurboEEthV2__Harvest_CellarIsShutdown_Paused() public {
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
        assertEq(IERC20(CELLAR_WETH_MAINNET).balanceOf(address(strategy)), 0);

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
        assertEq(IERC20(CELLAR_WETH_MAINNET).balanceOf(address(strategy)), 0);

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
        assertGt(IERC20(CELLAR_WETH_MAINNET).balanceOf(address(strategy)), 0);

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
        assertGt(IERC20(CELLAR_WETH_MAINNET).balanceOf(address(strategy)), 0);
    }

    function testSommelierTurboEEthV2__PreviewLiquidate() public {
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

    function testSommelierTurboEEthV2__PreviewLiquidateExact() public {
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

    function testSommelierTurboEEthV2__maxLiquidateExact() public {
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

    function testSommelierTurboEEthV2__MaxLiquidate() public {
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
            keccak256(abi.encode(address(CELLAR_WETH_MAINNET), uint256(6))),
            bytes32(uint256(uint8(1)))
        );
    }

    uint32 constant holdingPosition =
        uint32(uint256(26_959_946_667_150_639_794_667_015_087_019_630_673_637_144_422_540_572_481_103_610_249_216));

    function _shutDownCellar() internal {
        // keep the other values of the slot the same
        vm.store(
            CELLAR_WETH_MAINNET,
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

    function testSommelierTurboEEthV2__SimulateHarvest() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 ether, users.alice);

        vm.startPrank(users.keeper);
        (uint256 expectedBalance, uint256 outputAfterInvestment,,,,) = strategy.simulateHarvest();

        strategy.harvest(expectedBalance, outputAfterInvestment, address(0), block.timestamp);
    }
}
