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
import { IConvexBooster } from "src/interfaces/IConvexBooster.sol";
import { IUniswapV2Router02 as IRouter } from "src/interfaces/IUniswap.sol";

import { MaxApyVault } from "src/MaxApyVault.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { ConvexdETHFrxETHStrategy } from "src/strategies/mainnet/WETH/convex/ConvexdETHFrxETHStrategy.sol";
import { ConvexdETHFrxETHStrategyEvents } from "../../helpers/ConvexdETHFrxETHStrategyEvents.sol";
import "src/helpers/AddressBook.sol";
import { ConvexdETHFrxETHStrategyWrapper } from "../../mock/ConvexdETHFrxETHStrategyWrapper.sol";
import { MockConvexBooster } from "../../mock/MockConvexBooster.sol";
import { MockCurvePool } from "../../mock/MockCurvePool.sol";
import { IStrategyWrapper } from "../../interfaces/IStrategyWrapper.sol";

contract ConvexdETHFrxETHStrategyTest is BaseTest, ConvexdETHFrxETHStrategyEvents {
    IERC20 public constant crv = IERC20(CRV_MAINNET);
    IERC20 public constant cvx = IERC20(CVX_MAINNET);
    IERC20 public constant frxEth = IERC20(FRXETH_MAINNET);
    IRouter public constant SUSHISWAP_ROUTER = IRouter(SUSHISWAP_ROUTER_MAINNET);

    address public TREASURY;

    IStrategyWrapper public strategy;
    ConvexdETHFrxETHStrategyWrapper public implementation;
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
        implementation = new ConvexdETHFrxETHStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address,address)",
                address(vault),
                keepers,
                users.alice,
                bytes32(abi.encode("MaxApy dETH<>frxETH Strategy")),
                CURVE_DETH_FRXETH_POOL_MAINNET,
                CURVE_ETH_FRXETH_POOL_MAINNET,
                address(SUSHISWAP_ROUTER)
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));

        strategy = IStrategyWrapper(address(_proxy));

        IERC20(WETH_MAINNET).approve(address(vault), type(uint256).max);
    }

    /*==================INITIALIZATION TESTS==================*/

    function testConvexdETHFrxETH__Initialization() public {
        MaxApyVault _vault = new MaxApyVault(users.alice, WETH_MAINNET, "MaxApyWETHVault", "maxWETH", TREASURY);

        ProxyAdmin _proxyAdmin = new ProxyAdmin(users.alice);
        ConvexdETHFrxETHStrategyWrapper _implementation = new ConvexdETHFrxETHStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;

        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(_implementation),
            address(_proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address,address)",
                address(_vault),
                keepers,
                bytes32(abi.encode("MaxApy dETH<>frxETH Strategy")),
                users.alice,
                CURVE_DETH_FRXETH_POOL_MAINNET,
                CURVE_ETH_FRXETH_POOL_MAINNET,
                SUSHISWAP_ROUTER
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
        assertEq(_strategy.strategyName(), bytes32(abi.encode("MaxApy Convex ETH Strategy")));
        assertEq(_strategy.convexBooster(), CONVEX_BOOSTER_MAINNET);
        assertEq(_strategy.router(), address(SUSHISWAP_ROUTER));

        /*   assertNotEq(_strategy.convexRewardPool(), address(0));
        assertNotEq(_strategy.convexLpToken(), address(0));
        assertNotEq(_strategy.rewardToken(), address(0)); */

        assertEq(_strategy.curveLpPool(), CURVE_DETH_FRXETH_POOL_MAINNET);
        assertEq(_strategy.curveEthFrxEthPool(), CURVE_ETH_FRXETH_POOL_MAINNET);
        assertEq(
            IERC20(_strategy.curveLpPool()).allowance(address(_strategy), address(_strategy.convexBooster())),
            type(uint256).max
        );
        assertEq(IERC20(crv).allowance(address(_strategy), address(_strategy.router())), type(uint256).max);
        assertEq(IERC20(cvx).allowance(address(_strategy), address(_strategy.cvxWethPool())), type(uint256).max);
        assertEq(
            IERC20(frxEth).allowance(address(_strategy), address(_strategy.curveEthFrxEthPool())), type(uint256).max
        );

        assertEq(_strategy.maxSingleTrade(), 1000 * 1e18);

        assertEq(_strategy.minSwapCrv(), 1e17);

        assertEq(_strategy.minSwapCvx(), 1e18);

        assertEq(_proxyAdmin.owner(), users.alice);
        vm.startPrank(address(_proxyAdmin));
        // assertEq(proxyInit.admin(), address(_proxyAdmin));
        vm.stopPrank();

        vm.startPrank(users.alice);
    }

    //  /*==================STRATEGY CONFIGURATION TESTS==================*/

    function testConvexdETHFrxETH__SetEmergencyExit() public {
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

    function testConvexdETHFrxETH__SetMaxSingleTrade() public {
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

    function testConvexdETHFrxETH__IsActive() public {
        vault.addStrategy(address(strategy), 10_000, 0, 0, 0);
        assertEq(strategy.isActive(), false);

        deal(WETH_MAINNET, address(strategy), 1 ether);
        assertEq(strategy.isActive(), false);

        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
        vm.stopPrank();

        strategy.liquidateAllPositions();
        vm.startPrank(address(strategy));
        IERC20(WETH_MAINNET).transfer(makeAddr("random"), IERC20(WETH_MAINNET).balanceOf(address(strategy)));
        assertEq(strategy.isActive(), false);
        /* 
        deal(WETH_MAINNET, address(strategy), 1 ether);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, 0, address(0),block.timestamp);
        assertEq(strategy.isActive(), true); */
    }

    function testConvexdETHFrxETH__SetMinSwaps() public {
        // Negatives
        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setMinSwapCrv(1e19);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setMinSwapCvx(1e19);

        // Positives
        vm.startPrank(users.alice);
        vm.expectEmit();
        emit MinSwapCrvUpdated(1e19);
        strategy.setMinSwapCrv(1e19);
        assertEq(strategy.minSwapCrv(), 10e18);

        vm.expectEmit();
        emit MinSwapCvxUpdated(1e20);
        strategy.setMinSwapCvx(1e20);
        assertEq(strategy.minSwapCvx(), 1e20);
    }

    function testConvexdETHFrxETH__SetRouter() public {
        address router = makeAddr("router");
        address router2 = makeAddr("router2");
        // Negatives
        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setRouter(router);

        // Positives
        vm.startPrank(users.alice);
        vm.expectEmit();
        emit RouterUpdated(router);
        strategy.setRouter(router);
        assertEq(crv.allowance(address(strategy), router), type(uint256).max);

        vm.expectEmit();
        emit RouterUpdated(router2);
        strategy.setRouter(router2);
        assertEq(crv.allowance(address(strategy), router), 0);
        assertEq(crv.allowance(address(strategy), router2), type(uint256).max);
    }

    /*==================STRATEGY CORE LOGIC TESTS==================*/

    function testConvexdETHFrxETH__Slippage() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        vm.startPrank(users.keeper);

        strategy.harvest(0, 0, address(0), block.timestamp);

        deal({ token: address(crv), to: users.keeper, give: 10 ether });
        deal({ token: address(cvx), to: users.keeper, give: 10 ether });
        crv.approve(strategy.router(), type(uint256).max);
        cvx.approve(strategy.cvxWethPool(), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(crv);
        path[1] = WETH_MAINNET;

        uint256[] memory expectedAmountCrv =
            IRouter(strategy.router()).swapExactTokensForTokens(10 ether, 0, path, users.keeper, block.timestamp);

        uint256 expectedAmountCvx = ICurveLpPool(strategy.cvxWethPool()).exchange(1, 0, 10 ether, 0, false);

        deal({ token: address(crv), to: address(strategy), give: 10 ether });
        deal({ token: address(cvx), to: address(strategy), give: 10 ether });

        // Apply 1% difference
        uint256 minimumExpectedEthAmount = (expectedAmountCrv[1] + expectedAmountCvx) * 9999 / 10_000;
        // Setting a higher amount should fail
        vm.expectRevert(abi.encodeWithSignature("MinExpectedBalanceAfterSwapNotReached()"));
        strategy.harvest(expectedAmountCrv[1] + expectedAmountCvx + 1, 0, address(0), block.timestamp);

        // Setting a proper amount should allow swapping
        strategy.harvest(minimumExpectedEthAmount, 0, address(0), block.timestamp);
    }

    function testConvexdETHFrxETH__InvestmentSlippage() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        vm.startPrank(users.keeper);

        strategy.harvest(0, 0, address(0), block.timestamp);

        deal({ token: address(crv), to: users.keeper, give: 10 ether });
        deal({ token: address(cvx), to: users.keeper, give: 10 ether });
        crv.approve(strategy.router(), type(uint256).max);
        cvx.approve(strategy.cvxWethPool(), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(crv);
        path[1] = WETH_MAINNET;

        uint256[] memory expectedAmountCrv =
            IRouter(strategy.router()).swapExactTokensForTokens(10 ether, 0, path, users.keeper, block.timestamp);

        uint256 expectedAmountCvx = ICurveLpPool(strategy.cvxWethPool()).exchange(1, 0, 10 ether, 0, false);

        deal({ token: address(crv), to: address(strategy), give: 10 ether });
        deal({ token: address(cvx), to: address(strategy), give: 10 ether });

        // Apply 1% difference
        uint256 minimumExpectedEthAmount = (expectedAmountCrv[1] + expectedAmountCvx) * 9999 / 10_000;

        // Expect revert if output amount is gt amount obtained
        vm.expectRevert(abi.encodeWithSignature("MinOutputAmountNotReached()"));
        strategy.harvest(minimumExpectedEthAmount, type(uint256).max, address(0), block.timestamp);
    }

    function testConvexdETHFrxETH__PrepareReturn() public {
        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        (uint256 unrealizedProfit, uint256 loss, uint256 debtPayment) = strategy.prepareReturn(1 ether, 0);
        // assertEq(realizedProfit, 0);
        assertEq(loss, 0);
        assertEq(debtPayment, 1 ether);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();
        deal({ token: WETH_MAINNET, to: address(strategy), give: 60 ether });
        strategy.adjustPosition();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        uint256 beforeReturnSnapshotId = vm.snapshot();

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        // assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 60.000917856955753877 ether);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        // assertEq(realizedProfit, 59.93647432839715601 ether);
        assertEq(unrealizedProfit, 60.000917856955753877 ether);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        // assertEq(realizedProfit, 18.000275357086726163 ether);
        assertEq(unrealizedProfit, 60.000917856955753877 ether);
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

        snapshotId = vm.snapshot();

        deal({ token: WETH_MAINNET, to: address(strategy), give: 80 ether });

        strategy.adjustPosition();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        strategy.setMaxSingleTrade(1000);

        strategy.mockReport(0, 0, 0, TREASURY);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        // assertEq(realizedProfit, 40 ether + 1000);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
    }

    function testConvexdETHFrxETH__AdjustPosition() public {
        strategy.adjustPosition();
        assertEq(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);

        uint256 snapshotId = vm.snapshot();

        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 expectedLp = strategy.lpForAmount(10 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 10 ether);
        strategy.adjustPosition();
        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        deal({ token: WETH_MAINNET, to: address(strategy), give: 100 ether });
        expectedLp = strategy.lpForAmount(100 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 100 ether);
        strategy.adjustPosition();
        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        deal({ token: WETH_MAINNET, to: address(strategy), give: 500 ether });
        expectedLp = strategy.lpForAmount(500 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 500 ether);
        strategy.adjustPosition();

        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();
    }

    function testConvexdETHFrxETH__Invest() public {
        uint256 returned = strategy.invest(0, 0);
        assertEq(returned, 0);
        assertEq(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);

        vm.expectRevert(abi.encodeWithSignature("NotEnoughFundsToInvest()"));
        returned = strategy.invest(1, 0);

        uint256 snapshotId = vm.snapshot();

        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 expectedLp = strategy.lpForAmount(10 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 10 ether);
        strategy.invest(10 ether, 0);

        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), expectedLp - 2 ether);
        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        strategy.setMaxSingleTrade(1 ether);
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        expectedLp = strategy.lpForAmount(1 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 1 ether);
        strategy.invest(10 ether, 0);

        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), expectedLp - 1 ether);
    }

    function testConvexdETHFrxETH__Divest() public {
        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 expectedLp = strategy.lpForAmount(10 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 10 ether);
        strategy.invest(10 ether, 0);
        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), expectedLp - 1 ether);

        uint256 strategyBalanceBefore = IERC20(WETH_MAINNET).balanceOf(address(strategy));
        uint256 amountDivested = strategy.divest(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)));

        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + amountDivested);
    }

    function testConvexdETHFrxETH__LiquidatePosition() public {
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
        (liquidatedAmount, loss) = strategy.liquidatePosition(15 ether);
        assertGt(liquidatedAmount, 14.99 ether);
        assertLt(loss, 0.2 ether);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 50 ether });
        invested = strategy.invest(50 ether, 0);

        (liquidatedAmount, loss) = strategy.liquidatePosition(50 ether);

        assertGt(liquidatedAmount, 49.9 ether);
        assertLt(loss, 0.2 ether);
    }

    function testConvexdETHFrxETH__LiquidateAllPositions() public {
        uint256 snapshotId = vm.snapshot();

        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        uint256 expectedLp = strategy.lpForAmount(10 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 10 ether);
        strategy.invest(10 ether, 0);

        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), expectedLp - 2 ether);

        uint256 strategyBalanceBefore = IERC20(WETH_MAINNET).balanceOf(address(strategy));
        uint256 amountFreed = strategy.liquidateAllPositions();

        assertGt(amountFreed, 9 ether);

        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + amountFreed);
        assertEq(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 500 ether });
        expectedLp = strategy.lpForAmount(500 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 500 ether);
        strategy.invest(500 ether, 0);

        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), expectedLp - 50 ether);

        strategyBalanceBefore = IERC20(WETH_MAINNET).balanceOf(address(strategy));
        amountFreed = strategy.liquidateAllPositions();

        assertGt(amountFreed, 9 ether);

        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + amountFreed);
        assertEq(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);
    }

    function testConvexdETHFrxETH__UnwindRewards() public {
        deal({ token: WETH_MAINNET, to: address(strategy), give: 100 ether });
        vm.expectEmit();
        emit Invested(address(strategy), 100 ether);
        strategy.invest(100 ether, 0);

        strategy.unwindRewards();
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), 0);

        vm.warp(block.timestamp + 30 days);

        assertEq(IERC20(WETH_MAINNET).balanceOf(address(strategy)), 0);
        strategy.unwindRewards();
        assertEq(IERC20(cvx).balanceOf(address(strategy)), 0);
        assertEq(IERC20(crv).balanceOf(address(strategy)), 0);
        assertGt(IERC20(WETH_MAINNET).balanceOf(address(strategy)), 0);
    }

    function testConvexdETHFrxETH__Harvest() public {
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.harvest(0, 0, address(0), block.timestamp);

        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, 40 ether, 40 ether, 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);

        strategy.harvest(0, 0, address(0), block.timestamp);

        uint256 expectedStrategyLpBalance = strategy.lpForAmount(40 ether);
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
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, 40 ether, 40 ether, 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);

        strategy.harvest(0, 0, address(0), block.timestamp);

        expectedStrategyLpBalance = strategy.lpForAmount(40 ether);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);

        vm.startPrank(users.alice);
        strategy.setEmergencyExit(2);

        vm.startPrank(users.keeper);

        deal({ token: WETH_MAINNET, to: address(strategy), give: 10 ether });
        vm.warp(block.timestamp + 1 days);

        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 110.011279484032002561 ether);
        assertEq(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);
        vm.revertTo(snapshotId);

        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        expectedStrategyLpBalance = strategy.lpForAmount(40 ether);
        vault.deposit(100 ether, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, 40 ether, 40 ether, 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        strategy.harvest(0, 0, address(0), block.timestamp);

        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 60 ether);

        uint256 expectedLp = strategy.lpForAmount(10 ether);

        vm.startPrank(address(strategy));
        uint256 withdrawn = strategy.divest(expectedLp);

        IERC20(WETH_MAINNET).transfer(makeAddr("random"), withdrawn);
        vm.startPrank(users.keeper);

        strategy.harvest(0, 0, address(0), block.timestamp);

        StrategyData memory data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 2996);
        assertEq(data.strategyDebtRatio, 2996);
    }

    function testConvexdETHFrxETH__PreviewLiquidate() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 ether, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 expected = strategy.previewLiquidate(30 ether);
        vm.startPrank(address(vault));
        uint256 loss = strategy.liquidate(30 ether);
        assertEq(expected, 30 ether - loss);
    }

    function testConvexdETHFrxETH__PreviewLiquidateExact() public {
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

    function testConvexdETHFrxETH__maxLiquidateExact() public {
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

    function testConvexdETHFrxETH__MaxLiquidate() public {
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
}
