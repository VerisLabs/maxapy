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
import { YearnUSDTStrategyWrapper } from "../../mock/YearnUSDTStrategyWrapper-polygon.sol";
import { MaxApyVault } from "src/MaxApyVault.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { StrategyEvents } from "../../helpers/StrategyEvents.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { USDT_POLYGON, _1_USDCE } from "test/helpers/Tokens.sol";
import "src/helpers/AddressBook.sol";

import "forge-std/console.sol";

contract YearnUSDTStrategyTest is BaseTest, StrategyEvents {
    using SafeTransferLib for address;

    address public constant YVAULT_USDT_POLYGON = YEARN_USDT_YVAULT_POLYGON;
    address public TREASURY;

    IStrategyWrapper public strategy;
    YearnUSDTStrategyWrapper public implementation;
    MaxApyVault public vaultDeployment;
    IMaxApyVault public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;

    function setUp() public {
        super._setUp("POLYGON");
        vm.rollFork(53_869_145);

        TREASURY = makeAddr("treasury");

        vaultDeployment = new MaxApyVault(users.alice, USDCE_POLYGON, "MaxApyUSDCeVault", "maxUSDCe", TREASURY);

        vault = IMaxApyVault(address(vaultDeployment));
        proxyAdmin = new ProxyAdmin(users.alice);
        implementation = new YearnUSDTStrategyWrapper();

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
                YVAULT_USDT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(YVAULT_USDT_POLYGON, "yVault");
        vm.label(address(proxy), "YearnUSDTStrategy");
        vm.label(address(USDT_POLYGON), "USDT");
        vm.label(address(USDCE_POLYGON), "USDCE");

        strategy = IStrategyWrapper(address(_proxy));

        IERC20(USDCE_POLYGON).approve(address(vault), type(uint256).max);
    }

    /*==================INITIALIZATION TESTS==================*/

    function testYearnUSDT__Initialization() public {
        MaxApyVault _vault = new MaxApyVault(users.alice, USDCE_POLYGON, "MaxApyUSDCeVault", "maxUSDCe", TREASURY);
        ProxyAdmin _proxyAdmin = new ProxyAdmin(users.alice);
        YearnUSDTStrategyWrapper _implementation = new YearnUSDTStrategyWrapper();

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
                YVAULT_USDT_POLYGON
            )
        );

        IStrategyWrapper _strategy = IStrategyWrapper(address(_proxy));

        assertEq(_strategy.vault(), address(_vault));
        assertEq(_strategy.hasAnyRole(_strategy.vault(), _strategy.VAULT_ROLE()), true);
        assertEq(_strategy.underlyingAsset(), USDCE_POLYGON);
        assertEq(IERC20(USDT_POLYGON).allowance(address(_strategy), address(YVAULT_USDT_POLYGON)), type(uint256).max);
        assertEq(IERC20(USDCE_POLYGON).allowance(address(_strategy), address(_vault)), type(uint256).max);
        assertEq(_strategy.hasAnyRole(users.keeper, _strategy.KEEPER_ROLE()), true);
        assertEq(_strategy.hasAnyRole(users.alice, _strategy.ADMIN_ROLE()), true);
        assertEq(_strategy.strategyName(), bytes32(abi.encode("MaxApy Yearn Strategy")));
        assertEq(_strategy.yVault(), YVAULT_USDT_POLYGON);

        assertEq(_proxyAdmin.owner(), users.alice);
        vm.startPrank(address(_proxyAdmin));
        vm.stopPrank();

        vm.startPrank(users.alice);
    }

    /*==================STRATEGY CONFIGURATION TESTS==================*/

    function testYearnUSDT__SetEmergencyExit() public {
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

    function testYearnUSDT__SetMinSingleTrade() public {
        vm.stopPrank();
        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setMinSingleTrade(1 * _1_USDCE);

        vm.stopPrank();
        vm.startPrank(address(vault));
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setMinSingleTrade(1 * _1_USDCE);

        vm.stopPrank();
        vm.startPrank(users.alice);
        vm.expectEmit();
        emit MinSingleTradeUpdated(1 * _1_USDCE);
        strategy.setMinSingleTrade(1 * _1_USDCE);
        assertEq(strategy.minSingleTrade(), 1 * _1_USDCE);
    }

    function testYearnUSDT__IsActive() public {
        vault.addStrategy(address(strategy), 10_000, 0, 0, 0);
        assertEq(strategy.isActive(), false);

        deal(USDCE_POLYGON, address(strategy), 10 * _1_USDCE);
        assertEq(strategy.isActive(), false);

        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
        vm.stopPrank();

        strategy.divest(IERC20(YVAULT_USDT_POLYGON).balanceOf(address(strategy)));
        vm.startPrank(address(strategy));
        IERC20(USDCE_POLYGON).transfer(makeAddr("random"), IERC20(USDCE_POLYGON).balanceOf(address(strategy)));
        assertEq(strategy.isActive(), false);

        deal(USDCE_POLYGON, address(strategy), 1 * _1_USDCE);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
    }

    function testYearnUSDT__SetStrategist() public {
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
    function testYearnUSDT__InvestmentSlippage() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDCE, users.alice);

        vm.startPrank(users.keeper);

        // Expect revert if output amount is gt amount obtained
        vm.expectRevert(abi.encodeWithSignature("MinOutputAmountNotReached()"));
        strategy.harvest(0, type(uint256).max, address(0), block.timestamp);
    }

    function testYearnUSDT__PrepareReturn() public {
        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDCE, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        (uint256 unrealizedProfit, uint256 loss, uint256 debtPayment) = strategy.prepareReturn(1 * _1_USDCE, 0);
        assertEq(unrealizedProfit, 0);
        assertEq(loss, 0);
        assertEq(debtPayment, 1 * _1_USDCE);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 60 * _1_USDCE });
        strategy.invest(60 * _1_USDCE, 0);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDCE, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        uint256 beforeReturnSnapshotId = vm.snapshot();

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);
        assertEq(unrealizedProfit, 59_955_561);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDCE, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        strategy.triggerLoss(10 * _1_USDCE);

        beforeReturnSnapshotId = vm.snapshot();

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);
        assertEq(unrealizedProfit, 0);
        assertEq(loss, 10 * _1_USDCE);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);
        assertEq(unrealizedProfit, 0);
        assertEq(loss, 10 * _1_USDCE);
        assertEq(debtPayment, 0);

        vm.revertTo(snapshotId);
    }

    function testYearnUSDT__AdjustPosition() public {
        strategy.adjustPosition();
        assertEq(IERC20(YVAULT_USDT_POLYGON).balanceOf(address(strategy)), 0);

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDCE });
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDCE);
        vm.expectEmit();
        emit Invested(address(strategy), 9_992_594);
        strategy.adjustPosition();
        assertApproxEq(expectedShares, IERC20(YVAULT_USDT_POLYGON).balanceOf(address(strategy)), expectedShares / 1000);

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 100 * _1_USDCE });
        expectedShares += strategy.sharesForAmount(100 * _1_USDCE);
        vm.expectEmit();
        emit Invested(address(strategy), 99_925_938);
        strategy.adjustPosition();
        assertApproxEq(expectedShares, IERC20(YVAULT_USDT_POLYGON).balanceOf(address(strategy)), expectedShares / 1000);

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 500 * _1_USDCE });
        expectedShares += strategy.sharesForAmount(500 * _1_USDCE);
        vm.expectEmit();
        emit Invested(address(strategy), 499_629_694);
        strategy.adjustPosition();
        assertApproxEq(expectedShares, IERC20(YVAULT_USDT_POLYGON).balanceOf(address(strategy)), expectedShares / 1000);
    }

    function testYearnUSDT__Invest() public {
        uint256 returned = strategy.invest(0, 0);
        assertEq(returned, 0);
        assertEq(IERC20(YVAULT_USDT_POLYGON).balanceOf(address(strategy)), 0);

        vm.expectRevert(abi.encodeWithSignature("NotEnoughFundsToInvest()"));
        returned = strategy.invest(1, 0);

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDCE });
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDCE);

        vm.expectEmit();
        emit Invested(address(strategy), 9_992_594);

        strategy.invest(10 * _1_USDCE, 0);
        assertApproxEq(expectedShares, IERC20(YVAULT_USDT_POLYGON).balanceOf(address(strategy)), expectedShares / 1000);

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDCE });
        expectedShares += strategy.sharesForAmount(10 * _1_USDCE);

        vm.expectEmit();
        emit Invested(address(strategy), 9_992_594);

        strategy.invest(10 * _1_USDCE, 0);
        assertApproxEq(expectedShares, IERC20(YVAULT_USDT_POLYGON).balanceOf(address(strategy)), expectedShares / 1000);
    }

    function testYearnUSDT__Divest() public {
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDCE });
        uint256 expectedShares = strategy.sharesForAmount(9_992_594);
        strategy.invest(10 * _1_USDCE, 0);
        assertApproxEq(expectedShares, IERC20(YVAULT_USDT_POLYGON).balanceOf(address(strategy)), expectedShares / 1000);

        uint256 strategyBalanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(strategy));
        vm.expectEmit();
        emit Divested(address(strategy), expectedShares, 9_985_700);
        uint256 amountDivested = strategy.divest(expectedShares);
        assertEq(amountDivested, 9_985_700);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(strategy)), strategyBalanceBefore + amountDivested);
    }

    function testYearnUSDT__LiquidatePosition() public {
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDCE });
        (uint256 liquidatedAmount, uint256 loss) = strategy.liquidatePosition(1 * _1_USDCE);
        assertEq(liquidatedAmount, 1 * _1_USDCE);
        assertEq(loss, 0);

        (liquidatedAmount, loss) = strategy.liquidatePosition(9 * _1_USDCE);
        assertEq(liquidatedAmount, 9 * _1_USDCE);
        assertEq(loss, 0);

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 5 * _1_USDCE });
        strategy.invest(5 * _1_USDCE, 0);
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDCE });
        (liquidatedAmount, loss) = strategy.liquidatePosition(14_990_000);
        assertEq(liquidatedAmount, 14_986_557);
        assertEq(loss, 3443);

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 1000 * _1_USDCE });
        strategy.invest(1000 * _1_USDCE, 0);
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 500 * _1_USDCE });
        (liquidatedAmount, loss) = strategy.liquidatePosition(1000 * _1_USDCE);
        assertEq(liquidatedAmount, 999_655_248);
        assertEq(loss, 344_752);
    }

    function testYearnUSDT__LiquidateAllPositions() public {
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDCE });
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDCE);
        strategy.invest(10 * _1_USDCE, 0);
        assertApproxEq(expectedShares, IERC20(YVAULT_USDT_POLYGON).balanceOf(address(strategy)), expectedShares / 1000);

        uint256 strategyBalanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(strategy));
        uint256 amountFreed = strategy.liquidateAllPositions();
        assertEq(amountFreed, 9_992_003);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(strategy)), strategyBalanceBefore + 9_992_003);
        assertEq(IERC20(YVAULT_USDT_POLYGON).balanceOf(address(strategy)), 0);

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 500 * _1_USDCE });
        expectedShares = strategy.sharesForAmount(500 * _1_USDCE);
        strategy.invest(500 * _1_USDCE, 0);
        assertApproxEq(expectedShares, IERC20(YVAULT_USDT_POLYGON).balanceOf(address(strategy)), expectedShares / 1000);

        strategyBalanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(strategy));
        amountFreed = strategy.liquidateAllPositions();
        assertEq(amountFreed, 499_600_127);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(strategy)), strategyBalanceBefore + 499_600_127);
        assertEq(IERC20(YVAULT_USDT_POLYGON).balanceOf(address(strategy)), 0);
    }

    function testYearnUSDT__Harvest() public {
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.harvest(0, 0, address(0), block.timestamp);

        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDCE, users.alice);

        vm.startPrank(users.keeper);
        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, uint128(40 * _1_USDCE), 40 * _1_USDCE, 4000);
        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        strategy.harvest(0, 0, address(0), block.timestamp);

        uint256 expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDCE);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 60 * _1_USDCE);
        assertApproxEq(
            IERC20(YVAULT_USDT_POLYGON).balanceOf(address(strategy)),
            expectedStrategyShareBalance,
            expectedStrategyShareBalance / 1000
        );

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDCE });
        vm.expectEmit();
        emit StrategyReported(
            address(strategy), 10 * _1_USDCE, 0, 0, uint128(10 * _1_USDCE), 0, uint128(40 * _1_USDCE), 0, 4000
        );

        vm.expectEmit();
        emit Harvested(10 * _1_USDCE, 0, 0, 0);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 60 * _1_USDCE);
        uint256 shares = strategy.sharesForAmount(10 * _1_USDCE);
        assertApproxEq(
            IERC20(YVAULT_USDT_POLYGON).balanceOf(address(strategy)),
            expectedStrategyShareBalance + shares,
            expectedStrategyShareBalance / 1000
        );

        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();

        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDCE, users.alice);

        vm.startPrank(users.keeper);
        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, uint128(40 * _1_USDCE), uint128(40 * _1_USDCE), 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);

        strategy.harvest(0, 0, address(0), block.timestamp);

        expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDCE);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 60 * _1_USDCE);
        assertApproxEq(
            IERC20(YVAULT_USDT_POLYGON).balanceOf(address(strategy)),
            expectedStrategyShareBalance,
            expectedStrategyShareBalance / 1000
        );

        vm.startPrank(users.alice);
        strategy.setEmergencyExit(2);

        vm.startPrank(users.keeper);

        deal({ token: USDCE_POLYGON, to: address(strategy), give: 10 * _1_USDCE });
        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 2364, 39_997_636, 0, 2364, 1418, 1418, 4000);

        vm.expectEmit();
        emit Harvested(0, 2364, 49_968_011, 0);

        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 109_966_593);
        assertEq(IERC20(YVAULT_USDT_POLYGON).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);

        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDCE, users.alice);

        vm.startPrank(users.keeper);
        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, uint128(40 * _1_USDCE), uint128(40 * _1_USDCE), 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        strategy.harvest(0, 0, address(0), block.timestamp);

        expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDCE);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), 60 * _1_USDCE);
        assertApproxEq(
            IERC20(YVAULT_USDT_POLYGON).balanceOf(address(strategy)),
            expectedStrategyShareBalance,
            expectedStrategyShareBalance / 1000
        );

        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDCE);

        vm.startPrank(address(strategy));
        (YVAULT_USDT_POLYGON).safeTransfer(makeAddr("random"), expectedShares);

        vm.startPrank(users.keeper);
        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 9_993_693, 0, 0, uint128(9_993_693), uint128(30_006_307), 0, 3001);
        vm.expectEmit();
        emit Harvested(0, 9_993_693, 0, 2_995_415);
        strategy.harvest(0, 0, address(0), block.timestamp);

        StrategyData memory data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3001);
        assertEq(vault.totalDebt(), 30_006_307);
        assertEq(data.strategyDebtRatio, 3001);
        assertEq(data.strategyTotalDebt, 30_006_307);
        assertEq(data.strategyTotalLoss, 9_993_693);

        vm.expectEmit();
        emit StrategyReported(
            address(strategy), 0, 2067, 2_993_348, 0, uint128(9_995_760), uint128(27_010_892), 0, 3001
        );

        vm.expectEmit();
        emit Harvested(0, 2067, 2_993_348, 620);

        uint256 vaultBalanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(vault));
        uint256 strategyBalanceBefore = IERC20(YVAULT_USDT_POLYGON).balanceOf(address(strategy));
        uint256 expectedShareDecrease = strategy.sharesForAmount(2 * _1_USDCE);

        strategy.harvest(0, 0, address(0), block.timestamp);

        data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3001);
        assertEq(vault.totalDebt(), 27_010_892);
        assertEq(data.strategyDebtRatio, 3001);
        assertEq(data.strategyTotalDebt, 27_010_892);
        assertEq(data.strategyTotalLoss, 9_995_760);
        assertEq(IERC20(USDCE_POLYGON).balanceOf(address(vault)), vaultBalanceBefore + 2_993_348);
        assertLe(
            IERC20(YVAULT_USDT_POLYGON).balanceOf(address(strategy)), strategyBalanceBefore - expectedShareDecrease
        );
    }

    function testYearnUSDT__PreviewLiquidate() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDCE, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 expected = strategy.previewLiquidate(30 * _1_USDCE);
        vm.startPrank(address(vault));
        uint256 loss = strategy.liquidate(30 * _1_USDCE);
        // expect the Sommelier's {previewRedeem} to be fully precise
        assertLe(expected, 30 * _1_USDCE - loss);
    }

    function testYearnUSDT__PreviewLiquidateExact() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDCE, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 requestedAmount = strategy.previewLiquidateExact(30 * _1_USDCE);
        vm.startPrank(address(vault));
        uint256 balanceBefore = IERC20(USDCE_POLYGON).balanceOf(address(vault));
        strategy.liquidateExact(30 * _1_USDCE);
        uint256 withdrawn = IERC20(USDCE_POLYGON).balanceOf(address(vault)) - balanceBefore;
        // withdraw exactly what requested
        assertEq(withdrawn, 30 * _1_USDCE);
        // losses are equal or fewer than expected
        assertLe(withdrawn - 30 * _1_USDCE, requestedAmount - 30 * _1_USDCE);
    }

    function testYearnUSDT__maxLiquidateExact() public {
        vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDCE, users.alice);
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

    function testYearnUSDT__MaxLiquidate() public {
        vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDCE, users.alice);
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

    function testYearnUSDT__SimulateHarvest() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDCE, users.alice);

        vm.startPrank(users.keeper);
        (uint256 expectedBalance, uint256 outputAfterInvestment,,,,) = strategy.simulateHarvest();

        strategy.harvest(expectedBalance, outputAfterInvestment, address(0), block.timestamp);
    }
}
