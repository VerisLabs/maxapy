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
import { IStrategyWrapper } from "../../interfaces/IStrategyWrapper.sol";

import { MaxApyVault } from "src/MaxApyVault.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { ConvexdETHFrxETHStrategyEvents } from "../../helpers/ConvexdETHFrxETHStrategyEvents.sol";
import "src/helpers/AddressBook.sol";
import { BeefyMaiUSDCeStrategyWrapper } from "../../mock/BeefyMaiUSDCeStrategyWrapper.sol";
import { _1_USDCE } from "test/helpers/Tokens.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

contract BeefyMaiUSDCeStrategyTest is BaseTest, ConvexdETHFrxETHStrategyEvents {
    using SafeTransferLib for address;

    address public TREASURY;
    IStrategyWrapper public strategy;
    BeefyMaiUSDCeStrategyWrapper public implementation;
    MaxApyVault public vaultDeployment;
    IMaxApyVault public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;

    function setUp() public {
        super._setUp("POLYGON");
        vm.rollFork(61_767_099);

        TREASURY = makeAddr("treasury");

        vaultDeployment = new MaxApyVault(users.alice, USDCE_POLYGON, "MaxApyUSDCEVault", "maxUSDCE", TREASURY);

        vault = IMaxApyVault(address(vaultDeployment));

        proxyAdmin = new ProxyAdmin(users.alice);
        implementation = new BeefyMaiUSDCeStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy MAI<>USDCe Strategy")),
                users.alice,
                CURVE_MAI_USDCE_POOL_POLYGON,
                BEEFY_MAI_USDCE_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));

        strategy = IStrategyWrapper(address(_proxy));
        USDCE_POLYGON.safeApprove(address(vault), type(uint256).max);

        // vm.label(USDT_POLYGON, "USDT_POLYGON");         // todo
        // vm.label(USDCE_POLYGON, "USDCE_POLYGON");
        // vm.label(CRV_POLYGON, "CRV_POLYGON");
        // vm.label(CRV_USD_POLYGON, "CRV-USD_POLYGON");
    }

    /*==================INITIALIZATION TESTS==================*/

    function testBeefyMaiUSDCe__Initialization() public {
        MaxApyVault _vault = new MaxApyVault(users.alice, USDCE_POLYGON, "MaxApyUSDCEVault", "maxUSDCE", TREASURY);

        ProxyAdmin _proxyAdmin = new ProxyAdmin(users.alice);
        BeefyMaiUSDCeStrategyWrapper _implementation = new BeefyMaiUSDCeStrategyWrapper();

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;

        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(_implementation),
            address(_proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address)",
                address(_vault),
                keepers,
                bytes32(abi.encode("MaxApy MAI<>USDCe Strategy")),
                users.alice,
                CURVE_MAI_USDCE_POOL_POLYGON,
                BEEFY_MAI_USDCE_POLYGON
            )
        );

        IStrategyWrapper _strategy = IStrategyWrapper(address(_proxy));
        assertEq(_strategy.vault(), address(_vault));

        console2.log("VAULT_ROLE", _strategy.VAULT_ROLE());
        assertEq(_strategy.hasAnyRole(address(_vault), _strategy.VAULT_ROLE()), true);
        assertEq(_strategy.underlyingAsset(), USDCE_POLYGON);
        assertEq(IERC20(USDCE_POLYGON).allowance(address(_strategy), address(_vault)), type(uint256).max);
        assertEq(_strategy.hasAnyRole(users.keeper, _strategy.KEEPER_ROLE()), true);
        assertEq(_strategy.hasAnyRole(users.alice, _strategy.ADMIN_ROLE()), true);
        console2.log("Admin role", _strategy.ADMIN_ROLE());
        assertEq(_strategy.owner(), users.alice);
        assertEq(_strategy.strategyName(), bytes32(abi.encode("MaxApy MAI<>USDCe Strategy")));

        console2.log("CURVE LP POOL ", CURVE_MAI_USDCE_POOL_POLYGON);
        assertEq(_strategy.curveLpPool(), CURVE_MAI_USDCE_POOL_POLYGON, "hereee");
        assertEq(IERC20(USDCE_POLYGON).allowance(address(_strategy), CURVE_MAI_USDCE_POOL_POLYGON), type(uint256).max);

        assertEq(_proxyAdmin.owner(), users.alice);
        vm.startPrank(address(_proxyAdmin));
        vm.stopPrank();

        vm.startPrank(users.alice);
    }

    /*==================STRATEGY CONFIGURATION TESTS==================*/

    function testBeefyMaiUSDCE__SetEmergencyExit() public {
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

    function testBeefyMaiUSDCE__SetMinSingleTrade() public {
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

    // function testBeefyMaiUSDCE__IsActive() public {
    //     vault.addStrategy(address(strategy), 10_000, 0, 0, 0);
    //     assertEq(strategy.isActive(), false);

    //     deal(USDCE_POLYGON, address(strategy), 1 * _1_USDCE);
    //     assertEq(strategy.isActive(), false);

    //     vm.startPrank(users.keeper);
    //     strategy.harvest(0, 0, address(0), block.timestamp);
    //     assertEq(strategy.isActive(), true);
    //     vm.stopPrank();

    //     // strategy.divest(IERC20(CURVE_MAI_USDCE_POOL_POLYGON).balanceOf(address(strategy)));
    //     // vm.startPrank(address(strategy));
    //     // IERC20(USDCE_POLYGON).transfer(makeAddr("random"), IERC20(USDCE_POLYGON).balanceOf(address(strategy)));
    //     // assertEq(strategy.isActive(), false);

    //     // deal(USDCE_POLYGON, address(strategy), 1 * _1_USDCE);
    //     // vm.startPrank(users.keeper);
    //     // strategy.harvest(0, 0, address(0), block.timestamp);
    //     // assertEq(strategy.isActive(), true);
    // }

    function testBeefyMaiUSDCE__SetStrategist() public {
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
    // function testBeefyMaiUSDCE__InvestmentSlippage() public {
    //     vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

    //     vault.deposit(100 * _1_USDCE, users.alice);

    //     vm.startPrank(users.keeper);

    //     // Expect revert if output amount is gt amount obtained
    //     vm.expectRevert(abi.encodeWithSignature("MinOutputAmountNotReached()"));
    //     strategy.harvest(0, type(uint256).max, address(0), block.timestamp);
    // }

    function testBeefyMaiUSDCE__PrepareReturn() public {
        uint256 snapshotId = vm.snapshot();

        vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        vault.deposit(100 * _1_USDCE, users.alice);

        strategy.mockReport(0, 0, 0, TREASURY);

        (uint256 unrealizedProfit, uint256 loss, uint256 debtPayment) = strategy.prepareReturn(1 * _1_USDCE, 0);
        console2.log(" in test prepare return", unrealizedProfit, loss, debtPayment);
        assertEq(loss, 0);
        assertEq(debtPayment, 1 * _1_USDCE);

        vm.revertTo(snapshotId);

        snapshotId = vm.snapshot();
        deal({ token: USDCE_POLYGON, to: address(strategy), give: 60 * _1_USDCE });

        // strategy.adjustPosition();

        // vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        // vault.deposit(100 * _1_USDCE, users.alice);

        // (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        // console2.log("unrealizedProfit, loss, debtPayment = ", unrealizedProfit, loss, debtPayment);

        // assertApproxEq(unrealizedProfit, 60 * _1_USDCE, _1_USDCE / 10);
        // assertEq(loss, 0);
        // assertEq(debtPayment, 0);

        // vm.revertTo(snapshotId);

        // snapshotId = vm.snapshot();

        // vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        // vault.deposit(100 * _1_USDCE, users.alice);

        // strategy.mockReport(0, 0, 0, TREASURY);

        // strategy.triggerLoss(10 * _1_USDCE);

        // (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        // assertEq(unrealizedProfit, 0);
        // assertEq(loss, 10 * _1_USDCE);
        // assertEq(debtPayment, 0);

        // vm.revertTo(snapshotId);

        // snapshotId = vm.snapshot();

        // deal({ token: USDCE_POLYGON, to: address(strategy), give: 80 * _1_USDCE });

        // strategy.adjustPosition();

        // vault.addStrategy(address(strategy), 4000, type(uint72).max, 0, 0);

        // vault.deposit(100 * _1_USDCE, users.alice);

        // strategy.mockReport(0, 0, 0, TREASURY);

        // (unrealizedProfit, loss, debtPayment) = strategy.prepareReturn(0, 0);

        // assertEq(loss, 0);
        // assertEq(debtPayment, 0);
    }
    
}
