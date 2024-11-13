// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

import { BaseTest, IERC20, Vm, console2 } from "../../test/base/BaseTest.t.sol";

import { StrategyEvents } from "../../test/helpers/StrategyEvents.sol";
import { IStrategyWrapper } from "../../test/interfaces/IStrategyWrapper.sol";
import { MaxApyVault, OwnableRoles } from "src/MaxApyVault.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";

import { IUniswapV2Router02 as IRouter } from "src/interfaces/IUniswap.sol";

// Convex strategies
import { ConvexdETHFrxETHStrategyWrapper } from "../../test/mock/ConvexdETHFrxETHStrategyWrapper.sol";
// Yearn strategies
import { YearnWETHStrategyWrapper } from "../../test/mock/YearnWETHStrategyWrapper.sol";
// Sommelier strategies
import { SommelierMorphoEthMaximizerStrategyWrapper } from
    "../../test/mock/SommelierMorphoEthMaximizerStrategyWrapper.sol";
import { SommelierStEthDepositTurboStEthStrategyWrapper } from
    "../../test/mock/SommelierStEthDepositTurboStEthStrategyWrapper.sol";
import { SommelierTurboDivEthStrategyWrapper } from "../../test/mock/SommelierTurboDivEthStrategyWrapper.sol";
import { SommelierTurboEEthV2StrategyWrapper } from "../../test/mock/SommelierTurboEEthV2StrategyWrapper.sol";
import { SommelierTurboEthXStrategyWrapper } from "../../test/mock/SommelierTurboEthXStrategyWrapper.sol";
import { SommelierTurboEzEthStrategyWrapper } from "../../test/mock/SommelierTurboEzEthStrategyWrapper.sol";
import { SommelierTurboRsEthStrategyWrapper } from "../../test/mock/SommelierTurboRsEthStrategyWrapper.sol";
import { SommelierTurboStEthStrategyWrapper } from "../../test/mock/SommelierTurboStEthStrategyWrapper.sol";
import { SommelierTurboSwEthStrategyWrapper } from "../../test/mock/SommelierTurboSwEthStrategyWrapper.sol";
import "src/helpers/AddressBook.sol";

/// @notice this is a simple test deployment of a mainnet WETH vault in a local rpc
contract DeploymentScript is Script, OwnableRoles {
    ////////////////////////////////////////////////////////////////
    ///                      CONSTANTS                           ///
    ////////////////////////////////////////////////////////////////
    address public constant WETH = WETH_MAINNET;

    address public constant CURVE_POOL = CURVE_DETH_FRXETH_POOL_MAINNET;

    address public constant YVAULT_WETH_MAINNET = YEARN_WETH_YVAULT_MAINNET;

    address public constant CELLAR_WETH_MAINNET_MORPHO = SOMMELIER_MORPHO_ETH_MAXIMIZER_CELLAR_MAINNET;
    address public constant CELLAR_STETH_MAINNET = SOMMELIER_ST_ETH_DEPOSIT_TURBO_STETH_CELLAR_MAINNET;
    address public constant CELLAR_WETH_MAINNET_DIV_ETH = SOMMELIER_TURBO_DIV_ETH_CELLAR_MAINNET;
    address public constant CELLAR_WETH_MAINNET_EETHV2 = SOMMELIER_TURBO_EZETH_CELLAR_MAINNET;
    address public constant CELLAR_WETH_MAINNET_ETHX = SOMMELIER_TURBO_EETHX_CELLAR_MAINNET;
    address public constant CELLAR_WETH_MAINNET_EZ_ETH = SOMMELIER_TURBO_EZETH_CELLAR_MAINNET;
    address public constant CELLAR_WETH_MAINNET_RS_ETH = SOMMELIER_TURBO_RSETH_CELLAR_MAINNET;
    address public constant CELLAR_WETH_MAINNET_STETH = SOMMELIER_TURBO_STETH_CELLAR_MAINNET;
    address public constant CELLAR_WETH_MAINNET_SW_ETH = SOMMELIER_TURBO_SWETH_CELLAR_MAINNET;

    IERC20 public constant crv = IERC20(CRV_MAINNET);
    IERC20 public constant cvx = IERC20(CVX_MAINNET);
    IERC20 public constant frxEth = IERC20(FRXETH_MAINNET);

    IRouter public constant SUSHISWAP_ROUTER = IRouter(SUSHISWAP_ROUTER_MAINNET);

    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////
    // **********STRATS******************
    IStrategyWrapper public strategy1; // convex
    IStrategyWrapper public strategy2; // yearn
    IStrategyWrapper public strategy3; // sommelier morpho
    IStrategyWrapper public strategy4; // sommelier st-eth deposit turbo-st-eth
    IStrategyWrapper public strategy5; // sommelier div-eth
    IStrategyWrapper public strategy6; // sommelier e-eth-v2
    IStrategyWrapper public strategy7; // sommelier eth-x
    IStrategyWrapper public strategy8; // sommelier ez-eth
    IStrategyWrapper public strategy9; // sommelier rs-eth
    IStrategyWrapper public strategy10; // sommelier st-eth
    IStrategyWrapper public strategy11; // sommelier sw-eth

    // **********ROLES*******************
    address[] keepers;

    // **********LOCAL VARIABLES*****************
    // use storage variables to avoid stack too deep
    IMaxApyVault public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;
    address vaultAdmin;
    address vaultEmergencyAdmin;
    address strategyAdmin;
    address strategyEmergencyAdmin;
    address treasury;
    MaxApyVault vaultDeployment;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////

    function run() public {
        // use another private key here, dont use a keeper account for deployment
        address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        keepers.push(vm.envAddress("KEEPER1_ADDRESS"));
        keepers.push(vm.envAddress("KEEPER2_ADDRESS"));
        keepers.push(vm.envAddress("KEEPER3_ADDRESS"));

        vaultAdmin = vm.envAddress("VAULT_ADMIN_ADDRESS");
        vaultEmergencyAdmin = vm.envAddress("VAULT_EMERGENCY_ADMIN_ADDRESS");
        strategyAdmin = vm.envAddress("STRATEGY_ADMIN_ADDRESS");
        strategyEmergencyAdmin = vm.envAddress("STRATEGY_EMERGENCY_ADMIN_ADDRESS");
        treasury = vm.envAddress("TREASURY_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        /// Deploy MaxApyVault
        vaultDeployment = new MaxApyVault(deployerAddress, WETH, "MaxApyWETHVault", "maxApy", treasury);

        vault = IMaxApyVault(address(vaultDeployment));
        // grant roles
        vault.grantRoles(vaultAdmin, vault.ADMIN_ROLE());
        vault.grantRoles(vaultEmergencyAdmin, vault.EMERGENCY_ADMIN_ROLE());

        /// Deploy transparent upgradeable proxy admin
        proxyAdmin = new ProxyAdmin(strategyAdmin);

        // Deploy strategy1 (Convex)

        ConvexdETHFrxETHStrategyWrapper implementation1 = new ConvexdETHFrxETHStrategyWrapper();
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation1),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address,address)",
                address(vault),
                keepers,
                strategyAdmin,
                bytes32(abi.encode("MaxApy dETH<>frxETH Strategy")),
                CURVE_DETH_FRXETH_POOL_MAINNET,
                CURVE_ETH_FRXETH_POOL_MAINNET,
                address(SUSHISWAP_ROUTER)
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy1 = IStrategyWrapper(address(_proxy));
        strategy1.grantRoles(strategyAdmin, strategy1.ADMIN_ROLE());
        strategy1.grantRoles(strategyEmergencyAdmin, strategy1.EMERGENCY_ADMIN_ROLE());

        // Deploy strategy2 (Yearn WETH)
        YearnWETHStrategyWrapper implementation2 = new YearnWETHStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation2),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Strategy")),
                strategyAdmin,
                YVAULT_WETH_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy2 = IStrategyWrapper(address(_proxy));
        strategy2.grantRoles(strategyAdmin, strategy2.ADMIN_ROLE());
        strategy2.grantRoles(strategyEmergencyAdmin, strategy2.EMERGENCY_ADMIN_ROLE());

        // Deploy strategy3(Morpho Eth maximizer)
        SommelierMorphoEthMaximizerStrategyWrapper implementation3 = new SommelierMorphoEthMaximizerStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation3),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier Strategy")),
                strategyAdmin,
                CELLAR_WETH_MAINNET_MORPHO
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy3 = IStrategyWrapper(address(_proxy));
        strategy3.grantRoles(strategyAdmin, strategy3.ADMIN_ROLE());
        strategy3.grantRoles(strategyEmergencyAdmin, strategy3.EMERGENCY_ADMIN_ROLE());

        // Deploy strategy4(StEthDeposit)

        SommelierStEthDepositTurboStEthStrategyWrapper implementation4 =
            new SommelierStEthDepositTurboStEthStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation4),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier Strategy")),
                strategyAdmin,
                CELLAR_STETH_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy4 = IStrategyWrapper(address(_proxy));
        strategy4.grantRoles(strategyAdmin, strategy4.ADMIN_ROLE());
        strategy4.grantRoles(strategyEmergencyAdmin, strategy4.EMERGENCY_ADMIN_ROLE());

        // Deploy strategy5(DivEth)

        SommelierTurboDivEthStrategyWrapper implementation5 = new SommelierTurboDivEthStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation5),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier Strategy")),
                strategyAdmin,
                CELLAR_WETH_MAINNET_DIV_ETH
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy5 = IStrategyWrapper(address(_proxy));
        strategy5.grantRoles(strategyAdmin, strategy5.ADMIN_ROLE());
        strategy5.grantRoles(strategyEmergencyAdmin, strategy5.EMERGENCY_ADMIN_ROLE());

        // Deploy strategy6(EEth)
        SommelierTurboEEthV2StrategyWrapper implementation6 = new SommelierTurboEEthV2StrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation6),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier Strategy")),
                strategyAdmin,
                CELLAR_WETH_MAINNET_EETHV2
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy6 = IStrategyWrapper(address(_proxy));
        strategy6.grantRoles(strategyAdmin, strategy6.ADMIN_ROLE());
        strategy6.grantRoles(strategyEmergencyAdmin, strategy6.EMERGENCY_ADMIN_ROLE());

        // Deploy strategy7(EthX)
        SommelierTurboEEthV2StrategyWrapper implementation7 = new SommelierTurboEEthV2StrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation7),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier Strategy")),
                strategyAdmin,
                CELLAR_WETH_MAINNET_ETHX
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy7 = IStrategyWrapper(address(_proxy));
        strategy7.grantRoles(strategyAdmin, strategy7.ADMIN_ROLE());
        strategy7.grantRoles(strategyEmergencyAdmin, strategy7.EMERGENCY_ADMIN_ROLE());

        // Deploy strategy8(EzEth)
        SommelierTurboStEthStrategyWrapper implementation8 = new SommelierTurboStEthStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation8),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier Strategy")),
                strategyAdmin,
                CELLAR_WETH_MAINNET_EZ_ETH
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy8 = IStrategyWrapper(address(_proxy));
        strategy8.grantRoles(strategyAdmin, strategy8.ADMIN_ROLE());
        strategy8.grantRoles(strategyEmergencyAdmin, strategy8.EMERGENCY_ADMIN_ROLE());

        // Deploy strategy9(RsEth)
        SommelierTurboStEthStrategyWrapper implementation9 = new SommelierTurboStEthStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation9),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier Strategy")),
                strategyAdmin,
                CELLAR_WETH_MAINNET_RS_ETH
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy9 = IStrategyWrapper(address(_proxy));
        strategy9.grantRoles(strategyAdmin, strategy9.ADMIN_ROLE());
        strategy9.grantRoles(strategyEmergencyAdmin, strategy9.EMERGENCY_ADMIN_ROLE());

        // Deploy strategy10(StEth)
        SommelierTurboStEthStrategyWrapper implementation10 = new SommelierTurboStEthStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation10),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier Strategy")),
                strategyAdmin,
                CELLAR_WETH_MAINNET_STETH
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy10 = IStrategyWrapper(address(_proxy));
        strategy10.grantRoles(strategyAdmin, strategy10.ADMIN_ROLE());
        strategy10.grantRoles(strategyEmergencyAdmin, strategy10.EMERGENCY_ADMIN_ROLE());

        // Deploy strategy11(SwEth)
        SommelierTurboStEthStrategyWrapper implementation11 = new SommelierTurboStEthStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation11),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier Strategy")),
                strategyAdmin,
                CELLAR_WETH_MAINNET_SW_ETH
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy11 = IStrategyWrapper(address(_proxy));
        strategy11.grantRoles(strategyAdmin, strategy11.ADMIN_ROLE());
        strategy11.grantRoles(strategyEmergencyAdmin, strategy11.EMERGENCY_ADMIN_ROLE());

        // Add 4 strategies to the vault
        vault.addStrategy(address(strategy1), 2250, type(uint72).max, 0, 0); // convex
        vault.addStrategy(address(strategy2), 2250, type(uint72).max, 0, 0); // yearn
        vault.addStrategy(address(strategy4), 2250, type(uint72).max, 0, 0); // st-eth-deposit turbo st-eth
        vault.addStrategy(address(strategy10), 2250, type(uint72).max, 0, 0); // turbo st-eth

        console2.log("***************************DEPLOYMENT ADDRESSES**********************************");
        console2.log("[MAXAPY] Vault :", address(vault));
        console2.log("[CONVEX] dETh-ETH Strategy:", address(strategy1));
        console2.log("[YEARN] WETH Strategy:", address(strategy2));
        console2.log("[SOMMELIER] Morpho Eth Maximizer Strategy:", address(strategy3));
        console2.log("[SOMMELIER] (StEth deposit) Turbo StETh Strategy:", address(strategy4));
        console2.log("[SOMMELIER] Turbo DivEth Strategy:", address(strategy5));
        console2.log("[SOMMELIER] Turbo:EethStrategy :", address(strategy6));
        console2.log("[SOMMELIER] Turbo EThX Strategy :", address(strategy7));
        console2.log("[SOMMELIER] Turbo EzEth Strategy :", address(strategy8));
        console2.log("[SOMMELIER] Turbo RsEth Strategy :", address(strategy9));
        console2.log("[SOMMELIER] Turbo StEth Strategy :", address(strategy10));
        console2.log("[SOMMELIER] Turbo SwEth Strategy :", address(strategy11));

        console2.log("***************************ADDED TO VAULT**********************************");
        console2.log("[CONVEX] dETh-ETH Strategy:", address(strategy1));
        console2.log("[YEARN] WETH Strategy:", address(strategy2));
        console2.log("[SOMMELIER] (StEth deposit) Turbo StETh Strategy:", address(strategy4));
        console2.log("[SOMMELIER] Turbo StEth Strategy :", address(strategy10));
    }
}
