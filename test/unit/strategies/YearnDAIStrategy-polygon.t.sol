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
import { YearnDAIStrategyWrapper } from "../../mock/YearnDAIStrategyWrapper-polygon.sol";
import { MaxApyVault } from "src/MaxApyVault.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { StrategyEvents } from "../../helpers/StrategyEvents.sol";
import "src/helpers/AddressBook.sol";

contract YearnDAIStrategyTest is BaseTest, StrategyEvents {
    address public constant YVAULT_DAI_POLYGON = YEARN_DAI_POLYGON_VAULT_POLYGON;
    address public TREASURY;

    IStrategyWrapper public strategy;
    YearnDAIStrategyWrapper public implementation;
    MaxApyVault public vaultDeployment;
    IMaxApyVault public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;

    function setUp() public {
        super._setUp("POLYGON");
        vm.rollFork(53_869_145);

        TREASURY = makeAddr("treasury");

        vaultDeployment = new MaxApyVault(users.alice, DAI_POLYGON, "MaxApyDAIVault", "maxDAI", TREASURY);

        vault = IMaxApyVault(address(vaultDeployment));
        proxyAdmin = new ProxyAdmin(users.alice);
        implementation = new YearnDAIStrategyWrapper();

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
                YVAULT_DAI_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(YVAULT_DAI_POLYGON, "yVault");
        vm.label(address(proxy), "YearnDAIStrategy");
        vm.label(address(DAI_POLYGON), "DAI");

        strategy = IStrategyWrapper(address(_proxy));

        IERC20(DAI_POLYGON).approve(address(vault), type(uint256).max);
    }

    /*==================INITIALIZATION TESTS==================*/

    function testYearnDAI__Initialization() public {
        MaxApyVault _vault = new MaxApyVault(users.alice, DAI_POLYGON, "MaxApyDAIVault", "maxDAI", TREASURY);
        ProxyAdmin _proxyAdmin = new ProxyAdmin(users.alice);
        YearnDAIStrategyWrapper _implementation = new YearnDAIStrategyWrapper();

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
                YVAULT_DAI_POLYGON
            )
        );

        IStrategyWrapper _strategy = IStrategyWrapper(address(_proxy));

        assertEq(_strategy.vault(), address(_vault));
        assertEq(_strategy.hasAnyRole(_strategy.vault(), _strategy.VAULT_ROLE()), true);
        assertEq(_strategy.underlyingAsset(), DAI_POLYGON);
        assertEq(IERC20(DAI_POLYGON).allowance(address(_strategy), address(_vault)), type(uint256).max);
        assertEq(_strategy.hasAnyRole(users.keeper, _strategy.KEEPER_ROLE()), true);
        assertEq(_strategy.hasAnyRole(users.alice, _strategy.ADMIN_ROLE()), true);
        assertEq(_strategy.strategyName(), bytes32(abi.encode("MaxApy Yearn Strategy")));
        assertEq(_strategy.yVault(), YVAULT_DAI_POLYGON);
        assertEq(IERC20(DAI_POLYGON).allowance(address(_strategy), YVAULT_DAI_POLYGON), type(uint256).max);

        assertEq(_proxyAdmin.owner(), users.alice);
        vm.startPrank(address(_proxyAdmin));
        // assertEq(proxyInit.admin(), address(_proxyAdmin));
        vm.stopPrank();

        vm.startPrank(users.alice);
    }

    /*==================STRATEGY CONFIGURATION TESTS==================*/

    function testYearnDAI__SetEmergencyExit() public {
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

    function testYearnDAI__SetMinSingleTrade() public {
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

    function testYearnDAI__IsActive() public {
        vault.addStrategy(address(strategy), 10_000, 0, 0, 0);
        assertEq(strategy.isActive(), false);

        deal(DAI_POLYGON, address(strategy), 1 ether);
        assertEq(strategy.isActive(), false);

        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
        vm.stopPrank();

        strategy.divest(IERC20(YVAULT_DAI_POLYGON).balanceOf(address(strategy)));
        vm.startPrank(address(strategy));
        IERC20(DAI_POLYGON).transfer(makeAddr("random"), IERC20(DAI_POLYGON).balanceOf(address(strategy)));
        assertEq(strategy.isActive(), false);

        deal(DAI_POLYGON, address(strategy), 1 ether);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(strategy.isActive(), true);
    }

    function testYearnDAI__SetStrategist() public {
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
    function testYearnDAI__InvestmentSlippage() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        vm.startPrank(users.keeper);

        // Expect revert if output amount is gt amount obtained
        vm.expectRevert(abi.encodeWithSignature("MinOutputAmountNotReached()"));
        strategy.harvest(0, type(uint256).max, address(0), block.timestamp);
    }

    function testYearnDAI__PrepareReturn() public {
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

        deal({ token: DAI_POLYGON, to: address(strategy), give: 60 ether });
        strategy.invest(60 ether, 0);

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        uint256 beforeReturnSnapshotId = vm.snapshot();

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);
        // assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 59.999999999999999999 ether);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        // assertEq(realizedProfit, 59.999999999999999998 ether);
        assertEq(unrealizedProfit, 59.999999999999999999 ether);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);

        vm.revertTo(beforeReturnSnapshotId);
        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        // assertEq(realizedProfit, 29.999999999999999999 ether);
        assertEq(unrealizedProfit, 59.999999999999999999 ether);
        assertEq(loss, 0);
        assertEq(debtPayment, 0);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 ether, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        strategy.triggerLoss(10 ether);

        beforeReturnSnapshotId = vm.snapshot();

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);
        // assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 0);
        assertEq(loss, 10 ether);
        assertEq(debtPayment, 0);
        vm.revertTo(beforeReturnSnapshotId);

        (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);
        // assertEq(realizedProfit, 0);
        assertEq(unrealizedProfit, 0);
        assertEq(loss, 10 ether);
        assertEq(debtPayment, 0);

        vm.revertTo(snapshotId);
    }

    function testYearnDAI__AdjustPosition() public {
        strategy.adjustPosition();
        assertEq(IERC20(YVAULT_DAI_POLYGON).balanceOf(address(strategy)), 0);

        deal({ token: DAI_POLYGON, to: address(strategy), give: 10 ether });
        uint256 expectedShares = strategy.sharesForAmount(10 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 10 ether);
        strategy.adjustPosition();
        assertEq(expectedShares, IERC20(YVAULT_DAI_POLYGON).balanceOf(address(strategy)));

        deal({ token: DAI_POLYGON, to: address(strategy), give: 100 ether });
        expectedShares += strategy.sharesForAmount(100 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 100 ether);
        strategy.adjustPosition();
        assertEq(expectedShares, IERC20(YVAULT_DAI_POLYGON).balanceOf(address(strategy)));

        deal({ token: DAI_POLYGON, to: address(strategy), give: 500 ether });
        expectedShares += strategy.sharesForAmount(500 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 500 ether);
        strategy.adjustPosition();
        assertEq(expectedShares, IERC20(YVAULT_DAI_POLYGON).balanceOf(address(strategy)));
    }

    function testYearnDAI__Invest() public {
        uint256 returned = strategy.invest(0, 0);
        assertEq(returned, 0);
        assertEq(IERC20(YVAULT_DAI_POLYGON).balanceOf(address(strategy)), 0);

        vm.expectRevert(abi.encodeWithSignature("NotEnoughFundsToInvest()"));
        returned = strategy.invest(1, 0);

        deal({ token: DAI_POLYGON, to: address(strategy), give: 10 ether });
        uint256 expectedShares = strategy.sharesForAmount(10 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 10 ether);
        strategy.invest(10 ether, 0);
        assertEq(expectedShares, IERC20(YVAULT_DAI_POLYGON).balanceOf(address(strategy)));

        deal({ token: DAI_POLYGON, to: address(strategy), give: 10 ether });
        expectedShares += strategy.sharesForAmount(10 ether);
        vm.expectEmit();
        emit Invested(address(strategy), 10 ether);
        strategy.invest(10 ether, 0);
        assertEq(expectedShares, IERC20(YVAULT_DAI_POLYGON).balanceOf(address(strategy)));
    }

    function testYearnDAI__Divest() public {
        deal({ token: DAI_POLYGON, to: address(strategy), give: 10 ether });
        uint256 expectedShares = strategy.sharesForAmount(10 ether);
        strategy.invest(10 ether, 0);
        assertEq(expectedShares, IERC20(YVAULT_DAI_POLYGON).balanceOf(address(strategy)));

        uint256 strategyBalanceBefore = IERC20(DAI_POLYGON).balanceOf(address(strategy));
        vm.expectEmit();
        emit Divested(address(strategy), expectedShares, 10 ether - 1);
        uint256 amountDivested = strategy.divest(expectedShares);
        assertEq(amountDivested, 10 ether - 1);
        assertEq(IERC20(DAI_POLYGON).balanceOf(address(strategy)), strategyBalanceBefore + amountDivested);
    }

    function testYearnDAI__LiquidatePosition() public {
        deal({ token: DAI_POLYGON, to: address(strategy), give: 10 ether });
        (uint256 liquidatedAmount, uint256 loss) = strategy.liquidatePosition(1 ether);
        assertEq(liquidatedAmount, 1 ether);
        assertEq(loss, 0);

        (liquidatedAmount, loss) = strategy.liquidatePosition(10 ether);
        assertEq(liquidatedAmount, 10 ether);
        assertEq(loss, 0);

        deal({ token: DAI_POLYGON, to: address(strategy), give: 5 ether });
        strategy.invest(5 ether, 0);
        deal({ token: DAI_POLYGON, to: address(strategy), give: 10 ether });
        (liquidatedAmount, loss) = strategy.liquidatePosition(15 ether);
        assertEq(liquidatedAmount, 14.999999999999999999 ether);
        assertEq(loss, 1);

        deal({ token: DAI_POLYGON, to: address(strategy), give: 1000 ether });
        strategy.invest(1000 ether, 0);
        deal({ token: DAI_POLYGON, to: address(strategy), give: 500 ether });
        (liquidatedAmount, loss) = strategy.liquidatePosition(1000 ether);
        assertEq(liquidatedAmount, 999.999999999999999999 ether);
        assertEq(loss, 1);
    }

    function testYearnDAI__LiquidateAllPositions() public {
        deal({ token: DAI_POLYGON, to: address(strategy), give: 10 ether });
        uint256 expectedShares = strategy.sharesForAmount(10 ether);
        strategy.invest(10 ether, 0);
        assertEq(expectedShares, IERC20(YVAULT_DAI_POLYGON).balanceOf(address(strategy)));

        uint256 strategyBalanceBefore = IERC20(DAI_POLYGON).balanceOf(address(strategy));
        uint256 amountFreed = strategy.liquidateAllPositions();
        assertEq(amountFreed, 9.999999999999999999 ether);
        assertEq(IERC20(DAI_POLYGON).balanceOf(address(strategy)), strategyBalanceBefore + 9.999999999999999999 ether);
        assertEq(IERC20(YVAULT_DAI_POLYGON).balanceOf(address(strategy)), 0);

        deal({ token: DAI_POLYGON, to: address(strategy), give: 500 ether });
        expectedShares = strategy.sharesForAmount(500 ether);
        strategy.invest(500 ether, 0);
        assertEq(expectedShares, IERC20(YVAULT_DAI_POLYGON).balanceOf(address(strategy)));

        strategyBalanceBefore = IERC20(DAI_POLYGON).balanceOf(address(strategy));
        amountFreed = strategy.liquidateAllPositions();
        assertEq(amountFreed, 499.999999999999999999 ether);
        assertEq(IERC20(DAI_POLYGON).balanceOf(address(strategy)), strategyBalanceBefore + 499.999999999999999999 ether);
        assertEq(IERC20(YVAULT_DAI_POLYGON).balanceOf(address(strategy)), 0);
    }

    function testYearnDAI__Harvest() public {
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

        uint256 expectedStrategyShareBalance = strategy.sharesForAmount(40 ether);
        assertEq(IERC20(DAI_POLYGON).balanceOf(address(vault)), 60 ether);
        assertEq(IERC20(YVAULT_DAI_POLYGON).balanceOf(address(strategy)), expectedStrategyShareBalance, "1");

        deal({ token: DAI_POLYGON, to: address(strategy), give: 10 ether });

        vm.expectEmit();
        emit StrategyReported(address(strategy), 10 ether, 0, 0, 10 ether, 0, 40 ether, 0, 4000);

        vm.expectEmit();
        emit Harvested(10 ether, 0, 0, 0);
        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(DAI_POLYGON).balanceOf(address(vault)), 60 ether);
        uint256 shares = strategy.sharesForAmount(10 ether);
        assertEq(IERC20(YVAULT_DAI_POLYGON).balanceOf(address(strategy)), expectedStrategyShareBalance + shares, "2");

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
        assertEq(IERC20(DAI_POLYGON).balanceOf(address(vault)), 60 ether);
        assertEq(IERC20(YVAULT_DAI_POLYGON).balanceOf(address(strategy)), expectedStrategyShareBalance, "4");

        vm.startPrank(users.alice);
        strategy.setEmergencyExit(2);

        vm.startPrank(users.keeper);

        deal({ token: DAI_POLYGON, to: address(strategy), give: 10 ether });

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 0, 40 ether, 0, 0, 0, 0, 4000);

        vm.expectEmit();
        emit Harvested(0, 0, 49.999999999999999999 ether, 0);

        strategy.harvest(0, 0, address(0), block.timestamp);
        assertEq(IERC20(DAI_POLYGON).balanceOf(address(vault)), 109.999999999999999999 ether);
        assertEq(IERC20(YVAULT_DAI_POLYGON).balanceOf(address(strategy)), 0);

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
        assertEq(IERC20(DAI_POLYGON).balanceOf(address(vault)), 60 ether);
        assertEq(IERC20(YVAULT_DAI_POLYGON).balanceOf(address(strategy)), expectedStrategyShareBalance, "5");

        uint256 expectedShares = strategy.sharesForAmount(10 ether);

        vm.startPrank(address(strategy));
        IERC20(YVAULT_DAI_POLYGON).transfer(makeAddr("random"), expectedShares);

        vm.startPrank(users.keeper);
        vm.expectEmit();
        emit StrategyReported(
            address(strategy), 0, 9.999999999999999999 ether, 0, 0, 9.999999999999999999 ether, 30 ether + 1, 0, 3001
        );

        vm.expectEmit();
        emit Harvested(0, 9.999999999999999999 ether, 0, 2.991000000000000001 ether);
        strategy.harvest(0, 0, address(0), block.timestamp);

        StrategyData memory data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3001);
        assertEq(vault.totalDebt(), 30 ether + 1);
        assertEq(data.strategyDebtRatio, 3001);
        assertEq(data.strategyTotalDebt, 30 ether + 1);
        assertEq(data.strategyTotalLoss, 9.999999999999999999 ether);

        vm.expectEmit();
        emit StrategyReported(address(strategy), 0, 1, 2.991 ether, 0, 10 ether, 27.009 ether, 0, 3001);

        vm.expectEmit();
        emit Harvested(0, 1 wei, 2.991 ether, 0);

        uint256 vaultBalanceBefore = IERC20(DAI_POLYGON).balanceOf(address(vault));
        uint256 strategyBalanceBefore = IERC20(YVAULT_DAI_POLYGON).balanceOf(address(strategy));
        uint256 expectedShareDecrease = strategy.sharesForAmount(2.991 ether);

        strategy.harvest(0, 0, address(0), block.timestamp);

        data = vault.strategies(address(strategy));

        assertEq(vault.debtRatio(), 3001);
        assertEq(vault.totalDebt(), 27.009 ether);
        assertEq(data.strategyDebtRatio, 3001);
        assertEq(data.strategyTotalDebt, 27.009 ether);
        assertEq(data.strategyTotalLoss, 10 ether);
        assertEq(IERC20(DAI_POLYGON).balanceOf(address(vault)), vaultBalanceBefore + 2.991 ether);
        assertLe(IERC20(YVAULT_DAI_POLYGON).balanceOf(address(strategy)), strategyBalanceBefore - expectedShareDecrease);
    }

    function testYearnDAI__PreviewLiquidate() public {
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

    function testYearnDAI__PreviewLiquidateExact() public {
        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);
        vault.deposit(100 ether, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 requestedAmount = strategy.previewLiquidateExact(30 ether);
        vm.startPrank(address(vault));
        uint256 balanceBefore = IERC20(DAI_POLYGON).balanceOf(address(vault));
        strategy.liquidateExact(30 ether);
        uint256 withdrawn = IERC20(DAI_POLYGON).balanceOf(address(vault)) - balanceBefore;
        // withdraw exactly what requested
        assertEq(withdrawn, 30 ether);
        // losses are equal or fewer than expected
        assertLe(withdrawn - 30 ether, requestedAmount - 30 ether);
    }

    function testYearnDAI__maxLiquidateExact() public {
        vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
        vault.deposit(100 ether, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 maxLiquidateExact = strategy.maxLiquidateExact();
        uint256 balanceBefore = IERC20(DAI_POLYGON).balanceOf(address(vault));
        uint256 requestedAmount = strategy.previewLiquidateExact(maxLiquidateExact);
        vm.startPrank(address(vault));
        uint256 losses = strategy.liquidateExact(maxLiquidateExact);
        uint256 withdrawn = IERC20(DAI_POLYGON).balanceOf(address(vault)) - balanceBefore;
        // withdraw exactly what requested
        assertEq(withdrawn, maxLiquidateExact);
        // losses are equal or fewer than expected
        assertLe(losses, requestedAmount - maxLiquidateExact);
    }

    function testYearnDAI__MaxLiquidate() public {
        vault.addStrategy(address(strategy), 9000, type(uint72).max, 0, 0);
        vault.deposit(100 ether, users.alice);
        vm.startPrank(users.keeper);
        strategy.harvest(0, 0, address(0), block.timestamp);
        vm.stopPrank();
        uint256 maxWithdraw = strategy.maxLiquidate();
        uint256 balanceBefore = IERC20(DAI_POLYGON).balanceOf(address(vault));
        vm.startPrank(address(vault));
        strategy.liquidate(maxWithdraw);
        uint256 withdrawn = IERC20(DAI_POLYGON).balanceOf(address(vault)) - balanceBefore;
        assertLe(withdrawn, maxWithdraw);
    }
}
