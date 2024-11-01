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
import { YearnUSDTStrategyWrapper } from "../../mock/YearnUSDTStrategyWrapper-mainnet.sol";
import { MaxApyVault } from "src/MaxApyVault.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { StrategyEvents } from "../../helpers/StrategyEvents.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { USDC_MAINNET, _1_USDT } from "test/helpers/Tokens.sol";
import "src/helpers/AddressBook.sol";

contract YearnUSDTStrategyTest is BaseTest, StrategyEvents {
    using SafeTransferLib for address;

    address public constant YVAULT_USDT_MAINNET = YEARN_USDT_YVAULT_MAINNET;
    address public TREASURY;

    IStrategyWrapper public strategy;
    YearnUSDTStrategyWrapper public implementation;
    MaxApyVault public vaultDeployment;
    IMaxApyVault public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;

    function setUp() public {
        super._setUp("MAINNET");
        vm.rollFork(19_674_363);

        TREASURY = makeAddr("treasury");

        vaultDeployment = new MaxApyVault(users.alice, USDC_MAINNET, "MaxApyUSDTVault", "maxUSDT", TREASURY);

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
                bytes32("MaxApy Yearn Strategy"),
                users.alice,
                YVAULT_USDT_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(YVAULT_USDT_MAINNET, "yVault");
        vm.label(address(proxy), "YearnUSDTStrategy");
        vm.label(address(USDC_MAINNET), "USDC");
        vm.label(address(USDT_MAINNET), "USDT");

        strategy = IStrategyWrapper(address(_proxy));
        USDC_MAINNET.safeApprove(address(vault), type(uint256).max);
    }

    /*==================INITIALIZATION TESTS==================*/

    function testYearnUSDT__Initialization() public {
        MaxApyVault _vault = new MaxApyVault(users.alice, USDC_MAINNET, "MaxApyUSDTVault", "maxUSDT", TREASURY);
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
                bytes32("MaxApy Yearn Strategy"),
                users.alice,
                YVAULT_USDT_MAINNET
            )
        );

        IStrategyWrapper _strategy = IStrategyWrapper(address(_proxy));

        assertEq(_strategy.vault(), address(_vault));
        assertEq(_strategy.hasAnyRole(_strategy.vault(), _strategy.VAULT_ROLE()), true);
        assertEq(_strategy.underlyingAsset(), USDC_MAINNET);
        assertEq(IERC20(USDC_MAINNET).allowance(address(_strategy), address(_vault)), type(uint256).max);
        assertEq(_strategy.hasAnyRole(users.keeper, _strategy.KEEPER_ROLE()), true);
        assertEq(_strategy.hasAnyRole(users.alice, _strategy.ADMIN_ROLE()), true);
        assertEq(_strategy.strategyName(), bytes32("MaxApy Yearn Strategy"));
        assertEq(_strategy.yVault(), YVAULT_USDT_MAINNET);
        assertEq(IERC20(USDT_MAINNET).allowance(address(_strategy), YVAULT_USDT_MAINNET), type(uint256).max);

        assertEq(_proxyAdmin.owner(), users.alice);
        vm.startPrank(address(_proxyAdmin));
        // assertEq(proxyInit.admin(), address(_proxyAdmin));
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
        strategy.setMinSingleTrade(1 * _1_USDT);

        vm.stopPrank();
        vm.startPrank(address(vault));
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.setMinSingleTrade(1 * _1_USDT);

        vm.stopPrank();
        vm.startPrank(users.alice);
        vm.expectEmit();
        emit MinSingleTradeUpdated(1 * _1_USDT);
        strategy.setMinSingleTrade(1 * _1_USDT);
        assertEq(strategy.minSingleTrade(), 1 * _1_USDT);
    }

    function testYearnUSDT__IsActive() public {
        vault.addStrategy(address(strategy), 10_000, 0, 0, 0);
        assertEq(strategy.isActive(), false);

        deal(USDC_MAINNET, address(strategy), 1 * _1_USDT);
        assertEq(strategy.isActive(), false);

        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
        vm.stopPrank();

        strategy.divest(IERC20(YVAULT_USDT_MAINNET).balanceOf(address(strategy)));
        vm.startPrank(address(strategy));
        (USDC_MAINNET).safeTransfer(makeAddr("random"), IERC20(USDC_MAINNET).balanceOf(address(strategy)));
        assertEq(strategy.isActive(), false);

        deal(USDC_MAINNET, address(strategy), 1 * _1_USDT);
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

        vault.deposit(100 * _1_USDT, users.alice);

        vm.startPrank(users.keeper);

        // Expect revert if output amount is gt amount obtained
        vm.expectRevert(abi.encodeWithSignature("MinOutputAmountNotReached()"));
        strategy.harvest(0, type(uint256).max, address(0), block.timestamp);
    }

    function testYearnUSDT__PrepareReturn() public {
        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDT, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        (uint256 unrealizedProfit, uint256 loss, uint256 debtPayment) = strategy.prepareReturn(1 * _1_USDT, 0);
        // assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 0);
        assertEq(loss, 0);
        assertEq(debtPayment, 1 * _1_USDT);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        deal({ token: USDT_MAINNET, to: address(strategy), give: 60 * _1_USDT });
        strategy.investYearn(60 * _1_USDT);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDT, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        uint256 beforeReturnSnapshotId = vm.snapshot();

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);
        // assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 60_019_419);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDT, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        strategy.triggerLoss(10 * _1_USDT);

        beforeReturnSnapshotId = vm.snapshot();

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);
        // assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 0);
        assertEq(loss, 10 * _1_USDT);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);
        // assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 0);
        assertEq(loss, 10 * _1_USDT);
        assertEq(debtPayment, 0);

        vm.revertTo(snapshotId);
    }

    function testYearnUSDT__AdjustPosition() public {
        strategy.adjustPosition();
        assertEq(IERC20(YVAULT_USDT_MAINNET).balanceOf(address(strategy)), 0);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDT });
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDT);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDT);
        strategy.adjustPosition();
        assertApproxEq(expectedShares, IERC20(YVAULT_USDT_MAINNET).balanceOf(address(strategy)), expectedShares / 1000);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 100 * _1_USDT });
        expectedShares += strategy.sharesForAmount(100 * _1_USDT);
        vm.expectEmit();
        emit Invested(address(strategy), 100 * _1_USDT);
        strategy.adjustPosition();
        assertApproxEq(expectedShares, IERC20(YVAULT_USDT_MAINNET).balanceOf(address(strategy)), expectedShares / 1000);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 500 * _1_USDT });
        expectedShares += strategy.sharesForAmount(500 * _1_USDT);
        vm.expectEmit();
        emit Invested(address(strategy), 500 * _1_USDT);
        strategy.adjustPosition();
        assertApproxEq(expectedShares, IERC20(YVAULT_USDT_MAINNET).balanceOf(address(strategy)), expectedShares / 1000);
    }

    function testYearnUSDT__Invest() public {
        uint256 returned = strategy.invest(0, 0);
        assertEq(returned, 0);
        assertEq(IERC20(YVAULT_USDT_MAINNET).balanceOf(address(strategy)), 0);

        vm.expectRevert(abi.encodeWithSignature("NotEnoughFundsToInvest()"));
        returned = strategy.invest(1, 0);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDT });
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDT);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDT);
        strategy.invest(10 * _1_USDT, 0);
        assertEq(expectedShares, IERC20(YVAULT_USDT_MAINNET).balanceOf(address(strategy)));

        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDT });
        expectedShares += strategy.sharesForAmount(10 * _1_USDT);
        vm.expectEmit();
        emit Invested(address(strategy), 10 * _1_USDT);
        strategy.invest(10 * _1_USDT, 0);
        assertEq(expectedShares, IERC20(YVAULT_USDT_MAINNET).balanceOf(address(strategy)));
    }

    function testYearnUSDT__Divest() public {
        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDT });
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDT);
        strategy.invest(10 * _1_USDT, 0);
        assertEq(expectedShares, IERC20(YVAULT_USDT_MAINNET).balanceOf(address(strategy)));

        uint256 strategyBalanceBefore = IERC20(USDC_MAINNET).balanceOf(address(strategy));
        vm.expectEmit();
        emit Divested(address(strategy), expectedShares, 9_997_998);
        uint256 amountDivested = strategy.divest(expectedShares);
        assertEq(amountDivested, 9_997_998);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + amountDivested);
    }

    function testYearnUSDT__LiquidatePosition() public {
        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDT });
        (uint256 liquidatedAmount, uint256 loss) = strategy.liquidatePosition(1 * _1_USDT);
        assertEq(liquidatedAmount, 1 * _1_USDT);
        assertEq(loss, 0);

        (liquidatedAmount, loss) = strategy.liquidatePosition(10 * _1_USDT);
        assertEq(liquidatedAmount, 10 * _1_USDT);
        assertEq(loss, 0);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 5 * _1_USDT });
        strategy.invest(5 * _1_USDT, 0);
        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDT });
        (liquidatedAmount, loss) = strategy.liquidatePosition(14 * _1_USDT);
        assertEq(liquidatedAmount, 13_999_198);
        assertEq(loss, 802);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 1000 * _1_USDT });
        strategy.invest(1000 * _1_USDT, 0);
        deal({ token: USDC_MAINNET, to: address(strategy), give: 500 * _1_USDT });
        (liquidatedAmount, loss) = strategy.liquidatePosition(1000 * _1_USDT);
        assertEq(liquidatedAmount, 999_899_995);
        assertEq(loss, 100_005);
    }

    function testYearnUSDT__LiquidateAllPositions() public {
        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDT });
        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDT);
        strategy.invest(10 * _1_USDT, 0);
        assertEq(expectedShares, IERC20(YVAULT_USDT_MAINNET).balanceOf(address(strategy)));

        uint256 strategyBalanceBefore = IERC20(USDC_MAINNET).balanceOf(address(strategy));
        uint256 amountFreed = strategy.liquidateAllPositions();
        assertEq(amountFreed, 9_997_998);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + 9_997_998);
        assertEq(IERC20(YVAULT_USDT_MAINNET).balanceOf(address(strategy)), 0);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 500 * _1_USDT });
        expectedShares = strategy.sharesForAmount(500 * _1_USDT);
        strategy.invest(500 * _1_USDT, 0);
        assertApproxEq(expectedShares, IERC20(YVAULT_USDT_MAINNET).balanceOf(address(strategy)), expectedShares / 1000);

        strategyBalanceBefore = IERC20(USDC_MAINNET).balanceOf(address(strategy));
        amountFreed = strategy.liquidateAllPositions();
        assertEq(amountFreed, 499_900_003);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore + 499_900_003);
        assertEq(IERC20(YVAULT_USDT_MAINNET).balanceOf(address(strategy)), 0);
    }

    function testYearnUSDT__Harvest() public {
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        strategy.harvest(0, 0, address(0), block.timestamp);

        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDT, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, uint128(40 * _1_USDT), 40 * _1_USDT, 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        strategy.harvest(0, 0, address(0), block.timestamp);

        uint256 expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDT);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 60 * _1_USDT);
        assertEq(IERC20(YVAULT_USDT_MAINNET).balanceOf(address(strategy)), expectedStrategyShareBalance);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDT });

        vm.expectEmit();
        emit StrategyReported(
            address(strategy), 10 * _1_USDT, 0, 0, uint128(10 * _1_USDT), 0, uint128(40 * _1_USDT), 0, 4000
        );

        vm.expectEmit();
        emit Harvested(10 * _1_USDT, 0, 0, 0);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 60 * _1_USDT);
        uint256 shares = strategy.sharesForAmount(10 * _1_USDT);
        assertEq(IERC20(YVAULT_USDT_MAINNET).balanceOf(address(strategy)), expectedStrategyShareBalance + shares, "1");

        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();

        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDT, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, uint128(40 * _1_USDT), uint128(40 * _1_USDT), 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);

        strategy.harvest(0, 0, address(0), block.timestamp);

        expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDT);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 60 * _1_USDT);
        assertEq(IERC20(YVAULT_USDT_MAINNET).balanceOf(address(strategy)), expectedStrategyShareBalance, "3");

        vm.startPrank(users.alice);
        strategy.setEmergencyExit(2);

        vm.startPrank(users.keeper);

        deal({ token: USDC_MAINNET, to: address(strategy), give: 10 * _1_USDT });

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 1, 39_999_999, uint128(0), 1, 0, 0, 4000);

        vm.expectEmit();
        emit Harvested(0, 1, 49_991_998, 0);

        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 109_991_998);
        assertEq(IERC20(YVAULT_USDT_MAINNET).balanceOf(address(strategy)), 0);

        vm.revertTo(snapshotId);

        vm.startPrank(users.alice);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDT, users.alice);

        vm.startPrank(users.keeper);

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 0, 0, 0, uint128(40 * _1_USDT), uint128(40 * _1_USDT), 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 0, 0);
        strategy.harvest(0, 0, address(0), block.timestamp);

        expectedStrategyShareBalance = strategy.sharesForAmount(40 * _1_USDT);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 60 * _1_USDT);
        assertEq(IERC20(YVAULT_USDT_MAINNET).balanceOf(address(strategy)), expectedStrategyShareBalance, "4");

        uint256 expectedShares = strategy.sharesForAmount(10 * _1_USDT);

        vm.startPrank(address(strategy));
        (YVAULT_USDT_MAINNET).safeTransfer(makeAddr("random"), expectedShares);

        vm.startPrank(users.keeper);
        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 9_997_999, 0, 0, uint128(9_997_999), uint128(30_002_001), 0, 3001);

        vm.expectEmit();
        emit Harvested(0, 9_997_999, 0, 2_992_401);
        strategy.harvest(0, 0, address(0), block.timestamp);

        StrategyData memory data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3001);
        assertEq(vault.totalDebt(), 30_002_001);
        assertEq(data.strategyDebtRatio, 3001);
        assertEq(data.strategyTotalDebt, 30_002_001);
        assertEq(data.strategyTotalLoss, 9_997_999);

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 600, 2_991_801, 0, uint128(9_998_599), uint128(27_009_600), 0, 3001);

        vm.expectEmit();
        emit Harvested(0, 600, 2_991_801, 180);

        uint256 vaultBalanceBefore = IERC20(USDC_MAINNET).balanceOf(address(vault));
        uint256 strategyBalanceBefore = IERC20(YVAULT_USDT_MAINNET).balanceOf(address(strategy));
        uint256 expectedShareDecrease = strategy.sharesForAmount(2_991_801);

        strategy.harvest(0, 0, address(0), block.timestamp);

        data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3001);
        assertEq(vault.totalDebt(), 27_009_600);
        assertEq(data.strategyDebtRatio, 3001);
        assertEq(data.strategyTotalDebt, 27_009_600);
        assertEq(data.strategyTotalLoss, 9_998_599);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 62_991_801);
        assertLe(
            IERC20(YVAULT_USDT_MAINNET).balanceOf(address(strategy)), strategyBalanceBefore - expectedShareDecrease
        );
    }

    function testYearnUSDT__PreviewLiquidate() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDT, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 expected = strategy.previewLiquidate(30 * _1_USDT);
        vm.startPrank(address(vault));
        uint256 loss = strategy.liquidate(30 * _1_USDT);
        assertLe(expected, 30 * _1_USDT - loss);
    }

    function testYearnUSDT__PreviewLiquidateExact() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDT, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 requestedAmount = strategy.previewLiquidateExact(30 * _1_USDT);
        vm.startPrank(address(vault));
        uint256 balanceBefore = IERC20(USDC_MAINNET).balanceOf(address(vault));
        strategy.liquidateExact(30 * _1_USDT);
        uint256 withdrawn = IERC20(USDC_MAINNET).balanceOf(address(vault)) - balanceBefore;
        // withdraw exactly what requested
        assertEq(withdrawn, 30 * _1_USDT);
        // losses are equal or fewer than expected
        assertLe(withdrawn - 30 * _1_USDT, requestedAmount - 30 * _1_USDT);
    }

    function testYearnUSDT__maxLiquidateExact() public {
        vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDT, users.alice);
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

    function testYearnUSDT__MaxLiquidate() public {
        vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDT, users.alice);
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

    function testYearnUSDT__SimulateHarvest() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 * _1_USDT, users.alice);

        vm.startPrank(users.keeper);
        (uint256 expectedBalance, uint256 outputAfterInvestment,,,,) = strategy.simulateHarvest();

        strategy.harvest(expectedBalance, outputAfterInvestment, address(0), block.timestamp);
    }
}
