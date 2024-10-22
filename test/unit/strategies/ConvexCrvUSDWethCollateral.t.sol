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
import { IUniswapV3Router as IRouter } from "src/interfaces/IUniswap.sol";

import { MaxApyVault } from "src/MaxApyVault.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { ConvexdETHFrxETHStrategyEvents } from "../../helpers/ConvexdETHFrxETHStrategyEvents.sol";
import "src/helpers/AddressBook.sol";
import { ConvexCrvUSDWethCollateralStrategyWrapper } from "../../mock/ConvexCrvUSDWethCollateralStrategyWrapper.sol";
import { MockConvexBooster } from "../../mock/MockConvexBooster.sol";
import { MockCurvePool } from "../../mock/MockCurvePool.sol";
import { IStrategyWrapper } from "../../interfaces/IStrategyWrapper.sol";
import { _1_USDC } from "test/helpers/Tokens.sol";
import "src/helpers/AddressBook.sol";

contract ConvexCrvUSDWethCollateralStrategyTest is BaseTest, ConvexdETHFrxETHStrategyEvents {
    address public TREASURY;
    IStrategyWrapper public strategy;
    ConvexCrvUSDWethCollateralStrategyWrapper public implementation;
    MaxApyVault public vaultDeployment;
    IMaxApyVault public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;

    function setUp() public {
        super._setUp("MAINNET");
        vm.rollFork(20_074_046);

        TREASURY = makeAddr("treasury");

        vaultDeployment = new MaxApyVault(users.alice, USDC_MAINNET, "MaxApyWETHVault", "maxWETH", TREASURY);

        vault = IMaxApyVault(address(vaultDeployment));

        proxyAdmin = new ProxyAdmin(users.alice);
        implementation = new ConvexCrvUSDWethCollateralStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy dETH<>frxETH Strategy")),
                users.alice,
                CURVE_CRVUSD_WETH_COLLATERAL_LENDING_POOL_MAINNET,
                CURVE_USDC_CRVUSD_POOL_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));

        strategy = IStrategyWrapper(address(_proxy));

        IERC20(USDC_MAINNET).approve(address(vault), type(uint256).max);
        vm.label(CURVE_CRVUSD_WETH_COLLATERAL_LENDING_POOL_MAINNET, "CURVE_CRVUSD_LENDING_POOL");
        vm.label(CURVE_USDC_CRVUSD_POOL_MAINNET, "CURVE_CRVUSD_USDC_SWAP_POOL");
    }

    /*==================INITIALIZATION TESTS==================*/

    function testConvexCrvUSDWethCollateral__Initialization() public {
        MaxApyVault _vault = new MaxApyVault(users.alice, USDC_MAINNET, "MaxApyWETHVault", "maxWETH", TREASURY);

        ProxyAdmin _proxyAdmin = new ProxyAdmin(users.alice);
        ConvexCrvUSDWethCollateralStrategyWrapper _implementation = new ConvexCrvUSDWethCollateralStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;

        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(_implementation),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address)",
                address(_vault),
                keepers,
                bytes32(abi.encode("MaxApy dETH<>frxETH Strategy")),
                users.alice,
                CURVE_CRVUSD_WETH_COLLATERAL_LENDING_POOL_MAINNET,
                CURVE_USDC_CRVUSD_POOL_MAINNET
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
        assertEq(_strategy.strategyName(), bytes32(abi.encode("MaxApy Convex ETH Strategy")));
        assertEq(_strategy.convexBooster(), CONVEX_BOOSTER_MAINNET);
        assertEq(_strategy.router(), UNISWAP_V3_ROUTER_MAINNET);

        assertEq(_strategy.curveLendingPool(), CURVE_CRVUSD_WETH_COLLATERAL_LENDING_POOL_MAINNET);
        assertEq(_strategy.curveUsdcCrvUsdPool(), 0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E);
        assertEq(
            IERC20(_strategy.curveLendingPool()).allowance(address(_strategy), address(_strategy.convexBooster())),
            type(uint256).max
        );
        assertEq(IERC20(CRV_MAINNET).allowance(address(_strategy), address(_strategy.router())), type(uint256).max);
        assertEq(IERC20(CVX_MAINNET).allowance(address(_strategy), address(_strategy.router())), type(uint256).max);
        assertEq(
            IERC20(USDC_MAINNET).allowance(address(_strategy), address(_strategy.curveUsdcCrvUsdPool())),
            type(uint256).max
        );

        assertEq(_strategy.maxSingleTrade(), 1000 * 1e6);

        assertEq(_strategy.minSwapCrv(), 1e14);

        assertEq(_strategy.minSwapCvx(), 1e14);

        assertEq(_proxyAdmin.owner(), users.alice);
        vm.startPrank(address(_proxyAdmin));
        // assertEq(proxyInit.admin(), address(_proxyAdmin));
        vm.stopPrank();

        vm.startPrank(users.alice);
    }

    //  /*==================STRATEGY CONFIGURATION TESTS==================*/

    function testConvexCrvUSDWethCollateral__SetEmergencyExit() public {
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

    function testConvexCrvUSDWethCollateral__SetMaxSingleTrade() public {
        vm.stopPrank();
        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setMaxSingleTrade(1 * _1_USDC);

        vm.stopPrank();
        vm.startPrank(address(vault));
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setMaxSingleTrade(1 * _1_USDC);

        vm.stopPrank();
        vm.startPrank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidZeroAmount()"));
        strategy.setMaxSingleTrade(0);

        vm.expectEmit();
        emit MaxSingleTradeUpdated(1 * _1_USDC);
        strategy.setMaxSingleTrade(1 * _1_USDC);
        assertEq(strategy.maxSingleTrade(), 1 * _1_USDC);
    }

    function testConvexCrvUSDWethCollateral__IsActive() public {
        vault.addStrategy(address(strategy), 10_000, 0, 0, 0);
        assertEq(strategy.isActive(), false);

        deal(USDC_MAINNET, address(strategy), 1 * _1_USDC);
        assertEq(strategy.isActive(), false);

        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
        vm.stopPrank();

        strategy.liquidateAllPositions();
        vm.startPrank(address(strategy));
        IERC20(USDC_MAINNET).transfer(makeAddr("random"), IERC20(USDC_MAINNET).balanceOf(address(strategy)));
        assertEq(strategy.isActive(), false);
        /* 
        deal(USDC_MAINNET, address(strategy), 1 * _1_USDC);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, 0, address(0),block.timestamp);
        assertEq(strategy.isActive(), true); */
    }

    function testConvexCrvUSDWethCollateral__SetMinSwaps() public {
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

    /*==================STRATEGY CORE LOGIC TESTS==================*/
    function testConvexCrvUSDWethCollateral__InvestmentSlippage() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);

        strategy.harvest(0, 0, address(0), block.timestamp);

        deal({ token: address(CRV_MAINNET), to: users.keeper, give: 10 ether });
        IERC20(CRV_MAINNET).approve(strategy.router(), type(uint256).max);

        bytes memory path = abi.encodePacked(
            CRV_MAINNET,
            uint24(3000), // CRV <> WETH 0.3%
            WETH_MAINNET,
            uint24(500), // WETH <> USDC 0.005%
            USDC_MAINNET
        );

        uint256 expectedAmountCrv = IRouter(strategy.router()).exactInput(
            IRouter.ExactInputParams({
                path: path,
                recipient: users.keeper,
                deadline: block.timestamp,
                amountIn: 10 ether,
                amountOutMinimum: 0
            })
        );

        deal({ token: address(CRV_MAINNET), to: address(strategy), give: 10 ether });

        // Apply 1% difference
        uint256 minimumExpectedUSDCAmount = expectedAmountCrv * 999 / 10_000;

        // Expect revert if output amount is gt amount obtained
        vm.expectRevert(abi.encodeWithSignature("MinOutputAmountNotReached()"));
        strategy.harvest(minimumExpectedUSDCAmount, type(uint256).max, address(0), block.timestamp);
    }

    function testConvexCrvUSDWethCollateral__PrepareReturn() public {
        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDC, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        (uint256 unrealizedProfit, uint256 loss, uint256 debtPayment) = strategy.prepareReturn(1 * _1_USDC, 0);
        // assertEq(realizedProfit, 0);
        assertEq(loss, 0);
        assertEq(debtPayment, 1 * _1_USDC);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();
        deal({ token: USDC_MAINNET, to: address(strategy), give: 60 * _1_USDC });
        strategy.adjustPosition();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDC, users.alice);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        assertEq(unrealizedProfit, 59_988_000);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

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

        snapshotId = vm.snapshot();

        deal({ token: USDC_MAINNET, to: address(strategy), give: 80 * _1_USDC });

        strategy.adjustPosition();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDC, users.alice);

        strategy.setMaxSingleTrade(1000);

        strategy.mockReport(0, 0, 0, TREASURY);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        // assertEq(realizedProfit, 40 * _1_USDC + 1000);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
    }

    function testConvexCrvUSDWethCollateral__AdjustPosition() public {
        strategy.adjustPosition();
        assertEq(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);

        uint256 snapshotId = vm.snapshot();

        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedLp = strategy.lpForAmount(10 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.adjustPosition();
        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        deal({ token: USDC_MAINNET, to: address(strategy), give: 100 * _1_USDC });
        expectedLp = strategy.lpForAmount(100 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 100 * _1_USDC);
        strategy.adjustPosition();
        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        deal({ token: USDC_MAINNET, to: address(strategy), give: 500 * _1_USDC });
        expectedLp = strategy.lpForAmount(500 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 500 * _1_USDC);
        strategy.adjustPosition();

        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();
    }

    function testConvexCrvUSDWethCollateral__Invest() public {
        uint256 returned = strategy.invest(0, 0);
        assertEq(returned, 0);
        assertEq(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);

        vm.expectRevert(abi.encodeWithSignature("NotEnoughFundsToInvest()"));
        returned = strategy.invest(1, 0);

        uint256 snapshotId = vm.snapshot();

        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedLp = strategy.lpForAmount(10 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);

        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), expectedLp - 2 * _1_USDC);
        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        strategy.setMaxSingleTrade(1 * _1_USDC);
        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        expectedLp = strategy.lpForAmount(1 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 1 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);

        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), expectedLp - 1 * _1_USDC);
    }

    function testConvexCrvUSDWethCollateral__Divest() public {
        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedLp = strategy.lpForAmount(10 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);
        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), expectedLp - 1 * _1_USDC);

        uint256 strategyBalanceBefore = IERC20(USDC_MAINNET).balanceOf(address(strategy));
        uint256 amountDivested = strategy.divest(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)));

        assertEq(IERC20(USDC_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + amountDivested);
    }

    function testConvexCrvUSDWethCollateral__LiquidatePosition() public {
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
        (liquidatedAmount, loss) = strategy.liquidatePosition(15 * _1_USDC);
        assertGt(liquidatedAmount, 14 * _1_USDC);
        assertLt(loss, _1_USDC / 5);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 50 * _1_USDC });
        invested = strategy.invest(50 * _1_USDC, 0);

        (liquidatedAmount, loss) = strategy.liquidatePosition(50 * _1_USDC);

        assertGt(liquidatedAmount, 49 * _1_USDC);
        assertLt(loss, _1_USDC / 5);
    }

    function testConvexCrvUSDWethCollateral__LiquidateAllPositions() public {
        uint256 snapshotId = vm.snapshot();

        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedLp = strategy.lpForAmount(10 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);

        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), expectedLp - 2 * _1_USDC);

        uint256 strategyBalanceBefore = IERC20(USDC_MAINNET).balanceOf(address(strategy));
        uint256 amountFreed = strategy.liquidateAllPositions();

        assertGt(amountFreed, 9 * _1_USDC);

        assertEq(IERC20(USDC_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + amountFreed);
        assertEq(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 500 * _1_USDC });
        expectedLp = strategy.lpForAmount(500 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 500 * _1_USDC);
        strategy.invest(500 * _1_USDC, 0);

        assertGt(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), expectedLp - 50 * _1_USDC);

        strategyBalanceBefore = IERC20(USDC_MAINNET).balanceOf(address(strategy));
        amountFreed = strategy.liquidateAllPositions();

        assertGt(amountFreed, 9 * _1_USDC);

        assertEq(IERC20(USDC_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + amountFreed);
        assertEq(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);
    }

    function testConvexCrvUSDWethCollateral__UnwindRewards() public {
        deal({ token: USDC_MAINNET, to: address(strategy), give: 100 * _1_USDC });
        vm.expectEmit();
        emit Invested(address(strategy), 100 * _1_USDC);
        strategy.invest(100 * _1_USDC, 0);

        strategy.unwindRewards();
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(strategy)), 0, "1");

        vm.warp(block.timestamp + 30 days);

        assertEq(IERC20(USDC_MAINNET).balanceOf(address(strategy)), 0, "2");
        strategy.unwindRewards();
        assertEq(IERC20(CVX_MAINNET).balanceOf(address(strategy)), 0, "3");
        assertEq(IERC20(CRV_MAINNET).balanceOf(address(strategy)), 0, "4");
        assertGt(IERC20(USDC_MAINNET).balanceOf(address(strategy)), 0, "5");
    }

    function testConvexCrvUSDWethCollateral__Harvest() public {
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

        uint256 expectedStrategyLpBalance = strategy.lpForAmount(40 * _1_USDC);
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

        expectedStrategyLpBalance = strategy.lpForAmount(40 * _1_USDC);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 60 * _1_USDC);

        vm.startPrank(users.alice);
        strategy.setEmergencyExit(2);

        vm.startPrank(users.keeper);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDC });
        vm.warp(block.timestamp + 1 days);

        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 110_007_585);
        assertEq(IERC20(strategy.convexRewardPool()).balanceOf(address(strategy)), 0);
        vm.revertTo(snapshotId);

        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        expectedStrategyLpBalance = strategy.lpForAmount(40 * _1_USDC);
        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, uint128(40 * _1_USDC), uint128(40 * _1_USDC), 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        strategy.harvest(0, 0, address(0), block.timestamp);

        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 60 * _1_USDC);

        uint256 expectedLp = strategy.lpForAmount(10 * _1_USDC);

        vm.startPrank(address(strategy));
        uint256 withdrawn = strategy.divest(expectedLp);

        IERC20(USDC_MAINNET).transfer(makeAddr("random"), withdrawn);
        vm.startPrank(users.keeper);

        strategy.harvest(0, 0, address(0), block.timestamp);

        StrategyData memory data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3001);
        assertEq(data.strategyDebtRatio, 3001);
    }

    function testConvexCrvUSDWethCollateral__PreviewLiquidate() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 expected = strategy.previewLiquidate(30 * _1_USDC);
        vm.startPrank(address(vault));
        uint256 loss = strategy.liquidate(30 * _1_USDC);
        assertEq(expected, 30 * _1_USDC - loss);
    }

    function testConvexCrvUSDWethCollateral__PreviewLiquidateExact() public {
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

    function testConvexCrvUSDWethCollateral__maxLiquidateExact() public {
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

    function testConvexCrvUSDWethCollateral__MaxLiquidate() public {
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

    function testConvexCrvUSDWethCollateral__SimulateHarvest() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);
        (uint256 expectedBalance, uint256 outputAfterInvestment,,,,) = strategy.simulateHarvest();

        strategy.harvest(expectedBalance, outputAfterInvestment, address(0), block.timestamp);
    }
}
