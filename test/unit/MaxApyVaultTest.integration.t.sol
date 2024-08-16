// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";

import { BaseTest, IERC20, Vm, console2 } from "../base/BaseTest.t.sol";
import { IStrategyWrapper } from "../interfaces/IStrategyWrapper.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";
import { MaxApyVault } from "src/MaxApyVault.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { StrategyEvents } from "../helpers/StrategyEvents.sol";
import { ICurveLpPool } from "src/interfaces/ICurve.sol";
import { IUniswapV2Router02 as IRouter } from "src/interfaces/IUniswap.sol";

import { ConvexdETHFrxETHStrategyWrapper } from "../mock/ConvexdETHFrxETHStrategyWrapper.sol";
import { ConvexdETHFrxETHStrategyEvents } from "../helpers/ConvexdETHFrxETHStrategyEvents.sol";

import { SommelierMorphoEthMaximizerStrategyWrapper } from "../mock/SommelierMorphoEthMaximizerStrategyWrapper.sol";
import { SommelierMorphoEthMaximizerStrategy } from
    "src/strategies/mainnet/WETH/sommelier/SommelierMorphoEthMaximizerStrategy.sol";

import { SommelierTurboStEthStrategy } from "src/strategies/mainnet/WETH/sommelier/SommelierTurboStEthStrategy.sol";
import { SommelierTurboStEthStrategyWrapper } from "../mock/SommelierTurboStEthStrategyWrapper.sol";

import { SommelierStEthDepositTurboStEthStrategyWrapper } from
    "../mock/SommelierStEthDepositTurboStEthStrategyWrapper.sol";

import { YearnWETHStrategyWrapper } from "../mock/YearnWETHStrategyWrapper.sol";
import { MockRevertingStrategy } from "../mock/MockRevertingStrategy.sol";
import "src/helpers/AddressBook.sol";

contract MaxApyV2IntegrationTest is BaseTest, StrategyEvents {
    address public constant CELLAR_WETH_MAINNET_MORPHO = SOMMELIER_MORPHO_ETH_MAXIMIZER_CELLAR_MAINNET;
    address public constant CELLAR_WETH_MAINNET_STETH = SOMMELIER_TURBO_STETH_CELLAR_MAINNET;
    address public constant CELLAR_STETH_MAINNET = SOMMELIER_ST_ETH_DEPOSIT_TURBO_STETH_CELLAR_MAINNET;
    address public constant YVAULT_WETH_MAINNET = YEARN_WETH_YVAULT_MAINNET;

    address public constant CURVE_POOL = CURVE_ETH_STETH_POOL_MAINNET;

    IERC20 public constant crv = IERC20(CRV_MAINNET);
    IERC20 public constant cvx = IERC20(CVX_MAINNET);
    IERC20 public constant frxEth = IERC20(FRXETH_MAINNET);

    IRouter public constant SUSHISWAP_ROUTER = IRouter(SUSHISWAP_ROUTER_MAINNET);

    address public TREASURY;

    function _dealStEth(address give, uint256 wethIn) internal returns (uint256 stEthOut) {
        vm.deal(give, wethIn);
        stEthOut = ICurveLpPool(CURVE_POOL).exchange{ value: wethIn }(0, 1, wethIn, 0);
        IERC20(STETH_MAINNET).transfer(give, stEthOut >= wethIn ? wethIn : stEthOut);
    }

    IStrategyWrapper public strategy1; // yearn
    IStrategyWrapper public strategy2; // sommelier turbo steth
    IStrategyWrapper public strategy3; // sommelier steth deposit
    IStrategyWrapper public strategy4; // convex

    IMaxApyVault public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;

    function setUp() public {
        super._setUp("MAINNET");

        TREASURY = makeAddr("treasury");

        MaxApyVault vaultDeployment = new MaxApyVault(users.alice, WETH_MAINNET, "MaxApyWETHVault", "maxApy", TREASURY);

        vault = IMaxApyVault(address(vaultDeployment));
        proxyAdmin = new ProxyAdmin(users.alice);

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;

        // Deploy strategy1
        YearnWETHStrategyWrapper implementation1 = new YearnWETHStrategyWrapper();
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation1),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Strategy")),
                users.alice,
                YVAULT_WETH_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(YVAULT_WETH_MAINNET, "yVault");
        vm.label(address(proxy), "YearnWETHStrategy");
        strategy1 = IStrategyWrapper(address(_proxy));

        // Deploy strategy2
        SommelierTurboStEthStrategyWrapper implementation2 = new SommelierTurboStEthStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation2),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier Strategy")),
                users.alice,
                CELLAR_WETH_MAINNET_STETH
            )
        );
        vm.label(CELLAR_WETH_MAINNET_STETH, "Cellar");
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "SommelierTurbStEthStrategy");

        strategy2 = IStrategyWrapper(address(_proxy));

        // Deploy strategy3
        SommelierStEthDepositTurboStEthStrategyWrapper implementation3 =
            new SommelierStEthDepositTurboStEthStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation3),
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
        vm.label(STETH_MAINNET, "StETH");

        strategy3 = IStrategyWrapper(address(_proxy));

        // Deploy strategy4
        ConvexdETHFrxETHStrategyWrapper implementation4 = new ConvexdETHFrxETHStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation4),
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
        vm.label(address(proxy), "ConvexdETHFrxETHStrategy");

        strategy4 = IStrategyWrapper(address(_proxy));

        // Add all the strategies
        vault.addStrategy(address(strategy1), 2250, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy2), 2250, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy3), 2250, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy4), 2250, type(uint72).max, 0, 0);

        vm.rollFork(19_267_583);
        vm.label(address(WETH_MAINNET), "WETH");
        IERC20(WETH_MAINNET).approve(address(vault), type(uint256).max);
        vm.startPrank(users.bob);
        IERC20(WETH_MAINNET).approve(address(vault), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(users.alice);
    }

    function testMaxApyVault_ERC4626__PreviewDeposit() public {
        uint256 expectedShares = vault.previewDeposit(20 ether);
        uint256 sharesReturn = vault.deposit(20 ether, users.alice);
        assertEq(sharesReturn, expectedShares);
        assertEq(vault.balanceOf(users.alice), expectedShares);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 20 ether);

        expectedShares = vault.previewDeposit(20 ether);
        sharesReturn = vault.deposit(20 ether, users.alice);
        assertEq(sharesReturn, expectedShares);
        assertEq(vault.balanceOf(users.alice), expectedShares * 2);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 40 ether);
    }

    function testMaxApyVault_ERC4626__PreviewMint() public {
        uint256 expectedAssets = vault.previewMint(20 ether);
        uint256 assetsReturn = vault.mint(20 ether, users.alice);
        assertEq(assetsReturn, expectedAssets);
        assertEq(vault.balanceOf(users.alice), 20 ether);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), expectedAssets);

        expectedAssets = vault.previewMint(20 ether);
        assetsReturn = vault.mint(20 ether, users.alice);
        assertEq(assetsReturn, expectedAssets);
        assertEq(vault.balanceOf(users.alice), 40 ether);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), expectedAssets * 2);
    }

    function testMaxApyVault_ERC4626__PreviewRedeem() public {
        uint256 sharesAlice = vault.deposit(20 ether, users.alice);
        // other uses deposits as well
        deal(WETH_MAINNET, users.bob, 500 ether);
        vm.startPrank(users.bob);
        uint256 sharesBob = vault.deposit(500 ether, users.bob);
        vm.stopPrank();
        vm.startPrank(users.alice);

        uint256 snapshotId = vm.snapshot();
        assertEq(vault.redeem(type(uint256).max, users.alice, users.alice), vault.previewRedeem(sharesAlice));
        vm.revertTo(snapshotId);

        vm.startPrank(users.keeper);
        strategy1.harvest(0, 0, address(0), block.timestamp);
        strategy2.harvest(0, 0, address(0), block.timestamp);
        strategy3.harvest(0, 0, address(0), block.timestamp);
        strategy4.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        vm.startPrank(users.alice);
        uint256 expectedAssets = vault.previewRedeem(sharesAlice);
        uint256 assets = vault.redeem(type(uint256).max, users.alice, users.alice);
        assertEq(assets, expectedAssets);
        vm.stopPrank();
        vm.startPrank(users.bob);
        expectedAssets = vault.previewRedeem(sharesBob);
        assets = vault.redeem(type(uint256).max, users.bob, users.bob);
        assertEq(assets, expectedAssets);
        vm.stopPrank();
        vm.revertTo(snapshotId);

        vm.startPrank(users.keeper);
        strategy1.harvest(0, 0, address(0), block.timestamp);
        strategy2.harvest(0, 0, address(0), block.timestamp);
        strategy3.harvest(0, 0, address(0), block.timestamp);
        strategy4.harvest(0, 0, address(0), block.timestamp);
        deal(WETH_MAINNET, address(strategy1), 50 ether);
        // forward time so lastReport timestamp is not the same
        skip(1);
        strategy1.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        vm.startPrank(users.alice);
        expectedAssets = vault.previewRedeem(sharesAlice);
        assets = vault.redeem(type(uint256).max, users.alice, users.alice);
        assertEq(assets, expectedAssets);
        vm.stopPrank();
        vm.startPrank(users.bob);
        expectedAssets = vault.previewRedeem(sharesBob);
        assets = vault.redeem(type(uint256).max, users.bob, users.bob);
        assertEq(assets, expectedAssets);
        vm.stopPrank();
        vm.revertTo(snapshotId);
    }

    function testMaxApyVault_ERC4626__PreviewWithdraw() public {
        vault.deposit(20 ether, users.alice);
        // other users deposits as well
        deal(WETH_MAINNET, users.bob, 500 ether);

        vm.startPrank(users.bob);
        IERC20(WETH_MAINNET).approve(address(vault), type(uint256).max);
        vault.deposit(500 ether, users.bob);
        vm.stopPrank();

        vm.startPrank(users.alice);
        uint256 snapshotId = vm.snapshot();
        uint256 expectedShares = vault.previewWithdraw(18 ether);
        uint256 balanceBefore = IERC20(WETH_MAINNET).balanceOf(users.alice);
        uint256 shares = vault.withdraw(18 ether, users.alice, users.alice);
        uint256 transferred = IERC20(WETH_MAINNET).balanceOf(users.alice) - balanceBefore;
        assertEq(transferred, 18 ether);
        assertLe(shares, expectedShares);

        vm.startPrank(users.bob);
        expectedShares = vault.previewWithdraw(400 ether);
        balanceBefore = IERC20(WETH_MAINNET).balanceOf(users.bob);
        shares = vault.withdraw(400 ether, users.bob, users.bob);
        transferred = IERC20(WETH_MAINNET).balanceOf(users.bob) - balanceBefore;
        assertEq(transferred, 400 ether);
        assertLe(shares, expectedShares);
        vm.stopPrank();

        vm.revertTo(snapshotId);

        vm.startPrank(users.keeper);
        strategy1.harvest(0, 0, address(0), block.timestamp);
        strategy2.harvest(0, 0, address(0), block.timestamp);
        strategy3.harvest(0, 0, address(0), block.timestamp);
        strategy4.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        vm.startPrank(users.alice);
        expectedShares = vault.previewWithdraw(18 ether);
        balanceBefore = IERC20(WETH_MAINNET).balanceOf(users.alice);
        shares = vault.withdraw(18 ether, users.alice, users.alice);
        transferred = IERC20(WETH_MAINNET).balanceOf(users.alice) - balanceBefore;
        assertEq(transferred, 18 ether);
        assertLe(shares, expectedShares);
        vm.stopPrank();
        vm.startPrank(users.bob);
        expectedShares = vault.previewWithdraw(400 ether);
        balanceBefore = IERC20(WETH_MAINNET).balanceOf(users.bob);
        shares = vault.withdraw(400 ether, users.bob, users.bob);
        transferred = IERC20(WETH_MAINNET).balanceOf(users.bob) - balanceBefore;
        assertEq(transferred, 400 ether);
        assertLe(shares, expectedShares);
        vm.stopPrank();
        vm.revertTo(snapshotId);

        vm.startPrank(users.keeper);
        strategy1.harvest(0, 0, address(0), block.timestamp);
        strategy2.harvest(0, 0, address(0), block.timestamp);
        strategy3.harvest(0, 0, address(0), block.timestamp);
        strategy4.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        vm.startPrank(users.alice);
        expectedShares = vault.previewWithdraw(19 ether);
        balanceBefore = IERC20(WETH_MAINNET).balanceOf(users.alice);
        shares = vault.withdraw(19 ether, users.alice, users.alice);
        transferred = IERC20(WETH_MAINNET).balanceOf(users.alice) - balanceBefore;
        assertEq(transferred, 19 ether);
        assertLe(shares, expectedShares);
        vm.stopPrank();
        vm.startPrank(users.bob);
        expectedShares = vault.previewWithdraw(400 ether);
        balanceBefore = IERC20(WETH_MAINNET).balanceOf(users.bob);
        shares = vault.withdraw(400 ether, users.bob, users.bob);
        transferred = IERC20(WETH_MAINNET).balanceOf(users.bob) - balanceBefore;
        assertEq(transferred, 400 ether);
        assertLe(shares, expectedShares);
        vm.stopPrank();
        vm.revertTo(snapshotId);
    }

    function testMaxApyVault_ERC4626_RedeemMax() public {
        deal(WETH_MAINNET, users.alice, 500 ether);

        IERC20(WETH_MAINNET).approve(address(vault), type(uint256).max);
        vault.deposit(500 ether, users.alice);

        vm.startPrank(users.keeper);
        strategy1.harvest(0, 0, address(0), block.timestamp);
        strategy2.harvest(0, 0, address(0), block.timestamp);
        strategy3.harvest(0, 0, address(0), block.timestamp);
        strategy4.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();

        vm.startPrank(users.alice);
        vault.redeem(type(uint256).max, users.alice, users.alice);
    }

    function testMaxApyVault_ERC4626_WithdrawMax() public {
        deal(WETH_MAINNET, users.alice, 500 ether);

        IERC20(WETH_MAINNET).approve(address(vault), type(uint256).max);
        vault.deposit(500 ether, users.alice);

        vm.startPrank(users.keeper);
        strategy1.harvest(0, 0, address(0), block.timestamp);
        strategy2.harvest(0, 0, address(0), block.timestamp);
        strategy3.harvest(0, 0, address(0), block.timestamp);
        strategy4.harvest(0, 0, address(0), block.timestamp);

        deal(WETH_MAINNET, address(strategy1), 10 ether);
        skip(100);
        strategy1.harvest(0, 0, address(0), block.timestamp);

        vm.stopPrank();

        vm.startPrank(users.alice);
        vault.withdraw(type(uint256).max, users.alice, users.alice);
    }

    function testMaxApyVault__SharePrice() external {
        vault.deposit(20 ether, users.alice);
        assertEq(vault.sharePrice(), 1 ether);

        assertEq(strategy1.estimatedTotalAssets(), 0);
        assertEq(strategy1.lastEstimatedTotalAssets(), 0);

        // sending assets directly to the vault won't work
        deal(WETH_MAINNET, address(vault), 500 ether);
        assertEq(vault.sharePrice(), 1 ether);

        // share price might slightly decrease after investing
        vm.startPrank(users.keeper);
        strategy1.harvest(0, 0, address(0), block.timestamp);
        strategy2.harvest(0, 0, address(0), block.timestamp);
        strategy3.harvest(0, 0, address(0), block.timestamp);
        strategy4.harvest(0, 0, address(0), block.timestamp);
        assertApproxEq(vault.sharePrice(), 1 ether, 1 ether / 1000);

        // sending assets directly to the strategy won't work
        deal(WETH_MAINNET, address(strategy1), 5 ether);
        assertApproxEq(vault.sharePrice(), 1 ether, 1 ether / 1000);
        skip(1);
        strategy1.harvest(0, 0, address(0), block.timestamp);

        assertApproxEq(vault.sharePrice(), 1 ether * 125 / 100, 1 ether);

        // if the strategy has losses it should instantly be reflected in the share price
        vm.stopPrank();
        vm.startPrank(address(strategy1));
        // transfer shares to a random addresss
        IERC20(YVAULT_WETH_MAINNET).transfer(makeAddr("random"), strategy1.sharesForAmount(5 ether));

        // the share price gets back to the initial value approx
        assertApproxEq(vault.sharePrice(), 1 ether, 0.03 ether);
    }

    function testMaxApyVault_AutoPilot() public {
        MockRevertingStrategy revertingStrategy = new MockRevertingStrategy(address(vault), WETH_MAINNET);
        vault.addStrategy(address(revertingStrategy), 500, type(uint72).max, 0, 0);
        vault.setAutopilotEnabled(true);
        revertingStrategy.setAutopilot(true);
        uint256 lastReport = vault.lastReport();

        // deposit will trigger the reverting strategy
        vm.expectEmit();
        // emit event to log that the autopilot harvest reverted
        emit ForceHarvestFailed(address(revertingStrategy), abi.encodeWithSignature("HarvestFailed()"));
        uint256 expectedShares = vault.previewDeposit(20 ether);
        vault.deposit(20 ether, users.alice);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(vault)), 20 ether);
        assertEq(IERC20(address(vault)).balanceOf(users.alice), expectedShares);
        // the report didnt happen
        assertEq(vault.lastReport(), lastReport);
        assertEq(vault.nexHarvestStrategyIndex(), 0);

        // set a valid strategy in autipilot
        strategy1.setAutopilot(true);
        // simulate fake gains
        uint256 yVaultShares = IERC20(YVAULT_WETH_MAINNET).balanceOf(address(strategy1));
        uint256 yVaultProfit = strategy1.shareValue(yVaultShares) - strategy1.lastEstimatedTotalAssets();
        deal(WETH_MAINNET, address(strategy1), 10 ether);
        uint256 expectedManagementFee = (10 ether + yVaultProfit) * vault.managementFee() / MAX_BPS;
        expectedShares = vault.convertToShares(expectedManagementFee); // 2% management fee
        expectedShares += vault.previewDeposit(20 ether);
        vm.expectEmit();
        // harvest should happen
        emit Harvested(10 ether, 0, 0, 0);
        vm.startPrank(users.bob);
        vault.deposit(20 ether, users.bob);
        // user gets shares + performanceFee
        assertEq(IERC20(address(vault)).balanceOf(users.bob), expectedShares);
        // last report has changed
        assertGt(vault.lastReport(), lastReport);
        // next strategy to harvest will be next index
        assertEq(vault.nexHarvestStrategyIndex(), 1);

        // now it should success because it wont trigger the reverting strategy
        vault.deposit(20 ether, users.bob);
    }

    function testMaxApyVault__ExitStrategy() public {
        uint256 snapshotId = vm.snapshot();

        // Strategy 1: Yearn
        assertEq(vault.strategies(address(strategy1)).strategyDebtRatio, 2250);
        assertEq(vault.strategies(address(strategy1)).strategyTotalDebt, 0);
        assertEq(vault.withdrawalQueue(0), address(strategy1));
        vm.expectEmit();
        emit StrategyExited(address(strategy1), 0);
        vault.exitStrategy(address(strategy1));
        assertEq(strategy1.estimatedTotalAssets(), 0);
        assertEq(vault.strategies(address(strategy1)).strategyTotalDebt, 0);
        assertEq(vault.strategies(address(strategy1)).strategyDebtRatio, 0);
        assertFalse(vault.strategies(address(strategy1)).autoPilot);
        assertEq(vault.strategies(address(strategy1)).strategyActivation, 0);
        // The strategy should no longer be in the queue
        assertFalse(vault.withdrawalQueue(0) == address(strategy1));

        // Strategy 2: Sommelier
        assertEq(vault.strategies(address(strategy2)).strategyDebtRatio, 2250);
        assertEq(vault.strategies(address(strategy2)).strategyTotalDebt, 0);
        assertEq(vault.withdrawalQueue(0), address(strategy2));
        vm.expectEmit();
        emit StrategyExited(address(strategy2), 0);
        vault.exitStrategy(address(strategy2));
        assertEq(strategy2.estimatedTotalAssets(), 0);
        assertEq(vault.strategies(address(strategy2)).strategyTotalDebt, 0);
        assertEq(vault.strategies(address(strategy2)).strategyDebtRatio, 0);
        assertFalse(vault.strategies(address(strategy2)).autoPilot);
        assertEq(vault.strategies(address(strategy2)).strategyActivation, 0);
        // The strategy should no longer be in the queue
        assertFalse(vault.withdrawalQueue(0) == address(strategy2));

        // Strategy 3: Sommelier
        assertEq(vault.strategies(address(strategy3)).strategyDebtRatio, 2250);
        assertEq(vault.strategies(address(strategy3)).strategyTotalDebt, 0);
        assertEq(vault.withdrawalQueue(0), address(strategy3));
        vm.expectEmit();
        emit StrategyExited(address(strategy3), 0);
        vault.exitStrategy(address(strategy3));
        assertEq(strategy3.estimatedTotalAssets(), 0);
        assertEq(vault.strategies(address(strategy3)).strategyTotalDebt, 0);
        assertEq(vault.strategies(address(strategy3)).strategyDebtRatio, 0);
        assertFalse(vault.strategies(address(strategy3)).autoPilot);
        assertEq(vault.strategies(address(strategy3)).strategyActivation, 0);
        // The strategy should no longer be in the queue
        assertFalse(vault.withdrawalQueue(0) == address(strategy3));

        // Strategy 4: Sommelier
        assertEq(vault.strategies(address(strategy4)).strategyDebtRatio, 2250);
        assertEq(vault.strategies(address(strategy4)).strategyTotalDebt, 0);
        assertEq(vault.withdrawalQueue(0), address(strategy4));
        vm.expectEmit();
        emit StrategyExited(address(strategy4), 0);
        vault.exitStrategy(address(strategy4));
        assertEq(strategy4.estimatedTotalAssets(), 0);
        assertEq(vault.strategies(address(strategy4)).strategyTotalDebt, 0);
        assertEq(vault.strategies(address(strategy4)).strategyDebtRatio, 0);
        assertFalse(vault.strategies(address(strategy4)).autoPilot);
        assertEq(vault.strategies(address(strategy4)).strategyActivation, 0);
        // The strategy should no longer be in the queue
        assertFalse(vault.withdrawalQueue(0) == address(strategy4));
        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        vault.deposit(10 ether, users.alice);
        vm.startPrank(users.keeper);
        strategy1.harvest(0, 0, address(0), block.timestamp);
        strategy2.harvest(0, 0, address(0), block.timestamp);
        strategy3.harvest(0, 0, address(0), block.timestamp);
        strategy4.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();

        vm.startPrank(users.alice);

        // check vault data
        assertEq(vault.debtRatio(), 9000);
        assertEq(vault.totalDebt(), 9 ether);
        assertEq(vault.totalDeposits(), 10 ether);
        assertEq(vault.totalIdle(), 1 ether);

        // Strategy 1: Yearn
        assertEq(vault.strategies(address(strategy1)).strategyDebtRatio, 2250);
        assertEq(vault.strategies(address(strategy1)).strategyTotalDebt, 2.25 ether);
        assertEq(vault.withdrawalQueue(0), address(strategy1));

        vm.expectEmit();
        emit StrategyExited(address(strategy1), 2.249999999999999998 ether);
        vault.exitStrategy(address(strategy1));
        assertApproxEq(strategy1.estimatedTotalAssets(), 0, 1);
        assertEq(vault.strategies(address(strategy1)).strategyTotalDebt, 0);
        assertEq(vault.strategies(address(strategy1)).strategyDebtRatio, 0);
        assertFalse(vault.strategies(address(strategy1)).autoPilot);
        assertEq(vault.strategies(address(strategy1)).strategyActivation, 0);
        // The strategy should no longer be in the queue
        assertFalse(vault.withdrawalQueue(0) == address(strategy1));

        // check vault data
        assertEq(vault.debtRatio(), 6750);
        assertEq(vault.totalDebt(), 6.75 ether);
        assertEq(vault.totalDeposits(), 9.999999999999999998 ether);
        assertEq(vault.totalIdle(), 3.249999999999999998 ether);

        // Strategy 2: Sommelier
        assertEq(vault.strategies(address(strategy2)).strategyDebtRatio, 2250);
        assertEq(vault.strategies(address(strategy2)).strategyTotalDebt, 2.25 ether);
        assertEq(vault.withdrawalQueue(0), address(strategy2));

        emit StrategyExited(address(strategy1), 2.249999999999999998 ether);
        vault.exitStrategy(address(strategy2));
        // some dust could be left
        assertApproxEq(strategy2.estimatedTotalAssets(), 0, 0.01 ether);
        assertEq(vault.strategies(address(strategy2)).strategyTotalDebt, 0);
        assertEq(vault.strategies(address(strategy2)).strategyDebtRatio, 0);
        assertFalse(vault.strategies(address(strategy2)).autoPilot);
        assertEq(vault.strategies(address(strategy2)).strategyActivation, 0);
        // The strategy should no longer be in the queue
        assertFalse(vault.withdrawalQueue(0) == address(strategy2));

        // check vault data
        assertEq(vault.debtRatio(), 4500);
        assertEq(vault.totalDebt(), 4.5 ether);
        assertEq(vault.totalDeposits(), 9.998755009497361781 ether); // slight losses from withdraw
        assertEq(vault.totalIdle(), 5.498755009497361781 ether);

        // Strategy 3: Sommelier
        assertEq(vault.strategies(address(strategy3)).strategyDebtRatio, 2250);
        assertEq(vault.strategies(address(strategy3)).strategyTotalDebt, 2.25 ether);
        assertEq(vault.withdrawalQueue(0), address(strategy3));

        emit StrategyExited(address(strategy1), 2.249999999999999998 ether);
        vault.exitStrategy(address(strategy3));
        // some dust could be left
        assertApproxEq(strategy3.estimatedTotalAssets(), 0, 0.01 ether);
        assertEq(vault.strategies(address(strategy3)).strategyTotalDebt, 0);
        assertEq(vault.strategies(address(strategy3)).strategyDebtRatio, 0);
        assertFalse(vault.strategies(address(strategy3)).autoPilot);
        assertEq(vault.strategies(address(strategy3)).strategyActivation, 0);
        // The strategy should no longer be in the queue
        assertFalse(vault.withdrawalQueue(0) == address(strategy3));

        // check vault data
        assertEq(vault.debtRatio(), 2250);
        assertEq(vault.totalDebt(), 2.25 ether);
        assertEq(vault.totalDeposits(), 9.996511336157465263 ether); // slight losses from withdraw
        assertEq(vault.totalIdle(), 7.746511336157465263 ether);

        // Strategy 4: Sommelier
        assertEq(vault.strategies(address(strategy4)).strategyDebtRatio, 2250);
        assertEq(vault.strategies(address(strategy4)).strategyTotalDebt, 2.25 ether);
        assertEq(vault.withdrawalQueue(0), address(strategy4));

        emit StrategyExited(address(strategy1), 2.249999999999999998 ether);
        vault.exitStrategy(address(strategy4));
        // some dust could be left
        assertApproxEq(strategy4.estimatedTotalAssets(), 0, 0.01 ether);
        assertEq(vault.strategies(address(strategy4)).strategyTotalDebt, 0);
        assertEq(vault.strategies(address(strategy4)).strategyDebtRatio, 0);
        assertFalse(vault.strategies(address(strategy4)).autoPilot);
        assertEq(vault.strategies(address(strategy4)).strategyActivation, 0);
        // The strategy should no longer be in the queue
        assertFalse(vault.withdrawalQueue(0) == address(strategy4));

        // check vault data
        assertEq(vault.debtRatio(), 0);
        assertEq(vault.totalDebt(), 0);
        assertEq(vault.totalDeposits(), 9.990466618247177147 ether); // slight losses from withdraw
        assertEq(vault.totalIdle(), 9.990466618247177147 ether);
    }
}
