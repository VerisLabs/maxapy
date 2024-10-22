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
import { BeefyMaiUSDCeStrategy } from "src/strategies/polygon/USDCe/beefy/BeefyMaiUSDCeStrategy.sol";
import { ConvexUSDCCrvUSDStrategy } from "src/strategies/polygon/USDCe/convex/ConvexUSDCCrvUSDStrategy.sol";
import { ConvexUSDTCrvUSDStrategy } from "src/strategies/polygon/USDCe/convex/ConvexUSDTCrvUSDStrategy.sol";
import { YearnMaticUSDCStakingStrategy } from "src/strategies/polygon/USDCe/yearn/YearnMaticUSDCStakingStrategy.sol";
import { YearnAjnaUSDCStrategy } from "src/strategies/polygon/USDCe/yearn/YearnAjnaUSDCStrategy.sol";
import { YearnUSDTStrategy } from "src/strategies/polygon/USDCe/yearn/YearnUSDTStrategy.sol";
import { YearnUSDCeLenderStrategy } from "src/strategies/polygon/USDCe/yearn/YearnUSDCeLenderStrategy.sol";
import { YearnUSDCeStrategy } from "src/strategies/polygon/USDCe/yearn/YearnUSDCeStrategy.sol";
import { YearnDAIStrategy } from "src/strategies/polygon/USDCe/yearn/YearnDAIStrategy.sol";
import { YearnDAILenderStrategy } from "src/strategies/polygon/USDCe/yearn/YearnDAILenderStrategy.sol";
import { YearnCompoundUSDCeLenderStrategy } from
    "src/strategies/polygon/USDCe/yearn/YearnCompoundUSDCeLenderStrategy.sol";

//// Vault
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { MaxApyRouter } from "src/MaxApyRouter.sol";
import { MaxApyVaultFactory } from "src/MaxApyVaultFactory.sol";
import { MaxApyHarvester } from "src/periphery/MaxApyHarvester.sol";
import { MaxApyVault, OwnableRoles } from "src/MaxApyVault.sol";

/// @notice this is a simple test deployment of a polygon USDCe vault in a local rpc
contract PolygonDeploymentScript is Script, OwnableRoles {
    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////
    // **********STRATS******************
    // USDCE
    IStrategy public strategy1; // BeefyMaiUSDCeStrategy
    IStrategy public strategy2; // ConvexUSDCCrvUSDStrategy
    IStrategy public strategy3; // ConvexUSDTCrvUSDStrategy
    IStrategy public strategy4; // YearnMaticUSDCStaking
    IStrategy public strategy5; // YearnAjnaUSDC
    IStrategy public strategy6; // YearnUSDTStrategy
    IStrategy public strategy7; // YearnUSDCeLender
    IStrategy public strategy8; // YearnUSDCe
    IStrategy public strategy9; // YearnDAIStrategy
    IStrategy public strategy10; // YearnDAILenderStrategy
    IStrategy public strategy11; // YearnCompoundUSDCeLender

    // **********ROLES*******************
    address[] keepers;

    // **********LOCAL VARIABLES*****************
    // use storage variables to avoid stack too deep

    // Proxies
    ITransparentUpgradeableProxy proxy;
    ProxyAdmin proxyAdmin;

    // Vault
    IMaxApyVault vaultUsdce;
    MaxApyRouter router;
    MaxApyVaultFactory vaultFactory;
    MaxApyHarvester harvester;

    // Actors
    address vaultAdmin;
    address vaultEmergencyAdmin;
    address strategyAdmin;
    address strategyEmergencyAdmin;
    address treasury;
    address vaultDeployment;
    address factoryAdmin;
    address factoryDeployer;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////

    function run() public {
        /////////////////////////////////////////////////////////////////////////
        ///                             ACTORS                                ///
        /////////////////////////////////////////////////////////////////////////
        // use another private key here, dont use a keeper account for deployment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        keepers.push(vm.envAddress("KEEPER1_ADDRESS"));
        keepers.push(vm.envAddress("KEEPER2_ADDRESS"));

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

        /////////////////////////////////////////////////////////////////////////
        ///                             VAULT                                 ///
        /////////////////////////////////////////////////////////////////////////
        /// Deploy MaxApyHarvester
        /// Keepers = Backend - Relayers
        harvester = new MaxApyHarvester(vaultAdmin, keepers);
        keepers.push(address(harvester));

        /// Deploy router
        router = new MaxApyRouter(IWrappedToken(USDCE_POLYGON));

        /// Deploy factory and MaxApyVault
        vaultFactory = new MaxApyVaultFactory(treasury);
        vaultFactory.grantRoles(factoryAdmin, vaultFactory.ADMIN_ROLE());
        vaultFactory.grantRoles(factoryDeployer, vaultFactory.DEPLOYER_ROLE());

        /// Deploy MaxApyVault USDCE Vault
        vaultDeployment = vaultFactory.deploy(address(USDCE_POLYGON), deployerAddress, "Max APY");
        vaultUsdce = IMaxApyVault(address(vaultDeployment));
        vaultUsdce.grantRoles(vaultAdmin, vaultUsdce.ADMIN_ROLE());
        vaultUsdce.grantRoles(vaultEmergencyAdmin, vaultUsdce.EMERGENCY_ADMIN_ROLE());
        vaultUsdce.grantRoles(address(harvester), vaultUsdce.ADMIN_ROLE());

        /////////////////////////////////////////////////////////////////////////
        ///                        STRATEGIES                                 ///
        /////////////////////////////////////////////////////////////////////////
        /// Deploy transparent upgradeable proxy admin
        proxyAdmin = new ProxyAdmin(strategyAdmin);

        // Strategy1(BeefyMaiUSDCeStrategy)
        BeefyMaiUSDCeStrategy implementation1 = new BeefyMaiUSDCeStrategy();
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation1),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address)",
                address(vaultUsdce),
                keepers,
                bytes32(abi.encode("MaxApy Beefy MAI<>USDCe")),
                strategyAdmin,
                CURVE_MAI_USDCE_POOL_POLYGON,
                BEEFY_MAI_USDCE_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy1 = IStrategy(address(proxy));
        strategy1.grantRoles(strategyAdmin, strategy1.ADMIN_ROLE());
        strategy1.grantRoles(strategyEmergencyAdmin, strategy1.EMERGENCY_ADMIN_ROLE());

        // Strategy2(ConvexUSDCCrvUSDStrategy)
        ConvexUSDCCrvUSDStrategy implementation2 = new ConvexUSDCCrvUSDStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation2),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address)",
                address(vaultUsdce),
                keepers,
                bytes32(abi.encode("MaxApy Convex USD<>USDCe")),
                strategyAdmin,
                CURVE_CRVUSD_USDC_POOL_POLYGON,
                UNISWAP_V3_ROUTER_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy2 = IStrategy(address(proxy));
        strategy2.grantRoles(strategyAdmin, strategy2.ADMIN_ROLE());
        strategy2.grantRoles(strategyEmergencyAdmin, strategy2.EMERGENCY_ADMIN_ROLE());

        // Strategy3(ConvexUSDTCrvUSDStrategy)
        ConvexUSDTCrvUSDStrategy implementation3 = new ConvexUSDTCrvUSDStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation3),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address)",
                address(vaultUsdce),
                keepers,
                bytes32(abi.encode("MaxApy Convex USDT<>USDCe")),
                strategyAdmin,
                CURVE_CRVUSD_USDT_POOL_POLYGON,
                UNISWAP_V3_ROUTER_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy3 = IStrategy(address(proxy));
        strategy3.grantRoles(strategyAdmin, strategy3.ADMIN_ROLE());
        strategy3.grantRoles(strategyEmergencyAdmin, strategy3.EMERGENCY_ADMIN_ROLE());

        // Strategy4(YearnMaticUSDCStaking)
        YearnMaticUSDCStakingStrategy implementation4 = new YearnMaticUSDCStakingStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation4),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultUsdce),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Matic<>USDCe")),
                strategyAdmin,
                YEARN_MATIC_USDC_STAKING_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy4 = IStrategy(address(proxy));
        strategy4.grantRoles(strategyAdmin, strategy4.ADMIN_ROLE());
        strategy4.grantRoles(strategyEmergencyAdmin, strategy4.EMERGENCY_ADMIN_ROLE());

        // Strategy5(YearnAjnaUSDC)
        YearnAjnaUSDCStrategy implementation5 = new YearnAjnaUSDCStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation5),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultUsdce),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Ajna<>USDCe")),
                strategyAdmin,
                YEARN_AJNA_USDC_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy5 = IStrategy(address(proxy));
        strategy5.grantRoles(strategyAdmin, strategy5.ADMIN_ROLE());
        strategy5.grantRoles(strategyEmergencyAdmin, strategy5.EMERGENCY_ADMIN_ROLE());

        // Strategy6(YearnUSDTStrategy)
        YearnUSDTStrategy implementation6 = new YearnUSDTStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation6),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultUsdce),
                keepers,
                bytes32(abi.encode("MaxApy Yearn USDT<>USDCe")),
                strategyAdmin,
                YEARN_USDT_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy6 = IStrategy(address(proxy));
        strategy6.grantRoles(strategyAdmin, strategy6.ADMIN_ROLE());
        strategy6.grantRoles(strategyEmergencyAdmin, strategy6.EMERGENCY_ADMIN_ROLE());

        // Strategy7(YearnUSDCeLender)
        YearnUSDCeLenderStrategy implementation7 = new YearnUSDCeLenderStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation7),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultUsdce),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Lender USDCe")),
                strategyAdmin,
                YEARN_USDCE_LENDER_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy7 = IStrategy(address(proxy));
        strategy7.grantRoles(strategyAdmin, strategy7.ADMIN_ROLE());
        strategy7.grantRoles(strategyEmergencyAdmin, strategy7.EMERGENCY_ADMIN_ROLE());

        // Strategy8(YearnUSDCe)
        YearnUSDCeStrategy implementation8 = new YearnUSDCeStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation8),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultUsdce),
                keepers,
                bytes32(abi.encode("MaxApy Yearn USDCe")),
                strategyAdmin,
                YEARN_USDCE_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy8 = IStrategy(address(proxy));
        strategy8.grantRoles(strategyAdmin, strategy8.ADMIN_ROLE());
        strategy8.grantRoles(strategyEmergencyAdmin, strategy8.EMERGENCY_ADMIN_ROLE());

        // Strategy9(YearnDAIStrategy)
        YearnDAIStrategy implementation9 = new YearnDAIStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation9),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultUsdce),
                keepers,
                bytes32(abi.encode("MaxApy Yearn DAI<>USDCe")),
                strategyAdmin,
                YEARN_DAI_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy9 = IStrategy(address(proxy));
        strategy9.grantRoles(strategyAdmin, strategy9.ADMIN_ROLE());
        strategy9.grantRoles(strategyEmergencyAdmin, strategy9.EMERGENCY_ADMIN_ROLE());

        // Strategy10(YearnDAILenderStrategy)
        YearnDAILenderStrategy implementation10 = new YearnDAILenderStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation10),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultUsdce),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Lender DAI<>USDCe")),
                strategyAdmin,
                YEARN_DAI_LENDER_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy10 = IStrategy(address(proxy));
        strategy10.grantRoles(strategyAdmin, strategy10.ADMIN_ROLE());
        strategy10.grantRoles(strategyEmergencyAdmin, strategy10.EMERGENCY_ADMIN_ROLE());

        // Strategy11(YearnCompoundUSDCeLender)
        YearnCompoundUSDCeLenderStrategy implementation11 = new YearnCompoundUSDCeLenderStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation11),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultUsdce),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Compound Lender USDCe")),
                strategyAdmin,
                YEARN_COMPOUND_USDC_LENDER_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy11 = IStrategy(address(proxy));
        strategy11.grantRoles(strategyAdmin, strategy11.ADMIN_ROLE());
        strategy11.grantRoles(strategyEmergencyAdmin, strategy11.EMERGENCY_ADMIN_ROLE());

        console2.log("***************************DEPLOYMENT ADDRESSES**********************************");
        console2.log(" VAULT ");
        console2.log("[MAXAPY] Harvester :", address(harvester));
        console2.log("[MAXAPY] Router :", address(router));
        console2.log("[MAXAPY] Factory :", address(vaultFactory));
        console2.log("[MAXAPY] USDCE Vault :", address(vaultUsdce));

        console2.log(" STRATEGIES ");
        console2.log("[BEEFY] BeefyMaiUSDCeStrategy:", address(strategy1));
        console2.log("[CONVEX] ConvexUSDCCrvUSDStrategy:", address(strategy2));
        console2.log("[CONVEX] ConvexUSDTCrvUSDStrategy:", address(strategy3));
        console2.log("[YEARN] YearnMaticUSDCStaking:", address(strategy4));
        console2.log("[YEARN] YearnAjnaUSDC:", address(strategy5));
        console2.log("[YEARN] YearnUSDTStrategy:", address(strategy6));
        console2.log("[YEARN] YearnUSDCeLender:", address(strategy7));
        console2.log("[YEARN] YearnUSDCe:", address(strategy8));
        console2.log("[YEARN] YearnDAIStrategy:", address(strategy9));
        console2.log("[YEARN] YearnDAILenderStrategy:", address(strategy10));
        console2.log("[YEARN] YearnCompoundUSDCeLender:", address(strategy11));
    }
}
