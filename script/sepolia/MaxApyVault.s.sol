// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { Script, console2 } from "forge-std/Script.sol";

import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

import { MaxApyRouter } from "src/MaxApyRouter.sol";
import { MaxApyVault, OwnableRoles } from "src/MaxApyVault.sol";

import { MaxApyVaultFactory } from "src/MaxApyVaultFactory.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { IMaxApyRouter } from "src/interfaces/IMaxApyRouter.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";
import { IWrappedToken } from "src/interfaces/IWrappedToken.sol";

import { BaseSommelierStrategy } from "src/strategies/base/BaseSommelierStrategy.sol";
import { MockCellar } from "test/mock/MockCellar.sol";
import { MockWETH } from "test/mock/MockWETH.sol";

contract DeploymentScript is Script, OwnableRoles {
    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////

    BaseSommelierStrategy public strategy; // yearn
    IMaxApyVault public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;
    MockWETH public token;
    MockCellar public cellar;
    MaxApyRouter public router;
    MaxApyVaultFactory public vaultFactory;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////

    function run() public {
        address[] memory keepers = new address[](3);
        // use another private key here, dont use a keeper account for deployment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        keepers[0] = vm.envAddress("KEEPER1_ADDRESS");
        keepers[1] = vm.envAddress("KEEPER2_ADDRESS");
        keepers[2] = vm.envAddress("KEEPER3_ADDRESS");

        address vaultAdmin = vm.envAddress("VAULT_ADMIN_ADDRESS");
        address vaultEmergencyAdmin = vm.envAddress("VAULT_EMERGENCY_ADMIN_ADDRESS");
        address strategyAdmin = vm.envAddress("STRATEGY_ADMIN_ADDRESS");
        address strategyEmergencyAdmin = vm.envAddress("STRATEGY_EMERGENCY_ADMIN_ADDRESS");

        address treasury = vm.envAddress("TREASURY_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);
        // Deploy token
        token = new MockWETH("Wrapped Ether", "WETH");
        token.mint(deployerAddress, 100_000 ether);
        token.mint(vaultAdmin, 100_000 ether);
        token.mint(vaultEmergencyAdmin, 100_000 ether);
        token.mint(strategyAdmin, 100_000 ether);
        token.mint(keepers[0], 100_000 ether);
        token.mint(keepers[1], 100_000 ether);
        token.mint(keepers[2], 100_000 ether);

        /// Deploy router
        router = new MaxApyRouter(IWrappedToken(address(token)));

        /// Deploy factory and MaxApyVault
        vaultFactory = new MaxApyVaultFactory(treasury);
        address deployedVault = vaultFactory.deploy(address(token), vaultAdmin, "Max APY");

        vault = IMaxApyVault(address(deployedVault));

        /// Deploy transparent upgradeable proxy admin
        proxyAdmin = new ProxyAdmin(vaultAdmin);

        /// Deploy underlying cellar
        cellar = new MockCellar(address(token), "Sommelier WETH", "SWETH", true, 0);

        // Deploy strategy
        BaseSommelierStrategy implementation = new BaseSommelierStrategy();
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Strategy")),
                strategyAdmin,
                address(cellar)
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy = BaseSommelierStrategy(address(_proxy));
        strategy.grantRoles(strategyAdmin, strategy.ADMIN_ROLE());
        strategy.grantRoles(strategyEmergencyAdmin, strategy.EMERGENCY_ADMIN_ROLE());

        // Add strategy
        vault.addStrategy(address(strategy), 6000, type(uint72).max, 0, 0);

        // Remove strategy
        vault.exitStrategy(address(strategy));

        // Add it back
        vault.addStrategy(address(strategy), 6000, type(uint72).max, 0, 0);

        console2.log("***************************DEPLOYMENT ADDRESSES**********************************");
        console2.log("[MAXAPY] Factory :", address(vaultFactory));
        console2.log("[MAXAPY] Vault :", address(vault));
        console2.log("[MAXAPY] Router:", address(router));
        console2.log("[MOCK] WETH Token:", address(token));
        console2.log("[MOCK] WETH Strategy:", address(strategy));
        console2.log("[MOCK] SOMMELIER CELLAR:", address(cellar));

        console2.log("***************************ADDED TO VAULT**********************************");
        console2.log("[MOCK] WETH Strategy:", address(strategy));
    }
}
