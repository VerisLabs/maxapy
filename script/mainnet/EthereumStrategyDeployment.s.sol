// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

// helpers

import { console2 } from "../../test/base/BaseTest.t.sol";
import { StrategyEvents } from "../../test/helpers/StrategyEvents.sol";
import "forge-std/Script.sol";
import "src/helpers/AddressBook.sol";

// proxies

import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

// interfaces

import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";
import { IStrategy } from "src/interfaces/IStrategy.sol";
import { IWrappedToken } from "src/interfaces/IWrappedToken.sol";

//// Strategies

import { YearnAjnaDAIStakingStrategy } from "src/strategies/mainnet/USDC/yearn/YearnAjnaDAIStakingStrategy.sol";
import { YearnDAIStrategy } from "src/strategies/mainnet/USDC/yearn/YearnDAIStrategy.sol";
import { YearnUSDTStrategy } from "src/strategies/mainnet/USDC/yearn/YearnUSDTStrategy.sol";

//// Vault

import { MaxApyVault, OwnableRoles } from "src/MaxApyVault.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";

/// @notice this is a simple test deployment of a polygon USDCe vault in a local rpc
contract PolygonDeploymentScript is Script, OwnableRoles {
    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////
    // **********STRATS******************
    // USDCE
    IStrategy public strategy1;
    IStrategy public strategy2;
    IStrategy public strategy3;

    // **********ROLES*******************
    address[] keepers;

    // **********LOCAL VARIABLES*****************
    // use storage variables to avoid stack too deep

    // Proxies
    ITransparentUpgradeableProxy proxy;
    ProxyAdmin proxyAdmin;

    // Vault
    IMaxApyVault vault;

    // Actors
    address strategyAdmin;
    address strategyEmergencyAdmin;
    address treasury;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////

    function run() public {
        /////////////////////////////////////////////////////////////////////////
        ///                             ACTORS                                ///
        /////////////////////////////////////////////////////////////////////////
        // use another private key here, dont use a keeper account for deployment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        keepers.push(vm.envAddress("KEEPER1_ADDRESS"));
        keepers.push(vm.envAddress("KEEPER2_ADDRESS"));
        keepers.push(vm.envAddress("KEEPER3_ADDRESS"));

        strategyAdmin = vm.envAddress("STRATEGY_ADMIN_ADDRESS");
        strategyEmergencyAdmin = vm.envAddress("STRATEGY_EMERGENCY_ADMIN_ADDRESS");
        treasury = vm.envAddress("TREASURY_ADDRESS");
        bool isFork = vm.envBool("FORK");

        if (isFork) {
            revert("fork setup");
        }

        vm.startBroadcast(deployerPrivateKey);

        /////////////////////////////////////////////////////////////////////////
        ///                             VAULT                                 ///
        /////////////////////////////////////////////////////////////////////////
        vault = IMaxApyVault(0x349c996C4a53208b6EB09c103782D86a3F1BB57E);

        /////////////////////////////////////////////////////////////////////////
        ///                        STRATEGIES                                 ///
        /////////////////////////////////////////////////////////////////////////
        /// Deploy transparent upgradeable proxy admin
        proxyAdmin = new ProxyAdmin(strategyAdmin);

        //        YearnUSDTStrategy implementation1 = new YearnUSDTStrategy();
        //        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
        //            address(implementation1),
        //            address(proxyAdmin),
        //            abi.encodeWithSignature(
        //                "initialize(address,address[],bytes32,address,address)",
        //                address(vault),
        //                keepers,
        //                bytes32("MaxApy Yearn USDT<>USDC"),
        //                strategyAdmin,
        //                YEARN_USDT_YVAULT_MAINNET
        //            )
        //        );
        //        proxy = ITransparentUpgradeableProxy(address(_proxy));
        //        strategy1 = IStrategy(address(proxy));
        //        strategy1.grantRoles(strategyAdmin, strategy1.ADMIN_ROLE());
        //        strategy1.grantRoles(
        //            strategyEmergencyAdmin,
        //            strategy1.EMERGENCY_ADMIN_ROLE()
        //        );
        //
        //        YearnDAIStrategy implementation2 = new YearnDAIStrategy();
        //        _proxy = new TransparentUpgradeableProxy(
        //            address(implementation2),
        //            address(proxyAdmin),
        //            abi.encodeWithSignature(
        //                "initialize(address,address[],bytes32,address,address)",
        //                address(vault),
        //                keepers,
        //                bytes32("MaxApy Yearn DAI<>USDC"),
        //                strategyAdmin,
        //                YEARN_DAI_YVAULT_MAINNET
        //            )
        //        );
        //        proxy = ITransparentUpgradeableProxy(address(_proxy));
        //        strategy2 = IStrategy(address(proxy));
        //        strategy2.grantRoles(strategyAdmin, strategy2.ADMIN_ROLE());
        //        strategy2.grantRoles(
        //            strategyEmergencyAdmin,
        //            strategy2.EMERGENCY_ADMIN_ROLE()
        //        );

        YearnAjnaDAIStakingStrategy implementation3 = new YearnAjnaDAIStakingStrategy();
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation3),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32("MaxApy Yearn DAI Staking"),
                strategyAdmin,
                YEARN_AJNA_DAI_STAKING_YVAULT_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy3 = IStrategy(address(proxy));
        strategy3.grantRoles(strategyAdmin, strategy3.ADMIN_ROLE());
        strategy3.grantRoles(strategyEmergencyAdmin, strategy3.EMERGENCY_ADMIN_ROLE());

        console2.log("***************************DEPLOYMENT ADDRESSES**********************************");
        console2.log(" VAULT ");
        console2.log("[MAXAPY]Vault :", address(vault));

        console2.log(" STRATEGIES ");
        console2.log("YearnUSDTStrategy: ", address(strategy1));
        console2.log("YearnDAIStrategy: ", address(strategy2));
        console2.log("YearnAjnaDAIStakingStrategy: ", address(strategy3));
    }
}
