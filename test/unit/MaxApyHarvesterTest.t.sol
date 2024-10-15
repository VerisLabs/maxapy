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
        harvester.batchHarvests(harvests);
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
        harvester.batchHarvests(harvests);
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
        harvester.batchHarvests(harvests);
        vm.stopPrank();
        uint128 strategyTotalDebt = vault.strategies(address(strategy2)).strategyTotalDebt;
        uint128 strategyDebtRatio = vault.strategies(address(strategy2)).strategyDebtRatio;

        vm.startPrank(users.alice);
        vault.updateStrategyData(address(strategy2), 100, type(uint256).max, type(uint256).max, 200);
        vm.stopPrank();
        strategyTotalDebt = vault.strategies(address(strategy2)).strategyTotalDebt;
        strategyDebtRatio = vault.strategies(address(strategy2)).strategyDebtRatio;

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
        harvester.batchHarvests(harvests);
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
}
