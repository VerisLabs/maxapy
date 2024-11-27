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

import { BeefyaltETHfrxETHStrategyWrapper } from "../../mock/BeefyaltETHfrxETHStrategyWrapper.sol";

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { MaxApyVault } from "src/MaxApyVault.sol";
import "src/helpers/AddressBook.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";

contract BeefyaltETHfrxETHStrategyTest is BaseTest, ConvexdETHFrxETHStrategyEvents {
    using SafeTransferLib for address;

    address public TREASURY;
    IStrategyWrapper public strategy;
    BeefyaltETHfrxETHStrategyWrapper public implementation;
    MaxApyVault public vaultDeployment;
    IMaxApyVault public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;

    function setUp() public {
        super._setUp("MAINNET");
        vm.rollFork(20_790_660);

        TREASURY = makeAddr("treasury");

        vaultDeployment = new MaxApyVault(users.alice, WETH_MAINNET, "MaxApyWETHVault", "maxWETH", TREASURY);

        vault = IMaxApyVault(address(vaultDeployment));

        proxyAdmin = new ProxyAdmin(users.alice);
        implementation = new BeefyaltETHfrxETHStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address,address)",
                address(vault),
                keepers,
                bytes32("MaxApy ALTETH<>FRXETH Strategy"),
                users.alice,
                CURVE_ALTETH_FRXETH_MAINNET,
                BEEFY_ALTETH_FRXETH_MAINNET,
                CURVE_ETH_FRXETH_POOL_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));

        strategy = IStrategyWrapper(address(_proxy));
        WETH_MAINNET.safeApprove(address(vault), type(uint256).max);

        vm.label(WETH_MAINNET, "WETH_MAINNET");
    }

    /*==================INITIALIZATION TESTS==================*/

    function testBeefyaltETHfrxETH__Initialization() public {
        MaxApyVault _vault = new MaxApyVault(users.alice, WETH_MAINNET, "MaxApyUSDCEVault", "maxUSDCE", TREASURY);

        ProxyAdmin _proxyAdmin = new ProxyAdmin(users.alice);
        BeefyaltETHfrxETHStrategyWrapper _implementation = new BeefyaltETHfrxETHStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;

        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(_implementation),
            address(_proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address,address)",
                address(_vault),
                keepers,
                bytes32("MaxApy ALTETH<>FRXETH Strategy"),
                users.alice,
                CURVE_ALTETH_FRXETH_MAINNET,
                BEEFY_ALTETH_FRXETH_MAINNET,
                CURVE_ETH_FRXETH_POOL_MAINNET
            )
        );

        IStrategyWrapper _strategy = IStrategyWrapper(address(_proxy));
        assertEq(_strategy.vault(), address(_vault));

        assertEq(_strategy.hasAnyRole(address(_vault), _strategy.VAULT_ROLE()), true);
        assertEq(_strategy.underlyingAsset(), WETH_MAINNET);
        assertEq(IERC20(WETH_MAINNET).allowance(address(_strategy), address(_vault)), type(uint256).max);
        assertEq(_strategy.hasAnyRole(users.keeper, _strategy.KEEPER_ROLE()), true);
        assertEq(_strategy.hasAnyRole(users.alice, _strategy.ADMIN_ROLE()), true);

        assertEq(_strategy.owner(), users.alice);
        assertEq(_strategy.strategyName(), bytes32("MaxApy ALTETH<>FRXETH Strategy"));

        assertEq(_strategy.curveLpPool(), CURVE_ALTETH_FRXETH_MAINNET, "hereee");
        assertEq(IERC20(WETH_MAINNET).allowance(address(_strategy), CURVE_ALTETH_FRXETH_MAINNET), type(uint256).max);

        assertEq(_proxyAdmin.owner(), users.alice);
        vm.startPrank(address(_proxyAdmin));
        vm.stopPrank();

        vm.startPrank(users.alice);
    }

    /*==================STRATEGY CONFIGURATION TESTS==================*/

    function testBeefyaltETHfrxETH__SetEmergencyExit() public {
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

    function testBeefyaltETHfrxETH__SetMinSingleTrade() public {
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

    function testBeefyaltETHfrxETH__IsActive() public {
        vault.addStrategy(address(strategy), 10_000, 0, 0, 0);
        assertEq(strategy.isActive(), false);

        deal(WETH_MAINNET, address(strategy), 1 ether);
        assertEq(strategy.isActive(), false);

        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
        vm.stopPrank();

        strategy.divest(IERC20(BEEFY_ALTETH_FRXETH_MAINNET).balanceOf(address(strategy)));
        vm.startPrank(address(strategy));
        IERC20(WETH_MAINNET).transfer(makeAddr("random"), IERC20(WETH_MAINNET).balanceOf(address(strategy)));
        assertEq(strategy.isActive(), false);

        deal(WETH_MAINNET, address(strategy), 1 ether);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
    }

    function testBeefyaltETHfrxETH__SetStrategist() public {
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
    function testBeefyaltETHfrxETH__InvestmentSlippage() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        vm.startPrank(users.keeper);

        // Expect revert if output amount is gt amount obtained
        vm.expectRevert(abi.encodeWithSignature("MinOutputAmountNotReached()"));
        strategy.harvest(0, type(uint256).max, address(0), block.timestamp);
    }

    function testBeefyaltETHfrxETH__PrepareReturn() public {
        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        (uint256 unrealizedProfit, uint256 loss, uint256 debtPayment) = strategy.prepareReturn(1 ether, 0);

        assertEq(loss, 0);
        assertEq(debtPayment, 1 ether);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();
        deal({ token: WETH_MAINNET, to: address(strategy), give: 60 ether });

        strategy.adjustPosition();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        assertApproxEq(unrealizedProfit, 60 ether, 1 ether);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        strategy.triggerLoss(10 ether);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        assertEq(unrealizedProfit, 0);
        assertEq(loss, 10 ether);
        assertEq(debtPayment, 0);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        deal({ token: WETH_MAINNET, to: address(strategy), give: 80 ether });

        strategy.adjustPosition();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        assertEq(loss, 0);
        assertEq(debtPayment, 0);
    }

    function testBeefyaltETHfrxETH__Invest() public {
        uint256 returned = strategy.invest(0, 0);
        assertEq(returned, 0);
        assertEq(IERC20(BEEFY_ALTETH_FRXETH_MAINNET).balanceOf(address(strategy)), 0);

        vm.expectRevert(abi.encodeWithSignature("NotEnoughFundsToInvest()"));
        returned = strategy.invest(1, 0);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 expectedShares = strategy.sharesForAmount(10 ether);
        console2.log("###   ~ file: BeefyaltETHfrxETHStrategy.t.sol:292 ~ testBeefyaltETHfrxETH__Invest ~ expectedShares:", expectedShares);

        
        vm.expectEmit();
        emit Invested(address(strategy), 10 ether);
        strategy.invest(10 ether, 0);
        console2.log("###   ~ file: BeefyaltETHfrxETHStrategy.t.sol:304 ~ testBeefyaltETHfrxETH__Invest ~ IERC20(BEEFY_ALTETH_FRXETH_MAINNET).balanceOf(address(strategy)):", IERC20(BEEFY_ALTETH_FRXETH_MAINNET).balanceOf(address(strategy)));


        assertApproxEq(
            expectedShares, IERC20(BEEFY_ALTETH_FRXETH_MAINNET).balanceOf(address(strategy)), expectedShares / 10
        );
    }

    function testBeefyaltETHfrxETH__Divest() public {
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 expectedShares = strategy.sharesForAmount(10 ether);

        vm.expectEmit();
        emit Invested(address(strategy), 10 ether);
        strategy.invest(10 ether, 0);

        assertApproxEq(
            expectedShares, IERC20(BEEFY_ALTETH_FRXETH_MAINNET).balanceOf(address(strategy)), expectedShares / 10
        );

        uint256 strategyBalanceBefore = IERC20(WETH_MAINNET).balanceOf(address(strategy));
        uint256 amountDivested = strategy.divest(IERC20(BEEFY_ALTETH_FRXETH_MAINNET).balanceOf(address(strategy)));

        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + amountDivested);
    }

    function testBeefyaltETHfrxETH__LiquidatePosition() public {
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        (uint256 liquidatedAmount, uint256 loss) = strategy.liquidatePosition(1 ether);
        assertEq(liquidatedAmount, 1 ether);
        assertEq(loss, 0);

        (liquidatedAmount, loss) = strategy.liquidatePosition(10 ether);
        assertEq(liquidatedAmount, 10 ether);
        assertEq(loss, 0);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 5 ether });
        uint256 invested = strategy.invest(5 ether, 0);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });

        (liquidatedAmount, loss) = strategy.liquidatePosition(149 ether / 10);

        assertEq(liquidatedAmount, 149 ether / 10);
        assertLt(loss, 1 ether / 5);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 50 ether });
        invested = strategy.invest(50 ether, 0);

        (liquidatedAmount, loss) = strategy.liquidatePosition(495 ether / 10);

        assertEq(liquidatedAmount, 495 ether / 10);
        assertLt(loss, 1 ether / 5);
    }

    function testBeefyaltETHfrxETH__LiquidateAllPositions() public {
        uint256 snapshotId = vm.snapshot();

        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 shares = strategy.sharesForAmount(10 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 10 ether);
        strategy.invest(10 ether, 0);

        assertApproxEq(IERC20(BEEFY_ALTETH_FRXETH_MAINNET).balanceOf(address(strategy)), shares, shares / 10);

        uint256 strategyBalanceBefore = IERC20(WETH_MAINNET).balanceOf(address(strategy));
        uint256 amountFreed = strategy.liquidateAllPositions();

        assertApproxEq(amountFreed, 10 ether, 3 ether / 100);

        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + amountFreed);
        assertEq(IERC20(BEEFY_ALTETH_FRXETH_MAINNET).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 100 ether });
        shares = strategy.sharesForAmount(100 ether);

        vm.expectEmit();
        emit Invested(address(strategy), 100 ether);
        strategy.invest(100 ether, 0);

        assertApproxEq(IERC20(BEEFY_ALTETH_FRXETH_MAINNET).balanceOf(address(strategy)), shares, 2.5 ether);

        strategyBalanceBefore = IERC20(WETH_MAINNET).balanceOf(address(strategy));
        amountFreed = strategy.liquidateAllPositions();

        assertApproxEq(amountFreed, 100 ether, 2 ether);

        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + amountFreed);
        assertEq(IERC20(BEEFY_ALTETH_FRXETH_MAINNET).balanceOf(address(strategy)), 0);
    }

    function testBeefyaltETHfrxETH__Harvest() public {
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.harvest(0, 0, address(0), block.timestamp);

        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, uint128(40 ether), uint128(40 ether), 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);

        strategy.harvest(0, 0, address(0), block.timestamp);

        uint256 expectedStrategyShareBalance = strategy.sharesForAmount(40 ether);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), 0);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        vm.warp(block.timestamp + 1 days);

        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);

        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();

        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, uint128(40 ether), uint128(40 ether), 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);

        strategy.harvest(0, 0, address(0), block.timestamp);

        expectedStrategyShareBalance = strategy.sharesForAmount(40 ether);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);

        vm.startPrank(users.alice);
        strategy.setEmergencyExit(2);

        vm.startPrank(users.keeper);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        vm.warp(block.timestamp + 1 days);

        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 109956498446582789159);
        assertEq(IERC20(BEEFY_ALTETH_FRXETH_MAINNET).balanceOf(address(strategy)), 0);
        vm.revertTo(snapshotId);

        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        expectedStrategyShareBalance = strategy.sharesForAmount(40 ether);
        vault.deposit(100 ether, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, uint128(40 ether), uint128(40 ether), 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        strategy.harvest(0, 0, address(0), block.timestamp);

        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);

        expectedStrategyShareBalance = strategy.sharesForAmount(10 ether);

        vm.startPrank(address(strategy));
        uint256 withdrawn = strategy.divest(expectedStrategyShareBalance);

        IERC20(WETH_MAINNET).transfer(makeAddr("random"), withdrawn);
        vm.startPrank(users.keeper);

        strategy.harvest(0, 0, address(0), block.timestamp);

        StrategyData memory data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 2994);
        assertEq(data.strategyDebtRatio, 2994);
    }

    function testBeefyaltETHfrxETH__PreviewLiquidate() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 ether, users.alice);
        vm.startPrank(users.keeper);

        strategy.harvest(0, 0, address(0), block.timestamp);

        vm.stopPrank();
        uint256 expected = strategy.previewLiquidate(30 ether);
        console2.log("###   ~ file: BeefyaltETHfrxETHStrategy.t.sol:513 ~ testBeefyaltETHfrxETH__PreviewLiquidate ~ expected:", expected);

        vm.startPrank(address(vault));

        uint256 loss = strategy.liquidate(30 ether);
        console2.log("###   ~ file: BeefyaltETHfrxETHStrategy.t.sol:522 ~ testBeefyaltETHfrxETH__PreviewLiquidate ~ 30 ether - loss:", 30 ether - loss);

        assertLe(expected, 30 ether - loss);
    }
        


    function testBeefyaltETHfrxETH__PreviewLiquidateExact() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 ether, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 requestedAmount = strategy.previewLiquidateExact(30 ether);
        console2.log("###   ~ file: BeefyaltETHfrxETHStrategy.t.sol:527 ~ testBeefyaltETHfrxETH__PreviewLiquidateExact ~ requestedAmount:", requestedAmount);


        vm.startPrank(address(vault));
        uint256 balanceBefore = IERC20(WETH_MAINNET).balanceOf(address(vault));

        strategy.liquidateExact(30 ether);
        uint256 withdrawn = IERC20(WETH_MAINNET).balanceOf(address(vault)) - balanceBefore;

        // withdraw exactly what requested
        assertEq(withdrawn, 30 ether);
        // losses are equal or fewer than expected
        assertLe(withdrawn - 30 ether, requestedAmount - 30 ether);
    }

    function testBeefyaltETHfrxETH__maxLiquidateExact() public {
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

    function testBeefyaltETHfrxETH__MaxLiquidate() public {
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

    function testBeefyaltETHfrxETH___SimulateHarvest() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 ether, users.alice);
        vm.startPrank(users.keeper);
        (uint256 expectedBalance, uint256 outputAfterInvestment,,,,) = strategy.simulateHarvest();
        strategy.harvest(expectedBalance, outputAfterInvestment, address(0), block.timestamp);
    }

    function testBeefyaltETHfrxETH__PreviewLiquidate__FUZZY(uint256 amount) public {
        vm.assume(amount > 0.0001 ether && amount < 400 ether);
        deal(WETH_MAINNET, users.alice, amount);
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

    function testBeefyaltETHfrxETH__PreviewLiquidateExact__FUZZY(uint256 amount) public {
        vm.assume(amount > 0.0001 ether && amount < 400 ether);
        deal(WETH_MAINNET, users.alice, amount);
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(amount, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 requestedAmount = strategy.previewLiquidateExact(amount / 3);
        console2.log("###   ~ file: BeefyaltETHfrxETHStrategy.t.sol:614 ~ testBeefyaltETHfrxETH__PreviewLiquidateExact__FUZZY ~ requestedAmount:", requestedAmount);


        vm.startPrank(address(vault));
        uint256 balanceBefore = IERC20(WETH_MAINNET).balanceOf(address(vault));

        strategy.liquidateExact(amount / 3);
        uint256 withdrawn = IERC20(WETH_MAINNET).balanceOf(address(vault)) - balanceBefore;

        // withdraw exactly what requested
        assertGe(withdrawn, amount / 3);
        // losses are equal or fewer than expected
        assertLe(withdrawn - (amount / 3), requestedAmount - (amount / 3));
    }

    function testBeefyaltETHfrxETH__maxLiquidateExact__FUZZY(uint256 amount) public {
        vm.assume(amount > 0.0001 ether && amount < 270 ether);

        console2.log("###   ~ file: BeefyaltETHfrxETHStrategy.t.sol:648 ~ testBeefyaltETHfrxETH__maxLiquidateExact__FUZZY ~ amount:", amount);
        
        deal(WETH_MAINNET, users.alice, amount);
        vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
        vault.deposit(amount, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 maxLiquidateExact = strategy.maxLiquidateExact();
        console2.log("###   ~ file: BeefyaltETHfrxETHStrategy.t.sol:641 ~ testBeefyaltETHfrxETH__maxLiquidateExact__FUZZY ~ maxLiquidateExact:", maxLiquidateExact);

        uint256 balanceBefore = IERC20(WETH_MAINNET).balanceOf(address(vault));
        uint256 requestedAmount = strategy.previewLiquidateExact(maxLiquidateExact);
        console2.log("###   ~ file: BeefyaltETHfrxETHStrategy.t.sol:645 ~ testBeefyaltETHfrxETH__maxLiquidateExact__FUZZY ~ requestedAmount:", requestedAmount);

        vm.startPrank(address(vault));
        uint256 losses = strategy.liquidateExact(maxLiquidateExact);
        uint256 withdrawn = IERC20(WETH_MAINNET).balanceOf(address(vault)) - balanceBefore;
        // withdraw exactly what requested
        assertGe(withdrawn, maxLiquidateExact);
        // losses are equal or fewer than expected
        assertLe(losses, requestedAmount - maxLiquidateExact);
    }
        
    function testBeefyaltETHfrxETH__MaxLiquidate_FUZZY(uint256 amount) public {
        vm.assume(amount > 0.0001 ether && amount < 400 ether);
        deal(WETH_MAINNET, users.alice, amount);
        vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
        vault.deposit(amount, users.alice);
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
}
