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
import { YearnCompoundUSDCeLenderStrategyWrapper } from "../../mock/YearnCompoundUSDCeLenderStrategyWrapper.sol";
import { MaxApyVault } from "src/MaxApyVault.sol";

import "src/helpers/AddressBook.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";

import { _1_USDC } from "test/helpers/Tokens.sol";

contract YearnCompoundUSDCeLenderStrategyTest is BaseTest, StrategyEvents {
    address public constant YVAULT_USDCE_POLYGON = YEARN_COMPOUND_USDC_LENDER_YVAULT_POLYGON;
    address public TREASURY;

    IStrategyWrapper public strategy;
    YearnCompoundUSDCeLenderStrategyWrapper public implementation;
    MaxApyVault public vaultDeployment;
    IMaxApyVault public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;

    function setUp() public {
        super._setUp("POLYGON");
        vm.rollFork(53_869_145);

        TREASURY = makeAddr("treasury");

        vaultDeployment = new MaxApyVault(users.alice, USDCE_POLYGON, "MaxApyUSDCEVault", "maxUSDCE", TREASURY);

        vault = IMaxApyVault(address(vaultDeployment));
        proxyAdmin = new ProxyAdmin(users.alice);
        implementation = new YearnCompoundUSDCeLenderStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32("MaxApy Yearn Strategy"),
                users.alice,
                YVAULT_USDCE_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(YVAULT_USDCE_POLYGON, "yVault");
        vm.label(address(proxy), "YearnCompoundUSDCeLenderStrategy");
        vm.label(address(USDCE_POLYGON), "USDCe");

        strategy = IStrategyWrapper(address(_proxy));

        IERC20(USDCE_POLYGON).approve(address(vault), type(uint256).max);
    }

    /*==================INITIALIZATION TESTS==================*/

    function testYearnCompoundUSDCeLender__Initialization() public {
        MaxApyVault _vault = new MaxApyVault(users.alice, USDCE_POLYGON, "MaxApyUSDCEVault", "maxUSDCE", TREASURY);
        ProxyAdmin _proxyAdmin = new ProxyAdmin(users.alice);
        YearnCompoundUSDCeLenderStrategyWrapper _implementation = new YearnCompoundUSDCeLenderStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(_implementation),
            address(_proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(_vault),
                keepers,
                bytes32("MaxApy Yearn Strategy"),
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
        assertEq(_strategy.strategyName(), bytes32("MaxApy Yearn Strategy"));
        assertEq(_strategy.yVault(), YVAULT_USDCE_POLYGON);
        assertEq(IERC20(USDCE_POLYGON).allowance(address(_strategy), YVAULT_USDCE_POLYGON), type(uint256).max);

        assertEq(_proxyAdmin.owner(), users.alice);
        vm.startPrank(address(_proxyAdmin));
        // assertEq(proxyInit.admin(), address(_proxyAdmin));
        vm.stopPrank();

        vm.startPrank(users.alice);
    }

    /*==================STRATEGY CONFIGURATION TESTS==================*/

    function testYearnCompoundUSDCeLender__SetEmergencyExit() public {
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

    function testYearnCompoundUSDCeLender__SetMinSingleTrade() public {
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

    function testYearnCompoundUSDCeLender__IsActive() public {
        vault.addStrategy(address(strategy), 10_000, 0, 0, 0);
        assertEq(strategy.isActive(), false);

        deal(USDCE_POLYGON, address(strategy), 1 * _1_USDC);
        assertEq(strategy.isActive(), false);

        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
        vm.stopPrank();

        strategy.divest(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)));
        vm.startPrank(address(strategy));
        IERC20(USDCE_POLYGON).transfer(makeAddr("random"), IERC20(USDCE_POLYGON).balanceOf(address(strategy)));
        assertEq(strategy.isActive(), false);

        deal(USDCE_POLYGON, address(strategy), 1 * _1_USDC);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
    }

    function testYearnCompoundUSDCeLender__SetStrategist() public {
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
    function testYearnCompoundUSDCeLender__InvestmentSlippage() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);

        // Expect revert if output amount is gt amount obtained
        vm.expectRevert(abi.encodeWithSignature("MinOutputAmountNotReached()"));
        strategy.harvest(0, type(uint256).max, address(0), block.timestamp);
    }

    function testYearnCompoundUSDCeLender__PrepareReturn() public {
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

    function testYearnCompoundUSDCeLender__AdjustPosition() public {
        strategy.adjustPosition();
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), 0);

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.adjustPosition();
        assertEq(expectedShares, IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)));

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 100 * _1_USDC });
        expectedShares += strategy.sharesForAmount(100 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 100 * _1_USDC);
        strategy.adjustPosition();
        assertEq(expectedShares, IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)));

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 500 * _1_USDC });
        expectedShares += strategy.sharesForAmount(500 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 500 * _1_USDC);
        strategy.adjustPosition();
        assertEq(expectedShares, IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)));
    }

    function testYearnCompoundUSDCeLender__Invest() public {
        uint256 returned = strategy.invest(0, 0);
        assertEq(returned, 0);
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), 0);

        vm.expectRevert(abi.encodeWithSignature("NotEnoughFundsToInvest()"));
        returned = strategy.invest(1, 0);

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)));

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC });
        expectedShares += strategy.sharesForAmount(10 * _1_USDC);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)));
    }

    function testYearnCompoundUSDCeLender__Divest() public {
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)));

        uint256 strategyBalanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(strategy));
        vm.expectEmit();
        emit Divested(address(strategy), expectedShares, 10 * _1_USDC - 1);
        uint256 amountDivested = strategy.divest(expectedShares);
        assertEq(amountDivested, 10 * _1_USDC - 1);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(strategy)), strategyBalanceBefore + amountDivested);
    }

    function testYearnCompoundUSDCeLender__LiquidatePosition() public {
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

    function testYearnCompoundUSDCeLender__LiquidateAllPositions() public {
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC });
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);
        strategy.invest(10 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)));

        uint256 strategyBalanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(strategy));
        uint256 amountFreed = strategy.liquidateAllPositions();
        assertEq(amountFreed, 9_999_999);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(strategy)), strategyBalanceBefore + 9_999_999);
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), 0);

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 500 * _1_USDC });
        expectedShares = strategy.sharesForAmount(500 * _1_USDC);
        strategy.invest(500 * _1_USDC, 0);
        assertEq(expectedShares, IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)));

        strategyBalanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(strategy));
        amountFreed = strategy.liquidateAllPositions();
        assertEq(amountFreed, 499_999_999);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(strategy)), strategyBalanceBefore + 499_999_999);
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), 0);
    }

    function testYearnCompoundUSDCeLender__Harvest() public {
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.harvest(0, 0, address(0), block.timestamp);

        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, uint128(40 * _1_USDC), 40 * _1_USDC, 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        strategy.harvest(0, 0, address(0), block.timestamp);

        uint256 expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDC);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 60 * _1_USDC);
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), expectedStrategyShareBalance);

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
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), expectedStrategyShareBalance + shares, "1");

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
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), expectedStrategyShareBalance, "3");

        vm.startPrank(users.alice);
        strategy.setEmergencyExit(2);

        vm.startPrank(users.keeper);

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDC });

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 40 * _1_USDC, uint128(0), 0, 0, 0, 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 49_999_999, 0);

        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 109_999_999);
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), 0);

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
        assertEq(IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), expectedStrategyShareBalance, "4");

        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDC);

        vm.startPrank(address(strategy));
        IERC20(YVAULT_USDCE_POLYGON).transfer(makeAddr("random"), expectedShares);

        vm.startPrank(users.keeper);
        vm.expectEmit();
        emit StrategyReported(
            address(strategy), 0, 9_999_999, 0, 0, uint128(9_999_999), uint128(30 * _1_USDC + 1), 0, 3001
        );

        vm.expectEmit();
        emit Harvested(0, 9_999_999, 0, 2_991_001);
        strategy.harvest(0, 0, address(0), block.timestamp);

        StrategyData memory data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3001);
        assertEq(vault.totalDebt(), 30 * _1_USDC + 1);
        assertEq(data.strategyDebtRatio, 3001);
        assertEq(data.strategyTotalDebt, 30 * _1_USDC + 1);
        assertEq(data.strategyTotalLoss, 9_999_999);

        vm.expectEmit();
        emit StrategyReported(
            address(strategy), 0, 1, 2_991_000, 0, uint128(10 * _1_USDC), uint128(27_009_000), 0, 3001
        );

        vm.expectEmit();
        emit Harvested(0, 1 wei, 2_991_000, 0);

        uint256 vaultBalanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(vault));
        uint256 strategyBalanceBefore = IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy));
        uint256 expectedShareDecrease = strategy.sharesForAmount(2_991_000);

        strategy.harvest(0, 0, address(0), block.timestamp);

        data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3001);
        assertEq(vault.totalDebt(), 27_009_000);
        assertEq(data.strategyDebtRatio, 3001);
        assertEq(data.strategyTotalDebt, 27_009_000);
        assertEq(data.strategyTotalLoss, 10 * _1_USDC);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), vaultBalanceBefore + 2_991_000);
        assertLe(
            IERC20(YVAULT_USDCE_POLYGON).balanceOf(address(strategy)), strategyBalanceBefore - expectedShareDecrease
        );
    }

    function testYearnCompoundUSDCeLender__PreviewLiquidate() public {
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

    function testYearnCompoundUSDCeLender__PreviewLiquidate__FUZZY(uint256 amount) public {
        vm.assume(amount > 1e4 && amount <= 1000 * _1_USDC);
        vault.addStrategy(address(strategy), 10_000, type(uint72).max, 0, 0);
        deal(USDCE_POLYGON, users.alice, amount * 2);
        vault.deposit(amount * 2, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 expected = strategy.previewLiquidate(amount);
        vm.startPrank(address(vault));
        uint256 loss = strategy.liquidate(amount);
        // expect the Sommelier's {previewRedeem} to be fully precise
        assertEq(expected, amount - loss);
    }

    function testYearnCompoundUSDCeLender__PreviewLiquidateExact() public {
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

    function testYearnCompoundUSDCeLender__PreviewLiquidateExact__FUZZY(uint256 amount) public {
        vm.assume(amount > 1e4 && amount <= 1000 * _1_USDC);
        vault.addStrategy(address(strategy), 10_000, type(uint72).max, 0, 0);
        deal(USDCE_POLYGON, users.alice, amount * 2);
        vault.deposit(amount * 2, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 requestedAmount = strategy.previewLiquidateExact(amount);
        vm.startPrank(address(vault));
        uint256 balanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(vault));
        uint256 losses = strategy.liquidateExact(amount);
        uint256 withdrawn = IERC20(USDCE_POLYGON).balanceOf(address(vault)) - balanceBefore;
        // withdraw exactly what requested
        assertEq(withdrawn, amount);
        // losses are equal or fewer than expected
        assertLe(losses, requestedAmount - amount);
    }

    function testYearnCompoundUSDCeLender__maxLiquidateExact() public {
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

    function testYearnCompoundUSDCeLender__maxLiquidateExact__FUZZY(uint256 amount) public {
        vm.assume(amount > 1e4 && amount <= 1000 * _1_USDC);
        vault.addStrategy(address(strategy), 10_000, type(uint72).max, 0, 0);
        deal(USDCE_POLYGON, users.alice, amount * 2);
        vault.deposit(amount * 2, users.alice);
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

    function testYearnCompoundUSDCeLender__MaxLiquidate() public {
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

    function testYearnCompoundUSDCeLender__MaxLiquidate__FUZZY(uint256 amount) public {
        vm.assume(amount > 1e4 && amount <= 1000 * _1_USDC);
        vault.addStrategy(address(strategy), 10_000, type(uint72).max, 0, 0);
        deal(USDCE_POLYGON, users.alice, amount * 2);
        vault.deposit(amount * 2, users.alice);
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

    function testYearnCompoundUSDCeLender__SimulateHarvest() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDC, users.alice);

        vm.startPrank(users.keeper);
        (uint256 expectedBalance, uint256 outputAfterInvestment,,,,) = strategy.simulateHarvest();

        strategy.harvest(expectedBalance, outputAfterInvestment, address(0), block.timestamp);
    }
}
