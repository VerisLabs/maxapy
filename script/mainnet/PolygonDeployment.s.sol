// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";

import { IERC20, console2 } from "../../test/base/BaseTest.t.sol";
import { IStrategy } from "src/interfaces/IStrategy.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";
import { MaxApyVault, OwnableRoles } from "src/MaxApyVault.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { StrategyEvents } from "../../test/helpers/StrategyEvents.sol";
import { IUniswapV2Router02 as IRouter } from "src/interfaces/IUniswap.sol";

//// Strategiess
import { YearnAjnaUSDCStrategy } from "src/strategies/polygon/USDCe/yearn/YearnAjnaUSDCStrategy.sol";
import { YearnCompoundUSDCeLenderStrategy } from
    "src/strategies/polygon/USDCe/yearn/YearnCompoundUSDCeLenderStrategy.sol";
import { YearnMaticUSDCStakingStrategy } from "src/strategies/polygon/USDCe/yearn/YearnMaticUSDCStakingStrategy.sol";
import { YearnUSDCeLenderStrategy } from "src/strategies/polygon/USDCe/yearn/YearnUSDCeLenderStrategy.sol";
import { YearnUSDCeStrategy } from "src/strategies/polygon/USDCe/yearn/YearnUSDCeStrategy.sol";

//// Helpers(Factory , Router)f
import { MaxApyRouter } from "src/MaxApyRouter.sol";
import { MaxApyVaultFactory } from "src/MaxApyVaultFactory.sol";

import { IWrappedToken } from "src/interfaces/IWrappedToken.sol";
import "src/helpers/AddressBook.sol";

/// @notice this is a simple test deployment of a polygon USDCe vault in a local rpc
contract PolygonDeploymentScript is Script, OwnableRoles {
    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////
    // **********STRATS******************
    // USDCE
    IStrategy public strategy1; // YeearnAjnaUSDC
    IStrategy public strategy2; // YearnCompoundUSDCeLender
    IStrategy public strategy3; // YearnMaticUSDCStraking
    IStrategy public strategy4; // YearnUSDCeLender
    IStrategy public strategy5; // YearnUSDCe

    // **********ROLES*******************
    address[] keepers;

    // **********LOCAL VARIABLES*****************
    // use storage variables to avoid stack too deep
    IMaxApyVault vaultUsdce;
    ITransparentUpgradeableProxy proxy;
    ProxyAdmin proxyAdmin;
    address vaultAdmin;
    address vaultEmergencyAdmin;
    address strategyAdmin;
    address strategyEmergencyAdmin;
    address treasury;
    address vaultDeployment;
    MaxApyRouter router;
    MaxApyVaultFactory vaultFactory;
    address factoryAdmin;
    address factoryDeployer;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////

    function run() public {
        // use another private key here, dont use a keeper account for deployment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        keepers.push(vm.envAddress("KEEPER1_ADDRESS"));
        keepers.push(vm.envAddress("KEEPER2_ADDRESS"));
        keepers.push(vm.envAddress("KEEPER3_ADDRESS"));

        vaultAdmin = vm.envAddress("VAULT_ADMIN_ADDRESS");
        vaultEmergencyAdmin = vm.envAddress("VAULT_EMERGENCY_ADMIN_ADDRESS");
        strategyAdmin = vm.envAddress("STRATEGY_ADMIN_ADDRESS");
        strategyEmergencyAdmin = vm.envAddress("STRATEGY_EMERGENCY_ADMIN_ADDRESS");
        factoryAdmin = vm.envAddress("FACTORY_ADMIN");
        factoryDeployer = vm.envAddress("FACTORY_DEPLOYER");
        treasury = vm.envAddress("TREASURY_ADDRESS_POLYGON");
        bool isFork = vm.envBool("FORK");

        if (isFork) {
            revert("fork setup");
        }

        vm.startBroadcast(deployerPrivateKey);

        /////////////////////////////// HELPERS ///////////////////////////

        /// Deploy router
        router = new MaxApyRouter(IWrappedToken(USDCE_POLYGON));

        /// Deploy factory and MaxApyVault
        vaultFactory = new MaxApyVaultFactory(treasury);
        vaultFactory.grantRoles(factoryAdmin, vaultFactory.ADMIN_ROLE());
        vaultFactory.grantRoles(factoryDeployer, vaultFactory.DEPLOYER_ROLE());

        /// Deploy MaxApyVault
        vaultDeployment = vaultFactory.deploy(address(USDCE_POLYGON), deployerAddress, "Max APY");
        vaultUsdce = IMaxApyVault(address(vaultDeployment));
        // grant roles
        vaultUsdce.grantRoles(vaultAdmin, vaultUsdce.ADMIN_ROLE());
        vaultUsdce.grantRoles(vaultEmergencyAdmin, vaultUsdce.EMERGENCY_ADMIN_ROLE());

        /// Deploy transparent upgradeable proxy admin
        proxyAdmin = new ProxyAdmin(strategyAdmin);

        // Strategy1(YearnAjnaUSDCStrategy)
        YearnAjnaUSDCStrategy implementation1 = new YearnAjnaUSDCStrategy();
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation1),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultUsdce),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Ajna<>USDC")),
                strategyAdmin,
                YEARN_AJNA_USDC_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy1 = IStrategy(address(proxy));
        strategy1.grantRoles(strategyAdmin, strategy1.ADMIN_ROLE());
        strategy1.grantRoles(strategyEmergencyAdmin, strategy1.EMERGENCY_ADMIN_ROLE());

        // Strategy2(YearnCompoundUSDCeLender)
        YearnCompoundUSDCeLenderStrategy implementation2 = new YearnCompoundUSDCeLenderStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation2),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultUsdce),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Strategy")),
                strategyAdmin,
                YEARN_COMPOUND_USDC_LENDER_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy2 = IStrategy(address(proxy));
        strategy2.grantRoles(strategyAdmin, strategy2.ADMIN_ROLE());
        strategy2.grantRoles(strategyEmergencyAdmin, strategy2.EMERGENCY_ADMIN_ROLE());

        // Strategy3(YearnMaticUSDCStakingStrategy)
        YearnMaticUSDCStakingStrategy implementation3 = new YearnMaticUSDCStakingStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation3),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultUsdce),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Strategy")),
                strategyAdmin,
                YEARN_MATIC_USDC_STAKING_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy3 = IStrategy(address(proxy));
        strategy3.grantRoles(strategyAdmin, strategy3.ADMIN_ROLE());
        strategy3.grantRoles(strategyEmergencyAdmin, strategy3.EMERGENCY_ADMIN_ROLE());

        // Strategy4(YeaarnUSDCeStrategy)
        YearnUSDCeStrategy implementation4 = new YearnUSDCeStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation4),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultUsdce),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Strategy")),
                strategyAdmin,
                YEARN_USDCE_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy4 = IStrategy(address(proxy));
        strategy4.grantRoles(strategyAdmin, strategy4.ADMIN_ROLE());
        strategy4.grantRoles(strategyEmergencyAdmin, strategy4.EMERGENCY_ADMIN_ROLE());

        // Strategy5(YearnUSDCeLender)
        YearnUSDCeLenderStrategy implementation5 = new YearnUSDCeLenderStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation5),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultUsdce),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Strategy")),
                strategyAdmin,
                YEARN_USDCE_LENDER_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy5 = IStrategy(address(proxy));
        strategy5.grantRoles(strategyAdmin, strategy5.ADMIN_ROLE());
        strategy5.grantRoles(strategyEmergencyAdmin, strategy5.EMERGENCY_ADMIN_ROLE());

        console2.log("***************************DEPLOYMENT ADDRESSES**********************************");
        console2.log("[MAXAPY] Router :", address(router));
        console2.log("[MAXAPY] Factory :", address(vaultFactory));
        console2.log("[MAXAPY] USDCE Vault :", address(vaultUsdce));
        console2.log("[YEARN] AjnaUSDC:", address(strategy1));
        console2.log("[YEARN] CompoundUSDCeLender:", address(strategy2));
        console2.log("[YEARN] MaticUSDCStaking:", address(strategy3));
        console2.log("[YEARN] USDCeLender:", address(strategy4));
        console2.log("[YEARN] USDCe:", address(strategy5));
    }
}
