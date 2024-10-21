// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { BaseTest, IERC20, Vm, console2 } from "../base/BaseTest.t.sol";
import { BaseVaultTest } from "../base/BaseVaultTest.t.sol";
import { MaxApyVault, StrategyData } from "src/MaxApyVault.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";

import { YearnWETHStrategyWrapper } from "../mock/YearnWETHStrategyWrapper.sol";
import { SommelierTurboStEthStrategyWrapper } from "../mock/SommelierTurboStEthStrategyWrapper.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import { IStrategyWrapper } from "../interfaces/IStrategyWrapper.sol";
import { IERC20Metadata } from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

import { MaxApyHarvester } from "src/periphery/MaxApyHarvester.sol";

import "src/helpers/AddressBook.sol";

contract MaxApyHarvesterTest is BaseVaultTest {
    MaxApyHarvester harvester;
    IStrategyWrapper strategy1;
    IStrategyWrapper strategy2;

    function setUp() public {
        setupVault("MAINNET", WETH_MAINNET);
        vm.rollFork(18_619_489);

        IERC20(WETH_MAINNET).approve(address(vault), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(users.bob);
        IERC20(WETH_MAINNET).approve(address(vault), type(uint256).max);

        vm.startPrank(users.eve);
        IERC20(WETH_MAINNET).approve(address(vault), type(uint256).max);

        vm.startPrank(users.alice);

        vault.grantRoles(users.alice, vault.EMERGENCY_ADMIN_ROLE());

        address[] memory keepers = new address[](2);
        keepers[0] = users.keeper;
        keepers[1] = users.allocator;

        harvester = new MaxApyHarvester(users.alice, keepers);

        ProxyAdmin proxyAdmin = new ProxyAdmin(users.alice);
        YearnWETHStrategyWrapper implementation1 = new YearnWETHStrategyWrapper();

        keepers[0] = address(harvester);

        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation1),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Strategy")),
                users.alice,
                YEARN_WETH_YVAULT_MAINNET
            )
        );

        strategy1 = IStrategyWrapper(address(_proxy));

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
                SOMMELIER_TURBO_STETH_CELLAR_MAINNET
            )
        );

        strategy2 = IStrategyWrapper(address(_proxy));

        vault.addStrategy(address(strategy1), 4000, type(uint256).max, 0, 200);
        vault.addStrategy(address(strategy2), 4000, type(uint256).max, 0, 200);
        vault.grantRoles(address(harvester), vault.ADMIN_ROLE());

        vm.label(address(WETH_MAINNET), "WETH");
    }

    function testMaxApyHarvester__HarvestBatch_Positives() public {
        vault.deposit(10 ether, users.alice);
        MaxApyHarvester.HarvestData[] memory harvests = new MaxApyHarvester.HarvestData[](2);
        harvests[0] = MaxApyHarvester.HarvestData({
            strategyAddress: address(strategy1),
            minExpectedBalance: 0,
            minOutputAfterInvestment: 0,
            deadline: block.timestamp
        });
        harvests[1] = MaxApyHarvester.HarvestData({
            strategyAddress: address(strategy2),
            minExpectedBalance: 0,
            minOutputAfterInvestment: 0,
            deadline: block.timestamp
        });
        vm.startPrank(users.keeper);
        harvester.batchHarvest(vault, harvests);
        vm.stopPrank();
    }

    function testMaxApyHarvester__AllocateBatch_Positives() public {
        testMaxApyHarvester__HarvestBatch_Positives();
        MaxApyHarvester.AllocationData[] memory allocations = new MaxApyHarvester.AllocationData[](2);
        allocations[0] = MaxApyHarvester.AllocationData({
            strategyAddress: address(strategy1),
            debtRatio: 1000,
            maxDebtPerHarvest: type(uint256).max,
            minDebtPerHarvest: 0,
            performanceFee: 200
        });
        allocations[1] = MaxApyHarvester.AllocationData({
            strategyAddress: address(strategy2),
            debtRatio: 8000,
            maxDebtPerHarvest: type(uint256).max,
            minDebtPerHarvest: 0,
            performanceFee: 200
        });
        vm.startPrank(users.allocator);
        harvester.batchAllocate(vault, allocations);
        vm.stopPrank();
    }

    function testMaxApyHarvester__HarvestBatch_Negatives() public {
        vault.deposit(100 ether, users.alice);
        MaxApyHarvester.HarvestData[] memory harvests = new MaxApyHarvester.HarvestData[](2);
        harvests[0] = MaxApyHarvester.HarvestData({
            strategyAddress: address(strategy1),
            minExpectedBalance: 0,
            minOutputAfterInvestment: type(uint256).max,
            deadline: block.timestamp
        });
        harvests[1] = MaxApyHarvester.HarvestData({
            strategyAddress: address(strategy2),
            minExpectedBalance: 0,
            minOutputAfterInvestment: 0,
            deadline: block.timestamp
        });

        vm.startPrank(users.keeper);
        vm.expectRevert(abi.encodeWithSignature("MinOutputAmountNotReached()"));
        harvester.batchHarvest(vault, harvests);
        harvests[0] = MaxApyHarvester.HarvestData({
            strategyAddress: address(strategy1),
            minExpectedBalance: 0,
            minOutputAfterInvestment: 0,
            deadline: block.timestamp
        });
        harvests[1] = MaxApyHarvester.HarvestData({
            strategyAddress: address(strategy2),
            minExpectedBalance: 0,
            minOutputAfterInvestment: 0,
            deadline: block.timestamp
        });
        harvester.batchHarvest(vault, harvests);
        vm.stopPrank();
        uint128 strategyTotalDebt = vault.strategies(address(strategy2)).strategyTotalDebt;
        uint128 debtRatio = vault.strategies(address(strategy2)).strategyDebtRatio;

        vm.startPrank(users.alice);
        vault.updateStrategyData(address(strategy2), 100, type(uint256).max, type(uint256).max, 200);
        vm.stopPrank();
        strategyTotalDebt = vault.strategies(address(strategy2)).strategyTotalDebt;
        debtRatio = vault.strategies(address(strategy2)).strategyDebtRatio;

        vm.startPrank(users.keeper);
        harvests[0] = MaxApyHarvester.HarvestData({
            strategyAddress: address(strategy1),
            minExpectedBalance: 0,
            minOutputAfterInvestment: 0,
            deadline: block.timestamp
        });
        harvests[1] = MaxApyHarvester.HarvestData({
            strategyAddress: address(strategy2),
            minExpectedBalance: type(uint256).max,
            minOutputAfterInvestment: 0,
            deadline: block.timestamp
        });
        vm.expectRevert(abi.encodeWithSignature("MinExpectedBalanceNotReached()"));
        harvester.batchHarvest(vault, harvests);
    }

    function testMaxApyHarvester__AllocateBatch_Negatives() public {
        testMaxApyHarvester__HarvestBatch_Positives();
        MaxApyHarvester.AllocationData[] memory allocations = new MaxApyHarvester.AllocationData[](2);
        allocations[0] = MaxApyHarvester.AllocationData({
            strategyAddress: address(strategy1),
            debtRatio: 8000,
            maxDebtPerHarvest: type(uint256).max,
            minDebtPerHarvest: 0,
            performanceFee: 200
        });
        allocations[1] = MaxApyHarvester.AllocationData({
            strategyAddress: address(strategy2),
            debtRatio: 1000,
            maxDebtPerHarvest: type(uint256).max,
            minDebtPerHarvest: 0,
            performanceFee: 200
        });
        vm.startPrank(users.allocator);
        vm.expectRevert(abi.encodeWithSignature("InvalidDebtRatio()"));
        harvester.batchAllocate(vault, allocations);
        vm.stopPrank();
    }

     function testAddStrategy_single() public {
        MaxApyHarvester.AllocationData[] memory allocations = new MaxApyHarvester.AllocationData[](1);
        allocations[0] = MaxApyHarvester.AllocationData({
            strategyAddress: address(0),
            debtRatio: 2000,
            maxDebtPerHarvest: type(uint72).max,
            minDebtPerHarvest: 0,
            performanceFee: 200
        });

        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        harvester.batchAllocate(vault, allocations);
        vm.stopPrank();

        vm.startPrank(users.keeper);
        vm.expectRevert(abi.encodeWithSignature("InvalidZeroAddress()"));
        harvester.batchAllocate(vault, allocations);

        allocations[0].strategyAddress = address(strategy1);
        harvester.batchAllocate(vault, allocations);
        StrategyData memory strategyData = vault.strategies(address(strategy1));

        assertEq(
            allocations[0].debtRatio,
            strategyData.strategyDebtRatio
        );
        assertEq(
            allocations[0].maxDebtPerHarvest,
            strategyData.strategyMaxDebtPerHarvest
        );
        assertEq(
            allocations[0].minDebtPerHarvest,
            strategyData.strategyMinDebtPerHarvest
        );
        assertEq(
            allocations[0].performanceFee,
            strategyData.strategyPerformanceFee
        );
        vm.stopPrank();
    }

    function testAddStrategy_multiple() public {
        MaxApyHarvester.AllocationData[]
            memory allocation = new MaxApyHarvester.AllocationData[](2);
        allocation[0] = MaxApyHarvester.AllocationData({
            strategyAddress: address(0),
            debtRatio: 2000,
            maxDebtPerHarvest: type(uint72).max,
            minDebtPerHarvest: 0,
            performanceFee: 200
        });
         allocation[1] = MaxApyHarvester.AllocationData({
            strategyAddress: address(strategy2),
            debtRatio: 4000,
            maxDebtPerHarvest: type(uint72).max,
            minDebtPerHarvest: 0,
            performanceFee: 300
        });

        vm.startPrank(users.alice);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        harvester.batchAllocate(vault, allocation);
        vm.stopPrank();

        vm.startPrank(users.keeper);
        vm.expectRevert(abi.encodeWithSignature("InvalidZeroAddress()"));
        harvester.batchAllocate(vault, allocation);

        allocation[0].strategyAddress = address(strategy1);
        harvester.batchAllocate(vault, allocation);
        StrategyData memory strategyData = vault.strategies(address(strategy1));

        assertEq(
            allocation[0].debtRatio,
            strategyData.strategyDebtRatio
        );
        assertEq(
            allocation[0].maxDebtPerHarvest,
            strategyData.strategyMaxDebtPerHarvest
        );
        assertEq(
            allocation[0].minDebtPerHarvest,
            strategyData.strategyMinDebtPerHarvest
        );
        assertEq(
            allocation[0].performanceFee,
            strategyData.strategyPerformanceFee
        );

        strategyData = vault.strategies(address(strategy2));

        assertEq(
            allocation[1].debtRatio,
            strategyData.strategyDebtRatio
        );
        assertEq(
            allocation[1].maxDebtPerHarvest,
            strategyData.strategyMaxDebtPerHarvest
        );
        assertEq(
            allocation[1].minDebtPerHarvest,
            strategyData.strategyMinDebtPerHarvest
        );
        assertEq(
            allocation[1].performanceFee,
            strategyData.strategyPerformanceFee
        );
        vm.stopPrank();
    }

    function testRemoveStrategy_single() public {
        MaxApyHarvester.AllocationData[] memory allocation = new MaxApyHarvester.AllocationData[](1);
        allocation[0] = MaxApyHarvester.AllocationData({
            strategyAddress: address(strategy1),
            debtRatio: 2000,
            maxDebtPerHarvest: type(uint72).max,
            minDebtPerHarvest: 0,
            performanceFee: 200
        });

        vm.startPrank(users.keeper);
        harvester.batchAllocate(vault, allocation);
        StrategyData memory strategyData = vault.strategies(address(strategy1));

        assertEq(
            allocation[0].debtRatio,
            strategyData.strategyDebtRatio
        );
        assertEq(
            allocation[0].maxDebtPerHarvest,
            strategyData.strategyMaxDebtPerHarvest
        );
        assertEq(
            allocation[0].minDebtPerHarvest,
            strategyData.strategyMinDebtPerHarvest
        );
        assertEq(
            allocation[0].performanceFee,
            strategyData.strategyPerformanceFee
        );

        vm.stopPrank();
        MaxApyHarvester.HarvestData[]
            memory harvestData = new MaxApyHarvester.HarvestData[](1);
        harvestData[0] = MaxApyHarvester.HarvestData({
            strategyAddress: address(strategy1),
            minExpectedBalance: 0,
            minOutputAfterInvestment: 0,
            deadline: block.timestamp
        });

        vm.startPrank(users.bob);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        harvester.batchHarvest(vault, harvestData);
        vm.stopPrank();
       
        vm.startPrank(users.keeper);
        allocation = new MaxApyHarvester.AllocationData[](1);
        allocation[0] = MaxApyHarvester.AllocationData({
            strategyAddress: address(strategy1),
            debtRatio: 0,
            maxDebtPerHarvest: type(uint72).max,
            minDebtPerHarvest: 0,
            performanceFee: 200
        });
        harvester.batchAllocate(vault, allocation);
        harvester.batchHarvest(vault, harvestData);

        strategyData = vault.strategies(address(strategy1));
        assertEq(
            vault.hasAnyRole(address(strategy1), vault.STRATEGY_ROLE()),
            false
        );
        
        // it will fail on report modifier STRATEGY_ROLE
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        harvester.batchHarvest(vault, harvestData);
        
        vm.stopPrank();
    }

    function testRemoveStrategy_multiple() public {
        MaxApyHarvester.AllocationData[]
            memory allocations = new MaxApyHarvester.AllocationData[](2);
            allocations[0] = MaxApyHarvester.AllocationData({
            strategyAddress: address(strategy1),
            debtRatio: 2000,
            maxDebtPerHarvest: type(uint72).max,
            minDebtPerHarvest: 0,
            performanceFee: 200
        });
         allocations[1] = MaxApyHarvester.AllocationData({
            strategyAddress: address(strategy2),
            debtRatio: 4000,
            maxDebtPerHarvest: type(uint72).max,
            minDebtPerHarvest: 0,
            performanceFee: 300
        });

        vm.startPrank(users.keeper);
        harvester.batchAllocate(vault, allocations);

        MaxApyHarvester.HarvestData[]
            memory harvestData = new MaxApyHarvester.HarvestData[](2);
        harvestData[0] = MaxApyHarvester.HarvestData({
            strategyAddress: address(strategy1),
            minExpectedBalance: 0,
            minOutputAfterInvestment: 0,
            deadline: block.timestamp
        });
        harvestData[1] = MaxApyHarvester.HarvestData({
            strategyAddress: address(strategy2),
            minExpectedBalance: 0,
            minOutputAfterInvestment: 0,
            deadline: block.timestamp
        });

        assertEq(
            vault.hasAnyRole(address(strategy1), vault.STRATEGY_ROLE()),
            true
        );
        assertEq(
            vault.hasAnyRole(address(strategy2), vault.STRATEGY_ROLE()),
            true
        );

        harvester.batchHarvest(vault, harvestData);

        allocations = new MaxApyHarvester.AllocationData[](2);
            allocations[0] = MaxApyHarvester.AllocationData({
            strategyAddress: address(strategy1),
            debtRatio: 0,
            maxDebtPerHarvest: type(uint72).max,
            minDebtPerHarvest: 0,
            performanceFee: 200
        });
         allocations[1] = MaxApyHarvester.AllocationData({
            strategyAddress: address(strategy2),
            debtRatio: 0,
            maxDebtPerHarvest: type(uint72).max,
            minDebtPerHarvest: 0,
            performanceFee: 300
        });

        harvester.batchAllocate(vault, allocations);
        harvester.batchHarvest(vault, harvestData);
        
        assertEq(
            vault.hasAnyRole(address(strategy1), vault.STRATEGY_ROLE()),
            false
        );
        assertEq(
            vault.hasAnyRole(address(strategy2), vault.STRATEGY_ROLE()),
            false
        );

        vm.stopPrank();
    }
}
