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
import { BeefyMaiUSDCeStrategy } from "src/strategies/polygon/USDCe/beefy/BeefyMaiUSDCeStrategy.sol";
import { ConvexUSDCCrvUSDStrategy } from "src/strategies/polygon/USDCe/convex/ConvexUSDCCrvUSDStrategy.sol";
import { ConvexUSDTCrvUSDStrategy } from "src/strategies/polygon/USDCe/convex/ConvexUSDTCrvUSDStrategy.sol";
import { YearnDAIStrategy } from "src/strategies/polygon/USDCe/yearn/YearnDAIStrategy.sol";
import { YearnDAILenderStrategy } from "src/strategies/polygon/USDCe/yearn/YearnDAILenderStrategy.sol";
import { YearnUSDTStrategy } from "src/strategies/polygon/USDCe/yearn/YearnUSDTStrategy.sol";

//// Helpers(Factory , Router)f
import { MaxApyRouter } from "src/MaxApyRouter.sol";
import { MaxApyVaultFactory } from "src/MaxApyVaultFactory.sol";

import { IWrappedToken } from "src/interfaces/IWrappedToken.sol";
import "src/helpers/AddressBook.sol";

/// @notice this is a simple test deployment of a polygon USDCe vault in a local rpc
contract PolygonStrategiesDeploymentScript is Script, OwnableRoles {
    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////
    // **********STRATS******************
    // USDCE
    IStrategy public strategy1; // BeefyMAI
    IStrategy public strategy2; // ConvexUSDCCrvUSD
    IStrategy public strategy3; // ConvexUSDTCrvUSD
    IStrategy public strategy4; // YearnDAIStrategy
    IStrategy public strategy5; // YearnDAILenderStrategy
    IStrategy public strategy6; // YearnUSDT

    // **********ROLES*******************
    address[] keepers;

    // **********LOCAL VARIABLES*****************
    // use storage variables to avoid stack too deep
    IMaxApyVault vaultUsdce;
    ITransparentUpgradeableProxy proxy;
    ProxyAdmin proxyAdmin;
    address strategyAdmin;
    address strategyEmergencyAdmin;
    address vaultDeployment;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////

    function run() public {
        // use another private key here, dont use a keeper account for deployment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        keepers.push(vm.envAddress("KEEPER1_ADDRESS"));
        //keepers.push(vm.envAddress("KEEPER2_ADDRESS"));
        //keepers.push(vm.envAddress("KEEPER3_ADDRESS"));

        strategyAdmin = vm.envAddress("STRATEGY_ADMIN_ADDRESS");
        strategyEmergencyAdmin = vm.envAddress("STRATEGY_EMERGENCY_ADMIN_ADDRESS");
        bool isFork = vm.envBool("FORK");

        if (isFork) {
            revert("fork setup");
        }

        vaultUsdce = IMaxApyVault(0xbc45ee5275fC1FaEB129b755C67fc6Fc992109DE);

        vm.startBroadcast(deployerPrivateKey);

        /////////////////////////////// HELPERS ///////////////////////////

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
                CURVE_MAI_USDCE_POOL_POLYGON, // curveLpPool
                BEEFY_MAI_USDCE_POLYGON // beefyVault
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
                bytes32(abi.encode("MaxApy Convex USDC<>USD")),
                strategyAdmin,
                CURVE_CRVUSD_USDC_POOL_POLYGON, // curveLpPool
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
                bytes32(abi.encode("MaxApy Convex USDT<>USD")),
                strategyAdmin,
                CURVE_CRVUSD_USDT_POOL_POLYGON, // curveLpPool,
                UNISWAP_V3_ROUTER_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy3 = IStrategy(address(proxy));
        strategy3.grantRoles(strategyAdmin, strategy3.ADMIN_ROLE());
        strategy3.grantRoles(strategyEmergencyAdmin, strategy3.EMERGENCY_ADMIN_ROLE());

        // Strategy4(YearnDAIStrategy)
        YearnDAIStrategy implementation4 = new YearnDAIStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation4),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultUsdce),
                keepers,
                bytes32(abi.encode("MaxApy Yearn  DAI")),
                strategyAdmin,
                YEARN_DAI_POLYGON_VAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy4 = IStrategy(address(proxy));
        strategy4.grantRoles(strategyAdmin, strategy4.ADMIN_ROLE());
        strategy4.grantRoles(strategyEmergencyAdmin, strategy4.EMERGENCY_ADMIN_ROLE());

        // Strategy5(YearnDAILenderStrategy)
        YearnDAILenderStrategy implementation5 = new YearnDAILenderStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation5),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultUsdce),
                keepers,
                bytes32(abi.encode("MaxApy Yearn DAI Lender")),
                strategyAdmin,
                YEARN_DAI_LENDER_YVAULT_POLYGON
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
                bytes32(abi.encode("MaxApy Yearn USDT")),
                strategyAdmin,
                YEARN_USDCE_LENDER_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy6 = IStrategy(address(proxy));
        strategy6.grantRoles(strategyAdmin, strategy6.ADMIN_ROLE());
        strategy6.grantRoles(strategyEmergencyAdmin, strategy6.EMERGENCY_ADMIN_ROLE());

        console2.log("***************************DEPLOYMENT ADDRESSES**********************************");
        console2.log("[MAXAPY] USDCE Vault :", address(vaultUsdce));
        console2.log("[BEEFY] BeefyMaiUSDCe:", address(strategy1));
        console2.log("[CONVEX] ConvexUSDCCrvUSD:", address(strategy2));
        console2.log("[CONVEX] ConvexUSDTCrvUSD:", address(strategy3));
        console2.log("[YEARN] YearnDAI:", address(strategy4));
        console2.log("[YEARN] YearnDAILender:", address(strategy5));
        console2.log("[YEARN] YearnUSDT:", address(strategy5));
    }
}
