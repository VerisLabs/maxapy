// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

// helpers
import "forge-std/Script.sol";
import { console2 } from "../../test/base/BaseTest.t.sol";
import { StrategyEvents } from "../../test/helpers/StrategyEvents.sol";
import "src/helpers/AddressBook.sol";

// proxies
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";

// interfaces
import { IStrategy } from "src/interfaces/IStrategy.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";
import { IWrappedToken } from "src/interfaces/IWrappedToken.sol";

//// Strategies
import { BaseHopStrategy } from "src/strategies/base/BaseHopStrategy.sol";

//// Vault
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { MaxApyVault, OwnableRoles } from "src/MaxApyVault.sol";

/// @notice this is a simple test deployment of a polygon USDCe vault in a local rpc
contract PolygonDeploymentScript is Script, OwnableRoles {
    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////
    // **********STRATS******************
    // USDCE
    IStrategy public strategy1; 
    
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
        vault = IMaxApyVault(0xA02aA8774E8C95F5105E33c2f73bdC87ea45BD29);

        /////////////////////////////////////////////////////////////////////////
        ///                        STRATEGIES                                 ///
        /////////////////////////////////////////////////////////////////////////
        /// Deploy transparent upgradeable proxy admin
        proxyAdmin = new ProxyAdmin(strategyAdmin);

        BaseHopStrategy implementation1 = new BaseHopStrategy();
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation1),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address)",
                address(vault),
                keepers,
                bytes32("MaxApy HOP WETH"),
                strategyAdmin,
                HOP_ETH_SWAP_POLYGON,
                HOP_ETH_SWAP_LP_TOKEN_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy1 = IStrategy(address(proxy));
        strategy1.grantRoles(strategyAdmin, strategy1.ADMIN_ROLE());
        strategy1.grantRoles(strategyEmergencyAdmin, strategy1.EMERGENCY_ADMIN_ROLE());
    
        console2.log("***************************DEPLOYMENT ADDRESSES**********************************");
        console2.log(" VAULT ");
        console2.log("[MAXAPY]Vault :", address(vault));

        console2.log(" STRATEGIES ");
        console2.log("Strategy Deployed Address: ", address(strategy1));
    }
}
