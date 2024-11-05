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
import { YearnMaticUSDCStakingStrategyWrapper } from "../../mock/YearnMaticUSDCStakingStrategyWrapper.sol";
import { MaxApyVault } from "src/MaxApyVault.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { StrategyEvents } from "../../helpers/StrategyEvents.sol";
import { USDCE_POLYGON, _1_USDC } from "test/helpers/Tokens.sol";
import "src/helpers/AddressBook.sol";

contract YearnMaticUSDCStakingStrategyTest is BaseTest, StrategyEvents {
    address public constant YVAULT_USDCE_POLYGON = YEARN_MATIC_USDC_STAKING_YVAULT_POLYGON;
    address public TREASURY;

    IStrategyWrapper public strategy;
    YearnMaticUSDCStakingStrategyWrapper public implementation;
    MaxApyVault public vaultDeployment;
    IMaxApyVault public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;
    address stakingRewards;

    function setUp() public {
        super._setUp("POLYGON");
        vm.rollFork(53_869_145);

        TREASURY = makeAddr("treasury");

        vaultDeployment = new MaxApyVault(users.alice, USDCE_POLYGON, "MaxApyUSDCVault", "maxUSDC", TREASURY);

        vault = IMaxApyVault(address(vaultDeployment));
        proxyAdmin = new ProxyAdmin(users.alice);
        implementation = new YearnMaticUSDCStakingStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Strategy")),
                users.alice,
                YVAULT_USDCE_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(YVAULT_USDCE_POLYGON, "yVault");
        vm.label(address(proxy), "YearnMaticUSDCStakingStrategy");
        vm.label(address(USDCE_POLYGON), "USDC");
        vm.label(stakingRewards = address(implementation.yearnStakingRewards()), "YearnStakingRewardsMulti");
        vm.label(WPOL_POLYGON, "WMATIC");

        strategy = IStrategyWrapper(address(_proxy));

        IERC20(USDCE_POLYGON).approve(address(vault), type(uint256).max);
    }

    /*==================INITIALIZATION TESTS==================*/

    function testYearnMaticUSDC_Staking__Initialization() public {
        MaxApyVault _vault = new MaxApyVault(users.alice, USDCE_POLYGON, "MaxApyUSDCVault", "maxUSDC", TREASURY);
        ProxyAdmin _proxyAdmin = new ProxyAdmin(users.alice);
        YearnMaticUSDCStakingStrategyWrapper _implementation = new YearnMaticUSDCStakingStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(_implementation),
            address(_proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(_vault),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Strategy")),
                users.alice,
                YVAULT_USDCE_POLYGON
            )
        );

        IStrategyWrapper _strategy = IStrategyWrapper(address(_proxy));

        assertEq(_strategy.vault(), address(_vault));
        assertEq(_strategy.hasAnyRole(_strategy.vault(), _strategy.VAULT_ROLE()), true);
        assertEq(_strategy.underlyingAsset(), USDCE_POLYGON);
        assertEq(IERC20(USDCE_POLYGON).allowance(address(_strategy), address(_vault)), type(uint256).max);
        assertEq(_strategy.hasAnyRole(users.keeper, _strategy.KEEPER_ROLE()), true);
        assertEq(_strategy.hasAnyRole(users.alice, _strategy.ADMIN_ROLE()), true);
        assertEq(_strategy.strategyName(), bytes32(abi.encode("MaxApy Yearn Strategy")));
        assertEq(_strategy.yVault(), YVAULT_USDCE_POLYGON);
        assertEq(IERC20(USDCE_POLYGON).allowance(address(_strategy), YVAULT_USDCE_POLYGON), type(uint256).max);

        assertEq(_proxyAdmin.owner(), users.alice);
        vm.startPrank(address(_proxyAdmin));
        // assertEq(proxyInit.admin(), address(_proxyAdmin));
        vm.stopPrank();

        vm.startPrank(users.alice);
    }

    /*==================STRATEGY CONFIGURATION TESTS==================*/

    function testYearnMaticUSDC_Staking__SetEmergencyExit() public {
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

    function testYearnMaticUSDC_Staking__SetMaxSingleTrade() public {
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

    function testYearnMaticUSDC_Staking__SetMinSingleTrade() public {
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

    function testYearnMaticUSDC_Staking__IsActive() public {
        vault.addStrategy(address(strategy), 10_000, 0, 0, 0);
        assertEq(strategy.isActive(), false);

        deal(USDCE_POLYGON, address(strategy), 1 * _1_USDC);
        assertEq(strategy.isActive(), false);

        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
        vm.stopPrank();

        strategy.divest(IERC20(stakingRewards).balanceOf(address(strategy)));
        vm.startPrank(address(strategy));
        IERC20(USDCE_POLYGON).transfer(makeAddr("random"), IERC20(USDCE_POLYGON).balanceOf(address(strategy)));
        assertEq(strategy.isActive(), false);

        deal(USDCE_POLYGON, address(strategy), 1 * _1_USDC);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
    }

    function testYearnMaticUSDC_Staking__SetStrategist() public {
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
    function testYearnMaticUSDC_Staking__InvestmentSlippage() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);

        // Expect revert if output amount is gt amount obtained
        vm.expectRevert(abi.encodeWithSignature("MinOutputAmountNotReached()"));
        strategy.harvest(0, type(uint256).max, address(0), block.timestamp);
    }

    function testYearnMaticUSDC_Staking__PrepareReturn() public {
        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDC, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        (uint256 unrealizedProfit, uint256 loss, uint256 debtPayment) = strategy.prepareReturn(1 * _1_USDC, 0);
        // assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 0);
        assertEq(loss, 0);
        assertEq(debtPayment, 1 * _1_USDC);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 60 * _1_USDC });
        strategy.invest(60 * _1_USDC, 0);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDC, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        uint256 beforeReturnSnapshotId = vm.snapshot();

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);
        // assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 59_999_999);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);
        // assertEq(realizedProfit, 59_999_998);
        assertEq(unrealizedProfit, 59_999_999);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);

        vm.revertTo(beforeReturnSnapshotId);
        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        // assertEq(realizedProfit, 29_999_999);
        assertEq(unrealizedProfit, 59_999_999);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDC, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        strategy.triggerLoss(10 * _1_USDC);

        beforeReturnSnapshotId = vm.snapshot();

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);
        // assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 0);
        assertEq(loss, 10 * _1_USDC);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);
        // assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 0);
        assertEq(loss, 10 * _1_USDC);
        assertEq(debtPayment, 0);

        vm.revertTo(snapshotId);
    }

    function testYearnMaticUSDC_Staking__AdjustPosition() public {
        strategy.adjustPosition();
        assertEq(IERC20(stakingRewards).balanceOf(address(strategy)), 0);

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.adjustPosition();
        assertEq(expectedShares, IERC20(stakingRewards).balanceOf(address(strategy)));

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 100 * _1_USDC });
        expectedShares += strategy.sharesForAmount(100 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 100 * _1_USDC);
        strategy.adjustPosition();
        assertEq(expectedShares, IERC20(stakingRewards).balanceOf(address(strategy)));

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 500 * _1_USDC });
        expectedShares += strategy.sharesForAmount(500 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 500 * _1_USDC);
        strategy.adjustPosition();
        assertEq(expectedShares, IERC20(stakingRewards).balanceOf(address(strategy)));
    }

    function testYearnMaticUSDC_Staking__Invest() public {
        uint256 returned = strategy.invest(0, 0);
        assertEq(returned, 0);
        assertEq(IERC20(stakingRewards).balanceOf(address(strategy)), 0);

        vm.expectRevert(abi.encodeWithSignature("NotEnoughFundsToInvest()"));
        returned = strategy.invest(1, 0);

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(stakingRewards).balanceOf(address(strategy)));

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC });
        expectedShares += strategy.sharesForAmount(10 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(stakingRewards).balanceOf(address(strategy)));
    }

    function testYearnMaticUSDC_Staking__Divest() public {
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(stakingRewards).balanceOf(address(strategy)));

        uint256 strategyBalanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(strategy));
        vm.expectEmit();
        emit Divested(address(strategy), expectedShares, 9_999_999);
        uint256 amountDivested = strategy.divest(expectedShares);
        assertEq(amountDivested, 9_999_999);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(strategy)), strategyBalanceBefore + amountDivested);
    }

    function testYearnMaticUSDC_Staking__LiquidatePosition() public {
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC });
        (uint256 liquidatedAmount, uint256 loss) = strategy.liquidatePosition(1 * _1_USDC);
        assertEq(liquidatedAmount, 1 * _1_USDC);
        assertEq(loss, 0);

        (liquidatedAmount, loss) = strategy.liquidatePosition(10 * _1_USDC);
        assertEq(liquidatedAmount, 10 * _1_USDC);
        assertEq(loss, 0);

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 5 * _1_USDC });
        strategy.invest(5 * _1_USDC, 0);
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC });
        (liquidatedAmount, loss) = strategy.liquidatePosition(15 * _1_USDC);
        assertEq(liquidatedAmount, 14_999_999);
        assertEq(loss, 1);

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 1000 * _1_USDC });
        strategy.invest(1000 * _1_USDC, 0);
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 500 * _1_USDC });
        (liquidatedAmount, loss) = strategy.liquidatePosition(1000 * _1_USDC);
        assertEq(liquidatedAmount, 999_999_999);
        assertEq(loss, 1);
    }

    function testYearnMaticUSDC_Staking__LiquidateAllPositions() public {
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(stakingRewards).balanceOf(address(strategy)));

        uint256 strategyBalanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(strategy));
        uint256 amountFreed = strategy.liquidateAllPositions();
        assertEq(amountFreed, 9_999_999);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(strategy)), strategyBalanceBefore + 9_999_999);
        assertEq(IERC20(stakingRewards).balanceOf(address(strategy)), 0);

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 500 * _1_USDC });
        expectedShares = strategy.sharesForAmount(500 * _1_USDC);
        strategy.invest(500 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(stakingRewards).balanceOf(address(strategy)));

        strategyBalanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(strategy));
        amountFreed = strategy.liquidateAllPositions();
        assertEq(amountFreed, 499_999_999);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(strategy)), strategyBalanceBefore + 499_999_999);
        assertEq(IERC20(stakingRewards).balanceOf(address(strategy)), 0);
    }

    function testYearnMaticUSDC_Staking__UnwindRewards() public {
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 1000 * _1_USDC });
        vm.expectEmit();
        emit Invested(address(strategy), 1000 * _1_USDC);
        strategy.invest(1000 * _1_USDC, 0);

        strategy.unwindRewards();
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(strategy)), 0);

        vm.warp(block.timestamp + 10 days);

        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(strategy)), 0);
        strategy.unwindRewards();
        assertEq(IERC20(implementation.wpol()).balanceOf(address(strategy)), 0);
        assertGt(IERC20(USDCE_POLYGON).balanceOf(address(strategy)), 0);
    }

    function testYearnMaticUSDC_Staking__Harvest() public {
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
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 60 * _1_USDC);
        assertEq(IERC20(stakingRewards).balanceOf(address(strategy)), expectedStrategyShareBalance);

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC });

        vm.expectEmit();
        emit StrategyReported(
            address(strategy), 10 * _1_USDC, 0, 0, uint128(10 * _1_USDC), 0, uint128(40 * _1_USDC), 0, 4000
        );

        vm.expectEmit();
        emit Harvested(10 * _1_USDC, 0, 0, 0);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 60 * _1_USDC);
        uint256 shares = strategy.sharesForAmount(10 * _1_USDC);
        assertEq(IERC20(stakingRewards).balanceOf(address(strategy)), expectedStrategyShareBalance + shares);

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
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 60 * _1_USDC);
        assertEq(IERC20(stakingRewards).balanceOf(address(strategy)), expectedStrategyShareBalance);

        vm.startPrank(users.alice);
        strategy.setEmergencyExit(2);

        vm.startPrank(users.keeper);

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC });

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 40 * _1_USDC, uint128(0), 0, 0, 0, 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 49_999_999, 0);

        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 110 * _1_USDC - 1);
        assertEq(IERC20(stakingRewards).balanceOf(address(strategy)), 0);

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

        expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDC);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 60 * _1_USDC);
        assertEq(IERC20(stakingRewards).balanceOf(address(strategy)), expectedStrategyShareBalance);

        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC) + 1;
        strategy.divest(expectedShares);
        vm.startPrank(address(strategy));
        IERC20(USDCE_POLYGON).transfer(makeAddr("random"), 10 * _1_USDC);

        vm.startPrank(users.keeper);
        vm.expectEmit();
        emit StrategyReported(
            address(strategy), 0, 10 * _1_USDC + 1, 0, 0, uint128(10 * _1_USDC + 1), uint128(30 * _1_USDC - 1), 0, 3000
        );

        vm.expectEmit();
        emit Harvested(0, 10 * _1_USDC + 1, 0, 3 * _1_USDC);
        strategy.harvest(0, 0, address(0), block.timestamp);

        StrategyData memory data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3000);
        assertEq(vault.totalDebt(), 30 * _1_USDC - 1);
        assertEq(data.strategyDebtRatio, 3000);
        assertEq(data.strategyTotalDebt, 30 * _1_USDC - 1);
        assertEq(data.strategyTotalLoss, 10 * _1_USDC + 1);

        vm.expectEmit();
        emit StrategyReported(
            address(strategy), 0, 1, 3 * _1_USDC - 1, 0, uint128(10 * _1_USDC + 2), uint128(27 * _1_USDC - 1), 0, 3000
        );

        vm.expectEmit();
        emit Harvested(0, 1, 3 * _1_USDC - 1, 0);

        uint256 vaultBalanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(vault));
        uint256 strategyBalanceBefore = IERC20(stakingRewards).balanceOf(address(strategy));
        uint256 expectedShareDecrease = strategy.sharesForAmount(3 * _1_USDC - 1);

        strategy.harvest(0, 0, address(0), block.timestamp);

        data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3000);
        assertEq(vault.totalDebt(), 27 * _1_USDC - 1);
        assertEq(data.strategyDebtRatio, 3000);
        assertEq(data.strategyTotalDebt, 27 * _1_USDC - 1);
        assertEq(data.strategyTotalLoss, 10 * _1_USDC + 2);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), vaultBalanceBefore + 3 * _1_USDC - 1);
        assertLe(IERC20(stakingRewards).balanceOf(address(strategy)), strategyBalanceBefore - expectedShareDecrease);
    }

    function testYearnMaticUSDC_Staking__PreviewLiquidate() public {
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

    function testYearnMaticUSDC__PreviewLiquidate__FUZZY(uint256 amount) public {
        vm.assume(amount > 1 * _1_USDC && amount < 1_000_000 * _1_USDC);
        deal(USDCE_POLYGON, users.alice, amount);
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

    function testYearnMaticUSDC_Staking__PreviewLiquidateExact() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 requestedAmount = strategy.previewLiquidateExact(30 * _1_USDC);
        vm.startPrank(address(vault));
        uint256 balanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(vault));
        strategy.liquidateExact(30 * _1_USDC);
        uint256 withdrawn = IERC20(USDCE_POLYGON).balanceOf(address(vault)) - balanceBefore;
        // withdraw exactly what requested
        assertEq(withdrawn, 30 * _1_USDC);
        // losses are equal or fewer than expected
        assertLe(withdrawn - 30 * _1_USDC, requestedAmount - 30 * _1_USDC);
    }

    function testYearnMaticUSDC_Staking__maxLiquidateExact() public {
        vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 maxLiquidateExact = strategy.maxLiquidateExact();
        uint256 balanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(vault));
        uint256 requestedAmount = strategy.previewLiquidateExact(maxLiquidateExact);
        vm.startPrank(address(vault));
        uint256 losses = strategy.liquidateExact(maxLiquidateExact);
        uint256 withdrawn = IERC20(USDCE_POLYGON).balanceOf(address(vault)) - balanceBefore;
        // withdraw exactly what requested
        assertEq(withdrawn, maxLiquidateExact);
        // losses are equal or fewer than expected
        assertLe(losses, requestedAmount - maxLiquidateExact);
    }

    function testYearnMaticUSDC_Staking__MaxLiquidate() public {
        vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 maxWithdraw = strategy.maxLiquidate();
        uint256 balanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(vault));
        vm.startPrank(address(vault));
        strategy.liquidate(maxWithdraw);
        uint256 withdrawn = IERC20(USDCE_POLYGON).balanceOf(address(vault)) - balanceBefore;
        assertLe(withdrawn, maxWithdraw);
    }

    function testYearnMaticUSDC_Staking__PreviewLiquidateExact_FUZZY(uint256 amount) public {
        vm.assume(amount > 1 * _1_USDC && amount < 10 * _1_USDC);
        deal(USDCE_POLYGON, users.alice, amount);
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(amount, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 requestedAmount = strategy.previewLiquidateExact(amount);
        vm.startPrank(address(vault));
        uint256 balanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(vault));
        strategy.liquidateExact(amount);
        // uint256 withdrawn = IERC20(USDCE_POLYGON).balanceOf(address(vault)) - balanceBefore;
        // // withdraw exactly what requested
        // assertGe(withdrawn, amount);
        // // losses are equal or fewer than expected
        // assertLe(withdrawn - amount, requestedAmount - amount);
    }

    // function testYearnMaticUSDC_Staking__maxLiquidateExact_FUZZY(uint256 amount) public {
    //     vm.assume(amount > 1 * _1_USDC && amount < 1_000 * _1_USDC);
    //     deal(USDCE_POLYGON, users.alice, amount);
    //     vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
    //     vault.deposit(amount, users.alice);
    //     vm.startPrank(users.keeper);
    //     strategy.harvest(0, 0, address(0), block.timestamp);
    //     vm.stopPrank();
    //     uint256 maxLiquidateExact = strategy.maxLiquidateExact();
    //     uint256 balanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(vault));
    //     uint256 requestedAmount = strategy.previewLiquidateExact(maxLiquidateExact);
    //     vm.startPrank(address(vault));
    //     uint256 losses = strategy.liquidateExact(maxLiquidateExact);
    //     uint256 withdrawn = IERC20(USDCE_POLYGON).balanceOf(address(vault)) - balanceBefore;
    //     // withdraw exactly what requested
    //     assertGe(withdrawn, maxLiquidateExact);
    //     // losses are equal or fewer than expected
    //     assertLe(losses, requestedAmount - maxLiquidateExact);
    // }

    // function testYearnMaticUSDC_Staking__MaxLiquidate_FUZZY(uint256 amount) public {
    //     vm.assume(amount > 1 * _1_USDC && amount < 1_000 * _1_USDC);
    //     deal(USDCE_POLYGON, users.alice, amount);
    //     vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
    //     vault.deposit(amount, users.alice);
    //     vm.startPrank(users.keeper);
    //     strategy.harvest(0, 0, address(0), block.timestamp);
    //     vm.stopPrank();
    //     uint256 maxWithdraw = strategy.maxLiquidate();
    //     uint256 balanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(vault));
    //     vm.startPrank(address(vault));
    //     strategy.liquidate(maxWithdraw);
    //     uint256 withdrawn = IERC20(USDCE_POLYGON).balanceOf(address(vault)) - balanceBefore;
    //     assertLe(withdrawn, maxWithdraw);
    // }

    function testYearnMaticUSDC_Staking__SimulateHarvest() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);
        (uint256 expectedBalance, uint256 outputAfterInvestment,,,,) = strategy.simulateHarvest();

        strategy.harvest(expectedBalance, outputAfterInvestment, address(0), block.timestamp);
    }
}
