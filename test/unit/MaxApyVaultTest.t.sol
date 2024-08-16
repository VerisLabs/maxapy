// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { BaseTest, IERC20, Vm, console2 } from "../base/BaseTest.t.sol";
import { BaseVaultTest } from "../base/BaseVaultTest.t.sol";
import { MaxApyVault, StrategyData } from "src/MaxApyVault.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";
import { USDC_MAINNET, _1_USDC } from "test/helpers/Tokens.sol";

import { MockStrategy } from "../mock/MockStrategy.sol";
import { MockLossyUSDCStrategy } from "../mock/MockLossyUSDCStrategy.sol";
import { MockERC777, IERC1820Registry } from "../mock/MockERC777.sol";
import { ReentrantERC777AttackerDeposit } from "../mock/ReentrantERC777AttackerDeposit.sol";
import { ReentrantERC777AttackerWithdraw } from "../mock/ReentrantERC777AttackerWithdraw.sol";

import { IERC20Metadata } from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

contract MaxApyVaultTest is BaseVaultTest {
    function setUp() public {
        setupVault("MAINNET", USDC_MAINNET);

        IERC20(USDC_MAINNET).approve(address(vault), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(users.bob);
        IERC20(USDC_MAINNET).approve(address(vault), type(uint256).max);

        vm.startPrank(users.eve);
        IERC20(USDC_MAINNET).approve(address(vault), type(uint256).max);

        vm.startPrank(users.alice);

        vault.grantRoles(users.alice, vault.EMERGENCY_ADMIN_ROLE());

        vm.label(address(USDC_MAINNET), "USDC");
    }

    /*==================INITIALIZATION TESTS==================*/

    function testMaxApyVault__Initialization() public {
        assertEq(vault.performanceFee(), 1000);

        assertEq(vault.managementFee(), 200);

        assertEq(address(vault.asset()), USDC_MAINNET);

        assertEq(vault.name(), "MaxApyVaultUSDC");
        assertEq(vault.symbol(), "maxUSDCv2");
        assertEq(vault.decimals(), IERC20Metadata(USDC_MAINNET).decimals() + 6);
    }

    /*==================ACCESS CONTROL TESTS==================*/

    function testMaxApyVault__OwnerNegatives() public {
        MaxApyVault maxApyVault = new MaxApyVault(users.alice, USDC_MAINNET, "MaxApyVaultUSDC", "maxUSDCv2", TREASURY);

        IMaxApyVault vaultOwnership = IMaxApyVault(address(maxApyVault));
        assertEq(vaultOwnership.owner(), users.alice);

        vm.expectRevert(abi.encodeWithSignature("NewOwnerIsZeroAddress()"));
        vaultOwnership.transferOwnership(address(0));

        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vaultOwnership.transferOwnership(address(0));

        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vaultOwnership.renounceOwnership();

        vaultOwnership.requestOwnershipHandover();
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vaultOwnership.completeOwnershipHandover(users.bob);

        vaultOwnership.requestOwnershipHandover();
        vm.warp(block.timestamp + (48 * 3600) + 1);
        vm.startPrank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("NoHandoverRequest()"));
        vaultOwnership.completeOwnershipHandover(users.bob);

        vm.startPrank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("NoHandoverRequest()"));
        vaultOwnership.completeOwnershipHandover(users.eve);
    }

    function testMaxApyVault__OwnerPositives() public {
        MaxApyVault maxApyVault = new MaxApyVault(users.alice, USDC_MAINNET, "MaxApyVaultUSDC", "maxUSDCv2", TREASURY);

        IMaxApyVault vaultOwnership = IMaxApyVault(address(maxApyVault));
        assertEq(vaultOwnership.owner(), users.alice);

        vm.expectEmit();
        emit OwnershipTransferred(users.alice, users.bob);
        vaultOwnership.transferOwnership(users.bob);
        assertEq(vaultOwnership.owner(), users.bob);

        vm.startPrank(users.bob);
        vm.expectEmit();
        emit OwnershipTransferred(users.bob, users.alice);
        vaultOwnership.transferOwnership(users.alice);
        assertEq(vaultOwnership.owner(), users.alice);

        vm.expectEmit();
        emit OwnershipHandoverRequested(users.bob);
        vaultOwnership.requestOwnershipHandover();
        assertEq(vaultOwnership.ownershipHandoverExpiresAt(users.bob), block.timestamp + (48 * 3600));

        vm.expectEmit();
        emit OwnershipHandoverCanceled(users.bob);
        vaultOwnership.cancelOwnershipHandover();
        assertEq(vaultOwnership.ownershipHandoverExpiresAt(users.bob), 0);

        vm.expectEmit();
        emit OwnershipHandoverRequested(users.bob);
        vaultOwnership.requestOwnershipHandover();
        assertEq(vaultOwnership.ownershipHandoverExpiresAt(users.bob), block.timestamp + (48 * 3600));

        vm.startPrank(users.alice);
        vm.expectEmit();
        emit OwnershipTransferred(users.alice, users.bob);
        vaultOwnership.completeOwnershipHandover(users.bob);
        assertEq(vaultOwnership.ownershipHandoverExpiresAt(users.bob), 0);
        assertEq(vaultOwnership.owner(), users.bob);

        vm.startPrank(users.alice);
        vm.expectEmit();
        emit OwnershipHandoverRequested(users.alice);
        vaultOwnership.requestOwnershipHandover();
        assertEq(vaultOwnership.ownershipHandoverExpiresAt(users.alice), block.timestamp + (48 * 3600));

        vm.warp(block.timestamp + (48 * 3600));

        vm.startPrank(users.bob);
        vm.expectEmit();
        emit OwnershipTransferred(users.bob, users.alice);
        vaultOwnership.completeOwnershipHandover(users.alice);
        assertEq(vaultOwnership.ownershipHandoverExpiresAt(users.alice), 0);
        assertEq(vaultOwnership.owner(), users.alice);

        vm.startPrank(users.alice);
        vm.expectEmit();
        emit OwnershipTransferred(users.alice, address(0));
        vaultOwnership.renounceOwnership();
        assertEq(vaultOwnership.owner(), address(0));
    }

    function testMaxApyVault__RolesNegatives() public {
        MockStrategy mockStrategy = new MockStrategy(address(vault), USDC_MAINNET);

        MaxApyVault maxApyVault = new MaxApyVault(users.alice, USDC_MAINNET, "MaxApyVaultUSDC", "maxUSDCv2", TREASURY);

        IMaxApyVault vaultRoles = IMaxApyVault(address(maxApyVault));

        uint256 ADMIN_ROLE = vaultRoles.ADMIN_ROLE();
        uint256 EMERGENCY_ADMIN_ROLE = vaultRoles.EMERGENCY_ADMIN_ROLE();

        vaultRoles.grantRoles(users.bob, ADMIN_ROLE);
        vaultRoles.grantRoles(users.charlie, EMERGENCY_ADMIN_ROLE);

        assertEq(vaultRoles.owner(), users.alice);
        assertEq(vaultRoles.hasAnyRole(users.alice, ADMIN_ROLE), true);
        assertEq(vaultRoles.hasAnyRole(users.bob, ADMIN_ROLE), true);
        assertEq(vaultRoles.hasAnyRole(users.charlie, EMERGENCY_ADMIN_ROLE), true);

        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vaultRoles.grantRoles(users.eve, ADMIN_ROLE);

        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vaultRoles.revokeRoles(users.alice, ADMIN_ROLE);

        vm.startPrank(users.eve);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vault.addStrategy(address(mockStrategy), 4000, 0, 0, 0);

        vm.startPrank(users.charlie);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vault.addStrategy(address(mockStrategy), 4000, 0, 0, 0);

        vm.startPrank(users.eve);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vault.setEmergencyShutdown(true);

        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vault.setEmergencyShutdown(true);

        vm.startPrank(users.alice);
        vault.revokeRoles(users.alice, EMERGENCY_ADMIN_ROLE);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vault.setEmergencyShutdown(true);

        vault.grantRoles(users.alice, EMERGENCY_ADMIN_ROLE);
    }

    function testMaxApyVault__RolesPositives() public {
        MaxApyVault maxApyVault = new MaxApyVault(users.alice, USDC_MAINNET, "MaxApyVaultUSDC", "maxUSDCv2", TREASURY);

        IMaxApyVault vaultRoles = IMaxApyVault(address(maxApyVault));

        MockStrategy mockStrategy = new MockStrategy(address(vaultRoles), USDC_MAINNET);

        uint256 ADMIN_ROLE = vaultRoles.ADMIN_ROLE();
        uint256 EMERGENCY_ADMIN_ROLE = vaultRoles.EMERGENCY_ADMIN_ROLE();

        vaultRoles.grantRoles(users.alice, EMERGENCY_ADMIN_ROLE);
        vaultRoles.grantRoles(users.bob, ADMIN_ROLE);
        vaultRoles.grantRoles(users.charlie, EMERGENCY_ADMIN_ROLE);

        assertEq(vaultRoles.owner(), users.alice);
        assertEq(vaultRoles.hasAnyRole(users.alice, ADMIN_ROLE), true);
        assertEq(vaultRoles.hasAnyRole(users.alice, EMERGENCY_ADMIN_ROLE), true);
        assertEq(vaultRoles.hasAnyRole(users.bob, ADMIN_ROLE), true);
        assertEq(vaultRoles.hasAnyRole(users.charlie, EMERGENCY_ADMIN_ROLE), true);

        vm.expectEmit();
        emit RolesUpdated(users.eve, ADMIN_ROLE);
        vaultRoles.grantRoles(users.eve, ADMIN_ROLE);

        uint256 expectedRoles;
        assembly {
            expectedRoles := or(ADMIN_ROLE, EMERGENCY_ADMIN_ROLE)
        }
        vm.expectEmit();
        emit RolesUpdated(users.eve, expectedRoles);
        vaultRoles.grantRoles(users.eve, EMERGENCY_ADMIN_ROLE);

        vm.expectEmit();
        emit RolesUpdated(users.eve, EMERGENCY_ADMIN_ROLE);
        vaultRoles.revokeRoles(users.eve, ADMIN_ROLE);

        vm.expectEmit();
        emit RolesUpdated(users.eve, 0);
        vaultRoles.revokeRoles(users.eve, EMERGENCY_ADMIN_ROLE);

        vm.startPrank(users.bob);
        vm.expectEmit();
        emit RolesUpdated(users.bob, 0);
        vaultRoles.renounceRoles(ADMIN_ROLE);

        vm.startPrank(users.alice);
        vm.expectEmit();
        emit StrategyAdded(address(mockStrategy), 4000, 0, 0, 0);
        vaultRoles.addStrategy(address(mockStrategy), 4000, 0, 0, 0);

        mockStrategy = new MockStrategy(address(vaultRoles), USDC_MAINNET);
        vaultRoles.grantRoles(users.bob, ADMIN_ROLE);
        vm.startPrank(users.bob);
        vm.expectEmit();
        emit StrategyAdded(address(mockStrategy), 4000, 0, 0, 0);
        vaultRoles.addStrategy(address(mockStrategy), 4000, 0, 0, 0);

        vm.startPrank(users.alice);
        vm.expectEmit();
        emit EmergencyShutdownUpdated(false);
        vaultRoles.setEmergencyShutdown(false);

        vm.startPrank(users.charlie);
        vm.expectEmit();
        emit EmergencyShutdownUpdated(false);
        vaultRoles.setEmergencyShutdown(false);
    }

    /*==================STRATEGIES CONFIGURATION TESTS==================*/

    function testMaxApyVault__AddStrategyNegatives() public {
        MaxApyVault maxApyVault = new MaxApyVault(users.alice, USDC_MAINNET, "MaxApyVaultUSDC", "maxUSDCv2", TREASURY);

        IMaxApyVault fullQueueVault = IMaxApyVault(address(maxApyVault));

        MockStrategy mockStrategy = new MockStrategy(address(fullQueueVault), USDC_MAINNET);

        for (uint256 i; i < vault.MAXIMUM_STRATEGIES();) {
            mockStrategy = new MockStrategy(address(fullQueueVault), USDC_MAINNET);
            fullQueueVault.addStrategy(address(mockStrategy), 0, 0, 0, 0);
            unchecked {
                ++i;
            }
        }

        mockStrategy = new MockStrategy(address(fullQueueVault), USDC_MAINNET);
        vm.expectRevert(abi.encodeWithSignature("QueueIsFull()"));
        fullQueueVault.addStrategy(address(mockStrategy), 0, 0, 0, 0);

        mockStrategy = new MockStrategy(address(vault), USDC_MAINNET);

        vault.setEmergencyShutdown(true);
        vm.expectRevert(abi.encodeWithSignature("VaultInEmergencyShutdownMode()"));
        vault.addStrategy(address(mockStrategy), 0, 0, 0, 0);
        vault.setEmergencyShutdown(false);

        vm.expectRevert(abi.encodeWithSignature("InvalidZeroAddress()"));
        vault.addStrategy(address(0), 0, 0, 0, 0);

        vault.addStrategy(address(mockStrategy), 0, 0, 0, 0);
        vm.expectRevert(abi.encodeWithSignature("StrategyAlreadyActive()"));
        vault.addStrategy(address(mockStrategy), 0, 0, 0, 0);

        mockStrategy = new MockStrategy(address(0), USDC_MAINNET);
        vm.expectRevert(abi.encodeWithSignature("InvalidStrategyVault()"));
        vault.addStrategy(address(mockStrategy), 0, 0, 0, 0);

        mockStrategy = new MockStrategy(address(vault), address(0));
        vm.expectRevert(abi.encodeWithSignature("InvalidStrategyUnderlying()"));
        vault.addStrategy(address(mockStrategy), 0, 0, 0, 0);

        mockStrategy = new MockStrategy(address(vault), USDC_MAINNET);
        mockStrategy.setStrategist(address(0));
        vm.expectRevert(abi.encodeWithSignature("StrategyMustHaveStrategist()"));
        vault.addStrategy(address(mockStrategy), 0, 0, 0, 0);

        mockStrategy = new MockStrategy(address(vault), USDC_MAINNET);

        vm.expectRevert(abi.encodeWithSignature("InvalidDebtRatio()"));
        vault.addStrategy(address(mockStrategy), 10_001, 0, 0, 0);

        MaxApyVault maxApyVault2 = new MaxApyVault(users.alice, USDC_MAINNET, "MaxApyVaultUSDC", "maxUSDCv2", TREASURY);

        IMaxApyVault debtRatioVault = IMaxApyVault(address(maxApyVault2));

        mockStrategy = new MockStrategy(address(debtRatioVault), USDC_MAINNET);

        debtRatioVault.addStrategy(address(mockStrategy), 5600, 0, 0, 0);

        mockStrategy = new MockStrategy(address(debtRatioVault), USDC_MAINNET);
        vm.expectRevert(abi.encodeWithSignature("InvalidDebtRatio()"));
        debtRatioVault.addStrategy(address(mockStrategy), 4401, 0, 0, 0);

        mockStrategy = new MockStrategy(address(vault), USDC_MAINNET);

        vm.expectRevert(abi.encodeWithSignature("InvalidMinDebtPerHarvest()"));
        vault.addStrategy(address(mockStrategy), 10_000, 1_000_000, 1_000_001, 0);

        vm.expectRevert(abi.encodeWithSignature("InvalidMinDebtPerHarvest()"));
        vault.addStrategy(address(mockStrategy), 10_000, 0, 1, 0);

        vm.expectRevert(abi.encodeWithSignature("InvalidPerformanceFee()"));
        vault.addStrategy(address(mockStrategy), 10_000, 10, 1, 5001);

        vm.expectRevert(abi.encodeWithSignature("InvalidPerformanceFee()"));
        vault.addStrategy(address(mockStrategy), 10_000, 10, 1, 10_000);
    }

    function testMaxApyVault__AddStrategyPositives() public {
        MockStrategy mockStrategy = new MockStrategy(address(vault), USDC_MAINNET);
        assertEq(vault.MAXIMUM_STRATEGIES(), 20);
        address[] memory totalStrategies = new address[](20);

        vm.expectEmit();
        emit StrategyAdded(address(mockStrategy), 6000, type(uint72).max, 0, 4000);
        vault.addStrategy(address(mockStrategy), 6000, type(uint72).max, 0, 4000);

        StrategyData memory strategyData = vault.strategies(address(mockStrategy));
        assertEq(strategyData.strategyDebtRatio, 6000);
        assertEq(strategyData.strategyMaxDebtPerHarvest, type(uint72).max);
        assertEq(strategyData.strategyMinDebtPerHarvest, 0);
        assertEq(strategyData.strategyPerformanceFee, 4000);
        assertEq(strategyData.strategyLastReport, block.timestamp);
        assertEq(strategyData.strategyActivation, block.timestamp);
        assertEq(strategyData.strategyTotalLoss, 0);

        assertEq(vault.debtRatio(), 6000);
        assertEq(vault.withdrawalQueue(0), address(mockStrategy));

        totalStrategies[0] = address(mockStrategy);

        mockStrategy = new MockStrategy(address(vault), USDC_MAINNET);

        vm.expectEmit();
        emit StrategyAdded(address(mockStrategy), 20, type(uint72).max, type(uint24).max, 5000);
        vault.addStrategy(address(mockStrategy), 20, type(uint72).max, type(uint24).max, 5000);

        strategyData = vault.strategies(address(mockStrategy));
        assertEq(strategyData.strategyDebtRatio, 20);
        assertEq(strategyData.strategyMaxDebtPerHarvest, type(uint72).max);
        assertEq(strategyData.strategyMinDebtPerHarvest, type(uint24).max);
        assertEq(strategyData.strategyPerformanceFee, 5000);
        assertEq(strategyData.strategyLastReport, block.timestamp);
        assertEq(strategyData.strategyActivation, block.timestamp);
        assertEq(strategyData.strategyTotalLoss, 0);

        assertEq(vault.debtRatio(), 6020);
        assertEq(vault.withdrawalQueue(1), address(mockStrategy));

        totalStrategies[1] = address(mockStrategy);

        mockStrategy = new MockStrategy(address(vault), USDC_MAINNET);

        vm.expectEmit();
        emit StrategyAdded(address(mockStrategy), 3980, 0, 0, 488);
        vault.addStrategy(address(mockStrategy), 3980, 0, 0, 488);

        strategyData = vault.strategies(address(mockStrategy));
        assertEq(strategyData.strategyDebtRatio, 3980);
        assertEq(strategyData.strategyMaxDebtPerHarvest, 0);
        assertEq(strategyData.strategyMinDebtPerHarvest, 0);
        assertEq(strategyData.strategyPerformanceFee, 488);
        assertEq(strategyData.strategyLastReport, block.timestamp);
        assertEq(strategyData.strategyActivation, block.timestamp);
        assertEq(strategyData.strategyTotalLoss, 0);

        assertEq(vault.debtRatio(), 10_000);
        assertEq(vault.withdrawalQueue(2), address(mockStrategy));

        totalStrategies[2] = address(mockStrategy);

        assertEq(totalStrategies[0], vault.withdrawalQueue(0));
        assertEq(totalStrategies[1], vault.withdrawalQueue(1));
        assertEq(totalStrategies[2], vault.withdrawalQueue(2));
    }

    function testMaxApyVault__RevokeStrategy() public {
        MockStrategy mockStrategyNegatives = new MockStrategy(address(vault), USDC_MAINNET);
        MockStrategy mockStrategy = new MockStrategy(address(vault), USDC_MAINNET);

        vm.expectRevert(abi.encodeWithSignature("StrategyDebtRatioAlreadyZero()"));
        vault.revokeStrategy(address(mockStrategyNegatives));

        vault.addStrategy(address(mockStrategyNegatives), 4000, 0, 0, 0);
        vault.revokeStrategy(address(mockStrategyNegatives));
        vm.expectRevert(abi.encodeWithSignature("StrategyDebtRatioAlreadyZero()"));
        vault.revokeStrategy(address(mockStrategyNegatives));

        vault.addStrategy(address(mockStrategy), 4000, 0, 0, 0);
        assertEq(vault.debtRatio(), 4000);
        vm.expectEmit();
        emit StrategyRevoked(address(mockStrategy));
        vault.revokeStrategy(address(mockStrategy));
        assertEq(vault.debtRatio(), 0);
        StrategyData memory strategyData = vault.strategies(address(mockStrategy));
        assertEq(vault.debtRatio(), 0);
        assertEq(strategyData.strategyDebtRatio, 0);
    }

    function testMaxApyVault__RemoveStrategy() public {
        MockStrategy mockStrategy = new MockStrategy(address(vault), USDC_MAINNET);
        MockStrategy mockStrategy2 = new MockStrategy(address(vault), USDC_MAINNET);
        MockStrategy mockStrategy3 = new MockStrategy(address(vault), USDC_MAINNET);
        MockStrategy mockStrategy4 = new MockStrategy(address(vault), USDC_MAINNET);
        MockStrategy mockStrategy5 = new MockStrategy(address(vault), USDC_MAINNET);
        MockStrategy mockStrategy6 = new MockStrategy(address(vault), USDC_MAINNET);

        vault.addStrategy(address(mockStrategy), 2000, type(uint72).max, 0, 200);
        vault.addStrategy(address(mockStrategy2), 200, type(uint72).max, 0, 200);
        vault.addStrategy(address(mockStrategy3), 2000, type(uint72).max, 0, 200);
        vault.addStrategy(address(mockStrategy4), 20, type(uint72).max, 0, 200);
        vault.addStrategy(address(mockStrategy5), 200, type(uint72).max, 0, 200);
        vault.addStrategy(address(mockStrategy6), 20, type(uint72).max, 0, 100);

        changePrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vault.revokeStrategy(address(0));

        changePrank(users.alice);
        vault.removeStrategy(makeAddr("1"));

        vault.removeStrategy(address(mockStrategy4));

        assertEq(vault.withdrawalQueue(0), address(mockStrategy));
        assertEq(vault.withdrawalQueue(1), address(mockStrategy2));
        assertEq(vault.withdrawalQueue(2), address(mockStrategy3));
        assertEq(vault.withdrawalQueue(3), address(mockStrategy5));
        assertEq(vault.withdrawalQueue(4), address(mockStrategy6));

        vault.removeStrategy(address(mockStrategy));
        vault.removeStrategy(address(mockStrategy2));
        vault.removeStrategy(address(mockStrategy5));

        assertEq(vault.withdrawalQueue(0), address(mockStrategy3));
        assertEq(vault.withdrawalQueue(1), address(mockStrategy6));
        assertEq(vault.withdrawalQueue(2), address(0));
    }

    function testMaxApyVault__UpdateStrategyDataNegatives() public {
        MockStrategy mockStrategy = new MockStrategy(address(vault), USDC_MAINNET);
        MockStrategy mockStrategy2 = new MockStrategy(address(vault), USDC_MAINNET);

        vault.addStrategy(address(mockStrategy), 4000, 0, 0, 3000);

        vm.expectRevert(abi.encodeWithSignature("StrategyNotActive()"));
        vault.updateStrategyData(address(mockStrategy2), 4000, 0, 0, 3000);

        mockStrategy.setEmergencyExit(2);
        vm.expectRevert(abi.encodeWithSignature("StrategyInEmergencyExitMode()"));
        vault.updateStrategyData(address(mockStrategy), 4000, 0, 0, 3000);
        mockStrategy.setEmergencyExit(1);

        vm.expectRevert(abi.encodeWithSignature("InvalidMinDebtPerHarvest()"));
        vault.updateStrategyData(address(mockStrategy), 4000, 0, 1, 3000);

        vm.expectRevert(abi.encodeWithSignature("InvalidPerformanceFee()"));
        vault.updateStrategyData(address(mockStrategy), 4000, 0, 0, 5001);

        vm.expectRevert(abi.encodeWithSignature("InvalidDebtRatio()"));
        vault.updateStrategyData(address(mockStrategy), 10_001, 0, 0, 5000);

        MockStrategy mockStrategy3 = new MockStrategy(address(vault), USDC_MAINNET);
        vault.addStrategy(address(mockStrategy3), 2000, 0, 0, 3000);

        vm.expectRevert(abi.encodeWithSignature("InvalidDebtRatio()"));
        vault.updateStrategyData(address(mockStrategy), 8001, 0, 0, 5000);
    }

    function testMaxApyVault__UpdateStrategyDataPositives() public {
        MockStrategy mockStrategy = new MockStrategy(address(vault), USDC_MAINNET);
        MockStrategy mockStrategy2 = new MockStrategy(address(vault), USDC_MAINNET);

        MockStrategy mockStrategy3 = new MockStrategy(address(vault), USDC_MAINNET);

        vault.addStrategy(address(mockStrategy), 4000, 0, 0, 3000);
        vault.addStrategy(address(mockStrategy2), 3000, 0, 0, 299);
        vault.addStrategy(address(mockStrategy3), 2000, 0, 0, 5000);

        assertEq(vault.debtRatio(), 9000);

        StrategyData memory mockStrategyDataBefore = vault.strategies(address(mockStrategy));
        StrategyData memory mockStrategy2DataBefore = vault.strategies(address(mockStrategy2));
        StrategyData memory mockStrategy3DataBefore = vault.strategies(address(mockStrategy3));

        vault.updateStrategyData(address(mockStrategy), 5000, type(uint72).max, type(uint24).max, 100);

        StrategyData memory mockStrategyData = vault.strategies(address(mockStrategy));
        assertEq(mockStrategyData.strategyDebtRatio, 5000);
        assertEq(mockStrategyData.strategyMaxDebtPerHarvest, type(uint72).max);
        assertEq(mockStrategyData.strategyMinDebtPerHarvest, type(uint24).max);
        assertEq(mockStrategyData.strategyPerformanceFee, 100);
        assertEq(mockStrategyData.strategyLastReport, mockStrategyDataBefore.strategyLastReport);
        assertEq(mockStrategyData.strategyActivation, mockStrategyDataBefore.strategyActivation);
        assertEq(mockStrategyData.strategyTotalDebt, 0);
        assertEq(mockStrategyData.strategyTotalLoss, 0);

        assertEq(
            vault.debtRatio(),
            5000 + mockStrategy2DataBefore.strategyDebtRatio + mockStrategy3DataBefore.strategyDebtRatio
        );

        vault.updateStrategyData(address(mockStrategy2), 100, 200, 10, 4999);

        StrategyData memory mockStrategyData2 = vault.strategies(address(mockStrategy2));
        assertEq(mockStrategyData2.strategyDebtRatio, 100);
        assertEq(mockStrategyData2.strategyMaxDebtPerHarvest, 200);
        assertEq(mockStrategyData2.strategyMinDebtPerHarvest, 10);
        assertEq(mockStrategyData2.strategyPerformanceFee, 4999);
        assertEq(mockStrategyData2.strategyLastReport, mockStrategy2DataBefore.strategyLastReport);
        assertEq(mockStrategyData2.strategyActivation, mockStrategy2DataBefore.strategyActivation);
        assertEq(mockStrategyData2.strategyTotalDebt, 0);
        assertEq(mockStrategyData2.strategyTotalLoss, 0);

        assertEq(vault.debtRatio(), 5000 + 100 + mockStrategy3DataBefore.strategyDebtRatio);

        vault.updateStrategyData(address(mockStrategy3), 4786, 1999, 45, 1);

        StrategyData memory mockStrategyData3 = vault.strategies(address(mockStrategy3));
        assertEq(mockStrategyData3.strategyDebtRatio, 4786);
        assertEq(mockStrategyData3.strategyMaxDebtPerHarvest, 1999);
        assertEq(mockStrategyData3.strategyMinDebtPerHarvest, 45);
        assertEq(mockStrategyData3.strategyPerformanceFee, 1);
        assertEq(mockStrategyData3.strategyLastReport, mockStrategy3DataBefore.strategyLastReport);
        assertEq(mockStrategyData3.strategyActivation, mockStrategy3DataBefore.strategyActivation);
        assertEq(mockStrategyData3.strategyTotalDebt, 0);
        assertEq(mockStrategyData3.strategyTotalLoss, 0);

        assertEq(vault.debtRatio(), 5000 + 100 + 4786);
    }

    /*==================VAULT CONFIGURATION TESTS==================*/

    function testMaxApyVault__SetWithdrawalQueueNegatives() public {
        MockStrategy mockStrategy = new MockStrategy(address(vault), USDC_MAINNET);
        MockStrategy mockStrategy2 = new MockStrategy(address(vault), USDC_MAINNET);

        MockStrategy mockStrategy3 = new MockStrategy(address(vault), USDC_MAINNET);

        vault.addStrategy(address(mockStrategy), 2000, type(uint72).max, 0, 200);
        vault.addStrategy(address(mockStrategy2), 2000, type(uint72).max, 0, 200);
        vault.addStrategy(address(mockStrategy3), 2000, type(uint72).max, 0, 200);

        MockStrategy mockStrategy4 = new MockStrategy(address(vault), USDC_MAINNET);

        address[20] memory queue;
        queue[0] = address(mockStrategy);
        queue[1] = address(0);
        queue[2] = address(mockStrategy2);

        vm.expectRevert(abi.encodeWithSignature("InvalidQueueOrder()"));
        vault.setWithdrawalQueue(queue);

        queue[0] = address(0);
        queue[1] = address(mockStrategy);

        vm.expectRevert(abi.encodeWithSignature("InvalidQueueOrder()"));
        vault.setWithdrawalQueue(queue);

        queue[0] = address(mockStrategy);
        queue[1] = address(mockStrategy2);
        queue[2] = address(mockStrategy3);
        queue[3] = address(mockStrategy4);

        vm.expectRevert(abi.encodeWithSignature("StrategyNotActive()"));
        vault.setWithdrawalQueue(queue);

        queue[0] = address(mockStrategy4);
        queue[1] = address(0);
        queue[2] = address(0);
        queue[3] = address(0);

        vm.expectRevert(abi.encodeWithSignature("StrategyNotActive()"));
        vault.setWithdrawalQueue(queue);
    }

    function testMaxApyVault__SetWithdrawalQueuePositives() public {
        MockStrategy mockStrategy = new MockStrategy(address(vault), USDC_MAINNET);
        MockStrategy mockStrategy2 = new MockStrategy(address(vault), USDC_MAINNET);

        MockStrategy mockStrategy3 = new MockStrategy(address(vault), USDC_MAINNET);

        vault.addStrategy(address(mockStrategy), 2000, type(uint72).max, 0, 200);
        vault.addStrategy(address(mockStrategy2), 2000, type(uint72).max, 0, 200);
        vault.addStrategy(address(mockStrategy3), 2000, type(uint72).max, 0, 200);

        MockStrategy mockStrategy4 = new MockStrategy(address(vault), USDC_MAINNET);

        assertEq(vault.withdrawalQueue(0), address(mockStrategy));
        assertEq(vault.withdrawalQueue(1), address(mockStrategy2));
        assertEq(vault.withdrawalQueue(2), address(mockStrategy3));

        address[20] memory queue;
        queue[0] = address(mockStrategy3);
        queue[1] = address(mockStrategy);
        queue[2] = address(mockStrategy2);

        vm.expectEmit();
        emit WithdrawalQueueUpdated(queue);
        vault.setWithdrawalQueue(queue);

        uint256 maxStrategies = vault.MAXIMUM_STRATEGIES();
        for (uint256 i; i < maxStrategies;) {
            address strategy;
            if (i == 0) strategy = address(mockStrategy3);
            if (i == 1) strategy = address(mockStrategy);
            if (i == 2) strategy = address(mockStrategy2);

            assertEq(vault.withdrawalQueue(i), strategy);

            unchecked {
                ++i;
            }
        }

        vault.addStrategy(address(mockStrategy4), 2000, type(uint72).max, 0, 200);
        assertEq(vault.withdrawalQueue(0), address(mockStrategy3));
        assertEq(vault.withdrawalQueue(1), address(mockStrategy));
        assertEq(vault.withdrawalQueue(2), address(mockStrategy2));
        assertEq(vault.withdrawalQueue(3), address(mockStrategy4));

        queue[0] = address(mockStrategy4);
        queue[1] = address(mockStrategy2);
        queue[2] = address(mockStrategy);
        queue[3] = address(mockStrategy3);

        vm.expectEmit();
        emit WithdrawalQueueUpdated(queue);
        vault.setWithdrawalQueue(queue);

        for (uint256 i; i < maxStrategies;) {
            address strategy;
            if (i == 0) strategy = address(mockStrategy4);
            if (i == 1) strategy = address(mockStrategy2);
            if (i == 2) strategy = address(mockStrategy);
            if (i == 3) strategy = address(mockStrategy3);
            assertEq(vault.withdrawalQueue(i), strategy);

            unchecked {
                ++i;
            }
        }

        queue[0] = address(mockStrategy4);
        queue[1] = address(mockStrategy2);
        queue[2] = address(mockStrategy3);
        queue[3] = address(0);
        vm.expectEmit();
        emit WithdrawalQueueUpdated(queue);
        vault.setWithdrawalQueue(queue);

        for (uint256 i; i < maxStrategies;) {
            address strategy;
            if (i == 0) strategy = address(mockStrategy4);
            if (i == 1) strategy = address(mockStrategy2);
            if (i == 2) strategy = address(mockStrategy3);
            assertEq(vault.withdrawalQueue(i), strategy);

            unchecked {
                ++i;
            }
        }
    }

    function testMaxApyVault__SetEmergencyShutdown() public {
        assertEq(vault.emergencyShutdown(), false);
        vm.expectEmit();
        emit EmergencyShutdownUpdated(true);
        vault.setEmergencyShutdown(true);
        assertEq(vault.emergencyShutdown(), true);
        vm.expectEmit();
        emit EmergencyShutdownUpdated(false);
        vault.setEmergencyShutdown(false);
        assertEq(vault.emergencyShutdown(), false);
    }

    function testMaxApyVault__SetPerformanceFee() public {
        vm.startPrank(users.eve);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vault.setPerformanceFee(5001);
        vm.stopPrank();

        vm.startPrank(users.alice);

        vm.expectRevert(abi.encodeWithSignature("InvalidPerformanceFee()"));
        vault.setPerformanceFee(5001);

        vm.expectRevert(abi.encodeWithSignature("InvalidPerformanceFee()"));
        vault.setPerformanceFee(10_000);

        vm.expectEmit();
        emit PerformanceFeeUpdated(4999);
        vault.setPerformanceFee(4999);
        assertEq(vault.performanceFee(), 4999);

        vm.expectEmit();
        emit PerformanceFeeUpdated(20);
        vault.setPerformanceFee(20);
        assertEq(vault.performanceFee(), 20);

        vm.expectEmit();
        emit PerformanceFeeUpdated(0);
        vault.setPerformanceFee(0);
        assertEq(vault.performanceFee(), 0);
    }

    function testMaxApyVault__SetManagementFee() public {
        vm.startPrank(users.eve);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vault.setManagementFee(10_001);
        vm.stopPrank();

        vm.startPrank(users.alice);

        vm.expectRevert(abi.encodeWithSignature("InvalidManagementFee()"));
        vault.setManagementFee(10_001);

        vm.expectRevert(abi.encodeWithSignature("InvalidManagementFee()"));
        vault.setManagementFee(11_882);

        vm.expectEmit();
        emit ManagementFeeUpdated(9999);
        vault.setManagementFee(9999);
        assertEq(vault.managementFee(), 9999);

        vm.expectEmit();
        emit ManagementFeeUpdated(10_000);
        vault.setManagementFee(10_000);
        assertEq(vault.managementFee(), 10_000);

        vm.expectEmit();
        emit ManagementFeeUpdated(1);
        vault.setManagementFee(1);
        assertEq(vault.managementFee(), 1);

        vm.expectEmit();
        emit ManagementFeeUpdated(0);
        vault.setManagementFee(0);
        assertEq(vault.managementFee(), 0);
    }

    function testMaxApyVault__SetMaxDeposit() public {
        vm.startPrank(users.eve);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vault.setDepositLimit(9999);
        vm.stopPrank();

        vm.startPrank(users.alice);

        vm.expectEmit();
        emit DepositLimitUpdated(9999);
        vault.setDepositLimit(9999);
        assertEq(vault.maxDeposit(address(0)), 9999);

        vm.expectEmit();
        emit DepositLimitUpdated(0);
        vault.setDepositLimit(0);
        assertEq(vault.maxDeposit(address(0)), 0);

        vm.expectEmit();
        emit DepositLimitUpdated(type(uint256).max);
        vault.setDepositLimit(type(uint256).max);
        assertEq(vault.maxDeposit(address(0)), type(uint256).max);
    }

    function testMaxApyVault__SetTreasury() public {
        vm.startPrank(users.eve);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vault.setTreasury(makeAddr("random"));

        vm.stopPrank();
        vm.startPrank(users.alice);
        vault.setTreasury(makeAddr("random"));

        assertEq(vault.treasury(), makeAddr("random"));
    }

    /*==================USER-FACING FUNCTIONS TESTS==================*/

    // TODO: max TVL limit or deposit limit?
    function testMaxApyVault__DepositNegatives() public {
        ReentrantERC777AttackerDeposit reentrantAttacker = new ReentrantERC777AttackerDeposit();

        MockERC777 token = new MockERC777("Test", "TST", new address[](0), address(reentrantAttacker));

        MaxApyVault maxApyVault =
            new MaxApyVault(address(this), address(token), "MaxApyERC777Vault", "max777", TREASURY);

        IMaxApyVault vaultReentrant = IMaxApyVault(address(maxApyVault));

        reentrantAttacker.setVault(vaultReentrant);

        vm.startPrank(address(reentrantAttacker));
        token.approve(address(vaultReentrant), type(uint256).max);

        vm.startPrank(users.alice);

        vault.setEmergencyShutdown(true);
        vm.expectRevert(abi.encodeWithSignature("VaultInEmergencyShutdownMode()"));
        vault.deposit(1 * _1_USDC, users.alice);

        vault.setEmergencyShutdown(false);

        vm.expectRevert(abi.encodeWithSignature("TransferFromFailed()")); // reentrancy guard
        reentrantAttacker.attack(1);

        vm.expectRevert(abi.encodeWithSignature("InvalidZeroAddress()"));
        vault.deposit(1 * _1_USDC, address(0));

        vm.expectRevert(abi.encodeWithSignature("InvalidZeroAmount()"));
        vault.deposit(0, users.alice);

        vault.setDepositLimit(10 * _1_USDC);

        vm.expectRevert(abi.encodeWithSignature("VaultDepositLimitExceeded()"));
        vault.deposit(10 * _1_USDC + 1, users.alice);

        vault.deposit(5 * _1_USDC, users.alice);

        vm.expectRevert(abi.encodeWithSignature("VaultDepositLimitExceeded()"));
        vault.deposit(5 * _1_USDC + 1, users.alice);
    }

    function testMaxApyVault__DepositPositives() public {
        uint256 expectedShares = _calculateExpectedShares(1 * _1_USDC);
        vm.expectEmit();
        emit Deposit(users.alice, users.alice, 1 * _1_USDC, expectedShares);
        vault.deposit(1 * _1_USDC, users.alice);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 1 * _1_USDC);
        assertEq(vault.balanceOf(users.alice), 1 * _1_USDC * 10 ** 6);

        vm.warp(block.timestamp + 1);

        expectedShares = _calculateExpectedShares(150 * _1_USDC);
        vm.expectEmit();
        emit Deposit(users.alice, users.alice, 150 * _1_USDC, expectedShares);
        vault.deposit(150 * _1_USDC, users.alice);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 151 * _1_USDC);
        assertEq(vault.balanceOf(users.alice), 151 * _1_USDC * 10 ** 6);

        vm.warp(block.timestamp + 10 days);

        expectedShares = _calculateExpectedShares(10 * _1_USDC);
        vm.expectEmit();
        emit Deposit(users.alice, users.alice, 10 * _1_USDC, expectedShares);
        vault.deposit(10 * _1_USDC, users.alice);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 161 * _1_USDC);
        assertEq(vault.balanceOf(users.alice), 151 * _1_USDC * 10 ** 6 + expectedShares);
    }

    function testMaxApyVault__RedeemNegatives() public {
        ReentrantERC777AttackerWithdraw reentrantAttacker = new ReentrantERC777AttackerWithdraw();

        MockERC777 token = new MockERC777("Test", "TST", new address[](0), address(reentrantAttacker));

        MaxApyVault maxApyVault =
            new MaxApyVault(address(this), address(token), "MaxApyERC777Vault", "max777", TREASURY);

        IMaxApyVault vaultReentrant = IMaxApyVault(address(maxApyVault));

        reentrantAttacker.setVault(vaultReentrant);

        vm.startPrank(address(reentrantAttacker));
        token.approve(address(vaultReentrant), type(uint256).max);

        vm.startPrank(users.alice);

        uint256 expectedShares = _calculateExpectedShares(10 * _1_USDC);
        vault.deposit(10 * _1_USDC, users.alice);

        token.mint(users.alice, 1 * _1_USDC);
        token.approve(address(vaultReentrant), type(uint256).max);
        vm.expectRevert(abi.encodeWithSignature("TransferFromFailed()"));
        vaultReentrant.deposit(1 * _1_USDC, users.alice);

        MockLossyUSDCStrategy lossyStrategy =
            new MockLossyUSDCStrategy(address(vault), USDC_MAINNET, makeAddr("strategist"));
        MockLossyUSDCStrategy lossyStrategy2 =
            new MockLossyUSDCStrategy(address(vault), USDC_MAINNET, makeAddr("strategist"));
        MockLossyUSDCStrategy lossyStrategy3 =
            new MockLossyUSDCStrategy(address(vault), USDC_MAINNET, makeAddr("strategist"));

        deal({ token: USDC_MAINNET, to: address(lossyStrategy), give: 10 * _1_USDC });
        deal({ token: USDC_MAINNET, to: address(lossyStrategy2), give: 10 * _1_USDC });
        deal({ token: USDC_MAINNET, to: address(lossyStrategy3), give: 10 * _1_USDC });

        vault.addStrategy(address(lossyStrategy), 1000, type(uint72).max, 0, 1000);

        lossyStrategy.mockReport(0, 0, 0, TREASURY);

        StrategyData memory lossyStrategyData = vault.strategies(address(lossyStrategy));

        assertEq(lossyStrategyData.strategyTotalLoss, 0);

        assertEq(lossyStrategyData.strategyTotalDebt, 1 * _1_USDC);

        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 9 * _1_USDC);

        vm.expectRevert(abi.encodeWithSignature("RedeemMoreThanMax()"));
        vaultReentrant.redeem(expectedShares, users.alice, users.alice);

        vm.expectRevert(abi.encodeWithSignature("InvalidZeroShares()"));
        vault.redeem(0, users.alice, users.alice);
    }

    function testMaxApyVault__RedeemPositives() public {
        uint256 snapshotId = vm.snapshot();
        uint256 _shares;
        {
            _shares = _deposit(users.alice, vault, 10 * _1_USDC);

            uint256 redeemed = _redeem(users.alice, vault, _shares, 0);
            assertEq(redeemed, 10 * _1_USDC);
        }
        vm.revertTo(snapshotId);

        _deposit(users.alice, vault, 500 * _1_USDC);

        uint256 aliceBalanceBefore = IERC20(USDC_MAINNET).balanceOf(address(users.alice));

        uint256 valueWithdrawn = _redeem(users.alice, vault, 10 * 10 ** vault.decimals(), 0);

        valueWithdrawn += _redeem(users.alice, vault, 400 * 10 ** vault.decimals(), 0);

        valueWithdrawn += _redeem(users.alice, vault, 90 * 10 ** vault.decimals(), 0);

        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 0);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(users.alice)), aliceBalanceBefore + valueWithdrawn);
        assertEq(valueWithdrawn, 500 * _1_USDC);

        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();

        _shares = _deposit(users.alice, vault, 20 * _1_USDC);

        vm.startPrank(users.alice);
        MockLossyUSDCStrategy lossyStrategy =
            new MockLossyUSDCStrategy(address(vault), USDC_MAINNET, makeAddr("strategist"));

        vault.addStrategy(address(lossyStrategy), 5000, type(uint72).max, 0, 1000);

        lossyStrategy.mockReport(0, 0, 0, TREASURY);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy)), 10 * _1_USDC);
        lossyStrategy.setEstimatedTotalAssets(10 * _1_USDC);

        aliceBalanceBefore = IERC20(USDC_MAINNET).balanceOf(users.alice);
        StrategyWithdrawalPreviousData memory previousStrategyData;

        previousStrategyData.balance = IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy));

        uint256 vaultPreviousDebtRatio = vault.debtRatio();

        previousStrategyData.debtRatio = vault.strategies(address(lossyStrategy)).strategyDebtRatio;
        previousStrategyData.totalLoss = vault.strategies(address(lossyStrategy)).strategyTotalLoss;
        previousStrategyData.totalDebt = vault.strategies(address(lossyStrategy)).strategyTotalDebt;

        uint256 expectedRatioChange = _computeExpectedRatioChange(vault, address(lossyStrategy), 1 * _1_USDC);

        // we can only withdraw 19 USDC since the lossy strategy lost 1 USDC
        valueWithdrawn = _redeem(users.alice, vault, _shares, _1_USDC);

        assertEq(valueWithdrawn, 19 * _1_USDC);
        assertEq(IERC20(USDC_MAINNET).balanceOf(users.alice), aliceBalanceBefore + 19 * _1_USDC);
        assertEq(vault.balanceOf(users.alice), 0);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy)), previousStrategyData.balance - 9 * _1_USDC);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 0);

        assertEq(
            vault.strategies(address(lossyStrategy)).strategyDebtRatio,
            previousStrategyData.debtRatio - expectedRatioChange
        );
        assertEq(vault.debtRatio(), vaultPreviousDebtRatio - expectedRatioChange);
        assertEq(
            vault.strategies(address(lossyStrategy)).strategyTotalLoss, previousStrategyData.totalLoss + 1 * _1_USDC
        );
        assertEq(
            vault.strategies(address(lossyStrategy)).strategyTotalDebt, previousStrategyData.totalDebt - 10 * _1_USDC
        );
        assertEq(vault.totalDebt(), 0);
        assertEq(vault.totalIdle(), 0);

        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();

        _deposit(users.alice, vault, 50 * _1_USDC);

        vm.startPrank(users.alice);

        lossyStrategy = new MockLossyUSDCStrategy(address(vault), USDC_MAINNET, makeAddr("strategist"));

        MockLossyUSDCStrategy lossyStrategyFunded =
            new MockLossyUSDCStrategy(address(vault), USDC_MAINNET, makeAddr("strategist"));

        vault.addStrategy(address(lossyStrategy), 0, type(uint72).max, 0, 1000);

        vault.addStrategy(address(lossyStrategyFunded), 5000, type(uint72).max, 0, 1000);

        lossyStrategyFunded.mockReport(0, 0, 0, TREASURY);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(lossyStrategyFunded)), 25 * _1_USDC);
        lossyStrategyFunded.setEstimatedTotalAssets(25 * _1_USDC);

        aliceBalanceBefore = IERC20(USDC_MAINNET).balanceOf(users.alice);

        vaultPreviousDebtRatio = vault.debtRatio();

        previousStrategyData.balance = IERC20(USDC_MAINNET).balanceOf(address(lossyStrategyFunded));
        previousStrategyData.debtRatio = vault.strategies(address(lossyStrategyFunded)).strategyDebtRatio;
        previousStrategyData.totalLoss = vault.strategies(address(lossyStrategyFunded)).strategyTotalLoss;
        previousStrategyData.totalDebt = vault.strategies(address(lossyStrategyFunded)).strategyTotalDebt;
        expectedRatioChange = _computeExpectedRatioChange(vault, address(lossyStrategyFunded), 1 * _1_USDC);

        valueWithdrawn = _redeem(users.alice, vault, 50 * 10 ** vault.decimals(), _1_USDC);

        assertEq(valueWithdrawn, 49 * _1_USDC);
        assertEq(IERC20(USDC_MAINNET).balanceOf(users.alice), aliceBalanceBefore + 49 * _1_USDC);
        assertEq(vault.balanceOf(users.alice), 0);
        assertEq(
            IERC20(USDC_MAINNET).balanceOf(address(lossyStrategyFunded)), previousStrategyData.balance - 24 * _1_USDC
        );
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 0);

        assertEq(
            vault.strategies(address(lossyStrategyFunded)).strategyDebtRatio,
            previousStrategyData.debtRatio - expectedRatioChange
        );
        assertEq(vault.debtRatio(), vaultPreviousDebtRatio - expectedRatioChange);
        assertEq(
            vault.strategies(address(lossyStrategyFunded)).strategyTotalLoss,
            previousStrategyData.totalLoss + 1 * _1_USDC
        );
        assertEq(
            vault.strategies(address(lossyStrategyFunded)).strategyTotalDebt,
            previousStrategyData.totalDebt - 25 * _1_USDC
        );
        assertEq(vault.totalDebt(), 0);
        assertEq(vault.totalIdle(), 0);

        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();

        _deposit(users.alice, vault, 100 * _1_USDC);

        vm.startPrank(users.alice);

        lossyStrategy = new MockLossyUSDCStrategy(address(vault), USDC_MAINNET, makeAddr("strategist"));
        MockLossyUSDCStrategy lossyStrategy2 =
            new MockLossyUSDCStrategy(address(vault), USDC_MAINNET, makeAddr("strategist"));
        MockLossyUSDCStrategy lossyStrategy3 =
            new MockLossyUSDCStrategy(address(vault), USDC_MAINNET, makeAddr("strategist"));

        vault.addStrategy(address(lossyStrategy), 5000, type(uint72).max, 0, 1000);

        vault.addStrategy(address(lossyStrategy2), 2500, type(uint72).max, 0, 1000);

        vault.addStrategy(address(lossyStrategy3), 2500, type(uint72).max, 0, 1000);

        lossyStrategy.mockReport(0, 0, 0, TREASURY);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy)), 50 * _1_USDC);
        lossyStrategy2.mockReport(0, 0, 0, TREASURY);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy2)), 25 * _1_USDC);
        lossyStrategy3.mockReport(0, 0, 0, TREASURY);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy3)), 25 * _1_USDC);

        lossyStrategy.setEstimatedTotalAssets(50 * _1_USDC);
        lossyStrategy2.setEstimatedTotalAssets(25 * _1_USDC);
        lossyStrategy3.setEstimatedTotalAssets(25 * _1_USDC);

        aliceBalanceBefore = IERC20(USDC_MAINNET).balanceOf(users.alice);

        vaultPreviousDebtRatio = vault.debtRatio();

        previousStrategyData.balance = IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy));
        previousStrategyData.debtRatio = vault.strategies(address(lossyStrategy)).strategyDebtRatio;
        previousStrategyData.totalLoss = vault.strategies(address(lossyStrategy)).strategyTotalLoss;
        previousStrategyData.totalDebt = vault.strategies(address(lossyStrategy)).strategyTotalDebt;

        StrategyWithdrawalPreviousData memory previousStrategy2Data;

        previousStrategy2Data.balance = IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy2));
        previousStrategy2Data.debtRatio = vault.strategies(address(lossyStrategy2)).strategyDebtRatio;
        previousStrategy2Data.totalLoss = vault.strategies(address(lossyStrategy2)).strategyTotalLoss;
        previousStrategy2Data.totalDebt = vault.strategies(address(lossyStrategy2)).strategyTotalDebt;

        StrategyWithdrawalPreviousData memory previousStrategy3Data;

        previousStrategy3Data.balance = IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy3));
        previousStrategy3Data.debtRatio = vault.strategies(address(lossyStrategy3)).strategyDebtRatio;
        previousStrategy3Data.totalLoss = vault.strategies(address(lossyStrategy3)).strategyTotalLoss;
        previousStrategy3Data.totalDebt = vault.strategies(address(lossyStrategy3)).strategyTotalDebt;

        expectedRatioChange = _computeExpectedRatioChange(vault, address(lossyStrategy), 1 * _1_USDC);

        uint256 expectedRatioChange2 = _computeExpectedRatioChange(vault, address(lossyStrategy2), 1 * _1_USDC);

        valueWithdrawn = _redeem(
            users.alice,
            vault,
            65 * 10 ** vault.decimals(),
            2 * _1_USDC // 2 USDC loss expected due to withdrawal
        );

        {
            assertEq(valueWithdrawn, 63 * _1_USDC);
            assertEq(IERC20(USDC_MAINNET).balanceOf(users.alice), aliceBalanceBefore + 63 * _1_USDC);
            assertEq(vault.balanceOf(users.alice), 35 * _1_USDC * 10 ** 6);
            assertEq(
                IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy)), previousStrategyData.balance - 49 * _1_USDC
            );

            assertEq(
                IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy2)), previousStrategy2Data.balance - 14 * _1_USDC
            );

            assertEq(IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy3)), previousStrategy3Data.balance);

            assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 0);
        }

        assertEq(
            vault.strategies(address(lossyStrategy)).strategyDebtRatio,
            previousStrategyData.debtRatio - expectedRatioChange
        );

        assertEq(
            vault.strategies(address(lossyStrategy)).strategyTotalLoss, previousStrategyData.totalLoss + 1 * _1_USDC
        );
        assertEq(
            vault.strategies(address(lossyStrategy)).strategyTotalDebt, previousStrategyData.totalDebt - 50 * _1_USDC
        );

        assertLt(
            vault.strategies(address(lossyStrategy2)).strategyDebtRatio,
            previousStrategy2Data.debtRatio - expectedRatioChange2
        );

        assertEq(
            vault.strategies(address(lossyStrategy2)).strategyTotalLoss, previousStrategy2Data.totalLoss + 1 * _1_USDC
        );
        assertEq(
            vault.strategies(address(lossyStrategy2)).strategyTotalDebt, previousStrategy2Data.totalDebt - 15 * _1_USDC
        );

        assertEq(vault.strategies(address(lossyStrategy3)).strategyDebtRatio, previousStrategy3Data.debtRatio);

        assertEq(vault.strategies(address(lossyStrategy3)).strategyTotalLoss, 0);
        assertEq(vault.strategies(address(lossyStrategy3)).strategyTotalDebt, 25 * _1_USDC);

        assertLt(vault.debtRatio(), vaultPreviousDebtRatio - (expectedRatioChange + expectedRatioChange2));
        assertEq(vault.totalDebt(), 35 * _1_USDC);

        assertEq(vault.totalIdle(), 0);
    }

    function testMaxApyVault__WithdrawNegatives() public {
        ReentrantERC777AttackerWithdraw reentrantAttacker = new ReentrantERC777AttackerWithdraw();

        MockERC777 token = new MockERC777("Test", "TST", new address[](0), address(reentrantAttacker));

        MaxApyVault maxApyVault =
            new MaxApyVault(address(this), address(token), "MaxApyERC777Vault", "max777", TREASURY);

        IMaxApyVault vaultReentrant = IMaxApyVault(address(maxApyVault));

        reentrantAttacker.setVault(vaultReentrant);

        vm.startPrank(address(reentrantAttacker));
        token.approve(address(vaultReentrant), type(uint256).max);

        vm.startPrank(users.alice);

        vault.deposit(10 * _1_USDC, users.alice);

        token.mint(users.alice, 1 * _1_USDC);
        token.approve(address(vaultReentrant), type(uint256).max);
        vm.expectRevert(abi.encodeWithSignature("TransferFromFailed()"));
        vaultReentrant.deposit(1 * _1_USDC, users.alice);

        MockLossyUSDCStrategy lossyStrategy =
            new MockLossyUSDCStrategy(address(vault), USDC_MAINNET, makeAddr("strategist"));
        MockLossyUSDCStrategy lossyStrategy2 =
            new MockLossyUSDCStrategy(address(vault), USDC_MAINNET, makeAddr("strategist"));
        MockLossyUSDCStrategy lossyStrategy3 =
            new MockLossyUSDCStrategy(address(vault), USDC_MAINNET, makeAddr("strategist"));

        deal({ token: USDC_MAINNET, to: address(lossyStrategy), give: 10 * _1_USDC });
        deal({ token: USDC_MAINNET, to: address(lossyStrategy2), give: 10 * _1_USDC });
        deal({ token: USDC_MAINNET, to: address(lossyStrategy3), give: 10 * _1_USDC });

        vault.addStrategy(address(lossyStrategy), 1000, type(uint72).max, 0, 1000);

        lossyStrategy.mockReport(0, 0, 0, TREASURY);

        StrategyData memory lossyStrategyData = vault.strategies(address(lossyStrategy));

        assertEq(lossyStrategyData.strategyTotalLoss, 0);

        assertEq(lossyStrategyData.strategyTotalDebt, 1 * _1_USDC);

        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 9 * _1_USDC);

        vm.expectRevert(abi.encodeWithSignature("WithdrawMoreThanMax()"));
        vaultReentrant.withdraw(10 * _1_USDC, users.alice, users.alice);

        vm.expectRevert(abi.encodeWithSignature("InvalidZeroAmount()"));
        vault.withdraw(0, users.alice, users.alice);
    }

    function testMaxApyVault__WithdrawPositives() public {
        uint256 snapshotId = vm.snapshot();
        {
            _deposit(users.alice, vault, 10 * _1_USDC);

            uint256 withdrawn = _withdraw(users.alice, vault, vault.maxWithdraw(users.alice));
            assertApproxEq(withdrawn, 10 * _1_USDC, 1e5);
        }
        vm.revertTo(snapshotId);

        _deposit(users.alice, vault, 500 * _1_USDC);

        uint256 aliceBalanceBefore = IERC20(USDC_MAINNET).balanceOf(address(users.alice));

        uint256 valueWithdrawn = _withdraw(users.alice, vault, 10 * _1_USDC);

        valueWithdrawn += _withdraw(users.alice, vault, 400 * _1_USDC);

        valueWithdrawn += _withdraw(users.alice, vault, vault.maxWithdraw(users.alice));

        assertApproxEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 0, 5 * _1_USDC);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(users.alice)), aliceBalanceBefore + valueWithdrawn);

        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();

        _deposit(users.alice, vault, 20 * _1_USDC);

        vm.startPrank(users.alice);
        MockLossyUSDCStrategy lossyStrategy =
            new MockLossyUSDCStrategy(address(vault), USDC_MAINNET, makeAddr("strategist"));

        vault.addStrategy(address(lossyStrategy), 5000, type(uint72).max, 0, 1000);

        lossyStrategy.mockReport(0, 0, 0, TREASURY);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy)), 10 * _1_USDC);
        lossyStrategy.setEstimatedTotalAssets(10 * _1_USDC);

        aliceBalanceBefore = IERC20(USDC_MAINNET).balanceOf(users.alice);
        StrategyWithdrawalPreviousData memory previousStrategyData;

        previousStrategyData.balance = IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy));

        uint256 vaultPreviousDebtRatio = vault.debtRatio();

        previousStrategyData.debtRatio = vault.strategies(address(lossyStrategy)).strategyDebtRatio;
        previousStrategyData.totalLoss = vault.strategies(address(lossyStrategy)).strategyTotalLoss;
        previousStrategyData.totalDebt = vault.strategies(address(lossyStrategy)).strategyTotalDebt;

        uint256 expectedRatioChange = _computeExpectedRatioChange(vault, address(lossyStrategy), 1 * _1_USDC);

        // we can only withdraw 19 USDC since the lossy strategy lost 1 USDC
        valueWithdrawn = _withdraw(users.alice, vault, 18 * _1_USDC);

        assertEq(valueWithdrawn, 18 * _1_USDC);
        assertEq(IERC20(USDC_MAINNET).balanceOf(users.alice), aliceBalanceBefore + 18 * _1_USDC);
        assertApproxEq(vault.balanceOf(users.alice), 0, 2e12);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy)), previousStrategyData.balance - 8 * _1_USDC);
        assertApproxEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 0, 2 * _1_USDC);

        assertEq(
            vault.strategies(address(lossyStrategy)).strategyDebtRatio,
            previousStrategyData.debtRatio - expectedRatioChange
        );
        assertEq(vault.debtRatio(), vaultPreviousDebtRatio - expectedRatioChange);
        assertEq(
            vault.strategies(address(lossyStrategy)).strategyTotalLoss, previousStrategyData.totalLoss + 1 * _1_USDC
        );
        assertEq(
            vault.strategies(address(lossyStrategy)).strategyTotalDebt, previousStrategyData.totalDebt - 9 * _1_USDC
        );
        assertEq(vault.totalDebt(), _1_USDC);
        assertEq(vault.totalIdle(), 0);

        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();

        _deposit(users.alice, vault, 50 * _1_USDC);

        vm.startPrank(users.alice);

        lossyStrategy = new MockLossyUSDCStrategy(address(vault), USDC_MAINNET, makeAddr("strategist"));

        MockLossyUSDCStrategy lossyStrategyFunded =
            new MockLossyUSDCStrategy(address(vault), USDC_MAINNET, makeAddr("strategist"));

        vault.addStrategy(address(lossyStrategy), 0, type(uint72).max, 0, 1000);

        vault.addStrategy(address(lossyStrategyFunded), 5000, type(uint72).max, 0, 1000);

        lossyStrategyFunded.mockReport(0, 0, 0, TREASURY);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(lossyStrategyFunded)), 25 * _1_USDC);
        lossyStrategyFunded.setEstimatedTotalAssets(25 * _1_USDC);

        aliceBalanceBefore = IERC20(USDC_MAINNET).balanceOf(users.alice);

        vaultPreviousDebtRatio = vault.debtRatio();

        previousStrategyData.balance = IERC20(USDC_MAINNET).balanceOf(address(lossyStrategyFunded));
        previousStrategyData.debtRatio = vault.strategies(address(lossyStrategyFunded)).strategyDebtRatio;
        previousStrategyData.totalLoss = vault.strategies(address(lossyStrategyFunded)).strategyTotalLoss;
        previousStrategyData.totalDebt = vault.strategies(address(lossyStrategyFunded)).strategyTotalDebt;
        expectedRatioChange = _computeExpectedRatioChange(vault, address(lossyStrategyFunded), 1 * _1_USDC);

        valueWithdrawn = _withdraw(users.alice, vault, 49 * _1_USDC - _1_USDC);

        assertEq(valueWithdrawn, 48 * _1_USDC);
        assertEq(IERC20(USDC_MAINNET).balanceOf(users.alice), aliceBalanceBefore + 48 * _1_USDC);
        assertEq(vault.balanceOf(users.alice), _1_USDC * 1e6);
        assertEq(
            IERC20(USDC_MAINNET).balanceOf(address(lossyStrategyFunded)), previousStrategyData.balance - 23 * _1_USDC
        );
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 0);

        assertEq(
            vault.strategies(address(lossyStrategyFunded)).strategyDebtRatio,
            previousStrategyData.debtRatio - expectedRatioChange
        );
        assertEq(vault.debtRatio(), vaultPreviousDebtRatio - expectedRatioChange);
        assertEq(
            vault.strategies(address(lossyStrategyFunded)).strategyTotalLoss,
            previousStrategyData.totalLoss + 1 * _1_USDC
        );
        /*  assertEq(
            vault.strategies(address(lossyStrategyFunded)).strategyTotalDebt,
            previousStrategyData.totalDebt - 26 * _1_USDC, "here"
        ); */
        assertEq(vault.totalDebt(), _1_USDC);
        assertEq(vault.totalIdle(), 0);

        vm.revertTo(snapshotId);
        snapshotId = vm.snapshot();

        _deposit(users.alice, vault, 100 * _1_USDC);

        vm.startPrank(users.alice);

        lossyStrategy = new MockLossyUSDCStrategy(address(vault), USDC_MAINNET, makeAddr("strategist"));
        MockLossyUSDCStrategy lossyStrategy2 =
            new MockLossyUSDCStrategy(address(vault), USDC_MAINNET, makeAddr("strategist"));
        MockLossyUSDCStrategy lossyStrategy3 =
            new MockLossyUSDCStrategy(address(vault), USDC_MAINNET, makeAddr("strategist"));

        vault.addStrategy(address(lossyStrategy), 5000, type(uint72).max, 0, 1000);

        vault.addStrategy(address(lossyStrategy2), 2500, type(uint72).max, 0, 1000);

        vault.addStrategy(address(lossyStrategy3), 2500, type(uint72).max, 0, 1000);

        lossyStrategy.mockReport(0, 0, 0, TREASURY);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy)), 50 * _1_USDC);
        lossyStrategy2.mockReport(0, 0, 0, TREASURY);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy2)), 25 * _1_USDC);
        lossyStrategy3.mockReport(0, 0, 0, TREASURY);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy3)), 25 * _1_USDC);

        lossyStrategy.setEstimatedTotalAssets(50 * _1_USDC);
        lossyStrategy2.setEstimatedTotalAssets(25 * _1_USDC);
        lossyStrategy3.setEstimatedTotalAssets(25 * _1_USDC);

        aliceBalanceBefore = IERC20(USDC_MAINNET).balanceOf(users.alice);

        vaultPreviousDebtRatio = vault.debtRatio();

        previousStrategyData.balance = IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy));
        previousStrategyData.debtRatio = vault.strategies(address(lossyStrategy)).strategyDebtRatio;
        previousStrategyData.totalLoss = vault.strategies(address(lossyStrategy)).strategyTotalLoss;
        previousStrategyData.totalDebt = vault.strategies(address(lossyStrategy)).strategyTotalDebt;

        StrategyWithdrawalPreviousData memory previousStrategy2Data;

        previousStrategy2Data.balance = IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy2));
        previousStrategy2Data.debtRatio = vault.strategies(address(lossyStrategy2)).strategyDebtRatio;
        previousStrategy2Data.totalLoss = vault.strategies(address(lossyStrategy2)).strategyTotalLoss;
        previousStrategy2Data.totalDebt = vault.strategies(address(lossyStrategy2)).strategyTotalDebt;

        StrategyWithdrawalPreviousData memory previousStrategy3Data;

        previousStrategy3Data.balance = IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy3));
        previousStrategy3Data.debtRatio = vault.strategies(address(lossyStrategy3)).strategyDebtRatio;
        previousStrategy3Data.totalLoss = vault.strategies(address(lossyStrategy3)).strategyTotalLoss;
        previousStrategy3Data.totalDebt = vault.strategies(address(lossyStrategy3)).strategyTotalDebt;

        expectedRatioChange = _computeExpectedRatioChange(vault, address(lossyStrategy), 1 * _1_USDC);

        uint256 expectedRatioChange2 = _computeExpectedRatioChange(vault, address(lossyStrategy2), 1 * _1_USDC);

        valueWithdrawn = _withdraw(
            users.alice,
            vault,
            65 * _1_USDC - 2 * _1_USDC // 2 USDC loss expected due to withdrawal
        );

        {
            assertEq(valueWithdrawn, 63 * _1_USDC);
            assertEq(IERC20(USDC_MAINNET).balanceOf(users.alice), aliceBalanceBefore + 63 * _1_USDC);
            assertEq(vault.balanceOf(users.alice), 35 * _1_USDC * 10 ** 6);
            assertEq(
                IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy)), previousStrategyData.balance - 49 * _1_USDC
            );

            assertEq(
                IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy2)), previousStrategy2Data.balance - 14 * _1_USDC
            );

            assertEq(IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy3)), previousStrategy3Data.balance);

            assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), 0);
        }

        assertEq(
            vault.strategies(address(lossyStrategy)).strategyDebtRatio,
            previousStrategyData.debtRatio - expectedRatioChange
        );

        assertEq(
            vault.strategies(address(lossyStrategy)).strategyTotalLoss, previousStrategyData.totalLoss + 1 * _1_USDC
        );
        assertEq(
            vault.strategies(address(lossyStrategy)).strategyTotalDebt, previousStrategyData.totalDebt - 50 * _1_USDC
        );

        assertLt(
            vault.strategies(address(lossyStrategy2)).strategyDebtRatio,
            previousStrategy2Data.debtRatio - expectedRatioChange2
        );

        assertEq(
            vault.strategies(address(lossyStrategy2)).strategyTotalLoss, previousStrategy2Data.totalLoss + 1 * _1_USDC
        );
        assertEq(
            vault.strategies(address(lossyStrategy2)).strategyTotalDebt, previousStrategy2Data.totalDebt - 15 * _1_USDC
        );

        assertEq(vault.strategies(address(lossyStrategy3)).strategyDebtRatio, previousStrategy3Data.debtRatio);

        assertEq(vault.strategies(address(lossyStrategy3)).strategyTotalLoss, 0);
        assertEq(vault.strategies(address(lossyStrategy3)).strategyTotalDebt, 25 * _1_USDC);

        assertLt(vault.debtRatio(), vaultPreviousDebtRatio - (expectedRatioChange + expectedRatioChange2));
        assertEq(vault.totalDebt(), 35 * _1_USDC);

        assertEq(vault.totalIdle(), 0);
    }

    function testMaxApyVault__ReportNegatives() public {
        vault.grantRoles(users.alice, vault.STRATEGY_ROLE());

        MockLossyUSDCStrategy lossyStrategy =
            new MockLossyUSDCStrategy(address(vault), USDC_MAINNET, makeAddr("strategist"));

        vault.addStrategy(address(lossyStrategy), 4000, 0, 0, 0);

        lossyStrategy.mockReport(0, 0, 0, TREASURY);

        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vault.report(0, 0, 0, TREASURY);

        vm.stopPrank();

        vm.startPrank(address(lossyStrategy));

        vm.expectRevert(abi.encodeWithSignature("InvalidReportedGainAndDebtPayment()"));
        vault.report(0, 0, 1, TREASURY);

        deal({ token: USDC_MAINNET, to: address(lossyStrategy), give: 1 * _1_USDC });

        vm.warp(block.timestamp + 1);
        vault.report(1, 0, 0, TREASURY);
        vm.expectRevert(abi.encodeWithSignature("FeesAlreadyAssesed()"));
        vault.report(1, 0, 0, TREASURY);
    }

    function testMaxApyVault__ReportPositives() public {
        MockLossyUSDCStrategy lossyStrategy =
            new MockLossyUSDCStrategy(address(vault), USDC_MAINNET, makeAddr("strategist"));

        vault.addStrategy(address(lossyStrategy), 4000, type(uint96).max, 0, 0);

        _deposit(users.alice, vault, 100 * _1_USDC);

        vm.startPrank(address(lossyStrategy));

        vm.expectEmit();
        emit StrategyReported(address(lossyStrategy), 0, 0, 0, 0, 0, uint128(40 * _1_USDC), uint128(40 * _1_USDC), 4000);

        uint256 debt = vault.report(0, 0, 0, TREASURY);

        StrategyData memory strategyData = vault.strategies(address(lossyStrategy));

        // `strategyTotalLoss`, vault `totalDebt` were modified
        assertEq(strategyData.strategyDebtRatio, 4000);
        assertEq(vault.debtRatio(), 4000);
        assertEq(strategyData.strategyTotalDebt, 40 * _1_USDC);
        assertEq(strategyData.strategyTotalLoss, 0);
        assertEq(vault.totalDebt(), 40 * _1_USDC);

        assertEq(IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy)), 40 * _1_USDC);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(TREASURY)), 0 * _1_USDC);

        assertEq(vault.totalIdle(), 60 * _1_USDC);

        assertEq(strategyData.strategyLastReport, block.timestamp);
        assertEq(vault.lastReport(), block.timestamp);
        assertEq(debt, 0);

        uint256 snapshotId = vm.snapshot();

        StrategyData memory previousStrategyData = vault.strategies(address(lossyStrategy));
        uint256 previousVaultDebtRatio = vault.debtRatio();
        uint256 previousVaultTotalDebt = vault.totalDebt();
        uint256 previousVaultBalance = IERC20(USDC_MAINNET).balanceOf(address(vault));
        uint256 previousStrategyBalance = IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy));

        vm.recordLogs();

        debt = vault.report(0, uint128(1 * _1_USDC), 0, TREASURY);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        strategyData = vault.strategies(address(lossyStrategy));
        uint256 expectedRatioChange = _computeExpectedRatioChange(vault, address(lossyStrategy), 1 * _1_USDC);
        assertEq(strategyData.strategyDebtRatio, previousStrategyData.strategyDebtRatio - expectedRatioChange);
        assertEq(vault.debtRatio(), previousVaultDebtRatio - expectedRatioChange);
        assertEq(strategyData.strategyTotalLoss, previousStrategyData.strategyTotalLoss + 1 * _1_USDC);
        assertEq(strategyData.strategyTotalDebt, previousStrategyData.strategyTotalDebt - 1 * _1_USDC);
        assertEq(vault.totalDebt(), previousVaultTotalDebt - 1 * _1_USDC);
        assertGt(debt, 0);
        //assertEq(entries[0].topics[2], 0);
        assertEq(previousVaultBalance, IERC20(USDC_MAINNET).balanceOf(address(vault)));
        assertEq(previousStrategyBalance, IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy)));
        assertEq(block.timestamp, strategyData.strategyLastReport);
        assertEq(block.timestamp, vault.lastReport());

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();

        vm.startPrank(users.alice);

        vault.updateStrategyData(address(lossyStrategy), 4000, type(uint96).max, 0, 150);
        vm.stopPrank();
        vm.startPrank(address(lossyStrategy));

        vm.warp(block.timestamp + 100);

        deal({ token: USDC_MAINNET, to: address(lossyStrategy), give: 100 * _1_USDC });
        lossyStrategy.setEstimatedTotalAssets((40 + 100) * _1_USDC);

        previousVaultBalance = IERC20(USDC_MAINNET).balanceOf(address(vault));
        previousStrategyBalance = IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy));

        uint256 expectedShares = _calculateExpectedShares(2 * _1_USDC + 15 * _1_USDC / 10 + 10 * _1_USDC);
        uint256 expectedStrategistFees = _calculateExpectedStrategistFees(
            15 * _1_USDC / 10, expectedShares, 2 * _1_USDC + 15 * _1_USDC / 10 + 10 * _1_USDC
        );

        debt = vault.report(uint128(100 * _1_USDC), 0, 0, TREASURY);

        //assertEq(2 * _1_USDC, uint256(entries[3].topics[1]));
        //assertEq(1.5 * _1_USDC, uint256(entries[3].topics[3]));
        //assertEq(10 * _1_USDC, uint256(entries[3].topics[2]));
        assertEq(vault.balanceOf(lossyStrategy.strategist()), expectedStrategistFees);
        assertEq(vault.balanceOf(vault.treasury()), expectedShares - expectedStrategistFees);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), previousVaultBalance);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy)), previousStrategyBalance);
        assertEq(vault.totalIdle(), 60 * _1_USDC);
        vm.revertTo(snapshotId);

        vm.startPrank(users.alice);

        vault.setEmergencyShutdown(true);

        vm.startPrank(address(lossyStrategy));
        lossyStrategy.setEstimatedTotalAssets(40 * _1_USDC);

        vm.recordLogs();

        previousVaultBalance = IERC20(USDC_MAINNET).balanceOf(address(vault));
        previousStrategyBalance = IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy));
        debt = vault.report(0, 0, uint128(40 * _1_USDC), TREASURY);

        entries = vm.getRecordedLogs();

        //assertEq(entries[1].topics[3], 0);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(lossyStrategy)), previousStrategyBalance - 40 * _1_USDC);
        assertEq(IERC20(USDC_MAINNET).balanceOf(address(vault)), previousVaultBalance + 40 * _1_USDC);
        assertEq(vault.totalDeposits(), 100 * _1_USDC);
        assertEq(vault.totalAssets(), 140 * _1_USDC);
    }

    function testMaxApyVault__setAutopilotEnabledNegatives() public {
        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vault.setAutopilotEnabled(true);
    }

    function testMaxApyVault__setAutopilotEnabledPositives() public {
        assertFalse(vault.autoPilotEnabled());
        vm.expectEmit();
        emit AutopilotEnabled(true);
        vault.setAutopilotEnabled(true);
        assertTrue(vault.autoPilotEnabled());
        vm.expectEmit();
        emit AutopilotEnabled(false);
        vault.setAutopilotEnabled(false);
        assertFalse(vault.autoPilotEnabled());
    }
}
