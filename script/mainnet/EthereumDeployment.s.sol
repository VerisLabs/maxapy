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

//// WETH
// Convex strategies
import { ConvexdETHFrxETHStrategy } from "src/strategies/mainnet/WETH/convex/ConvexdETHFrxETHStrategy.sol";
// Yearn strategies
import { YearnWETHStrategy } from "src/strategies/mainnet/WETH/yearn/YearnWETHStrategy.sol";
import { YearnCompoundV3WETHLenderStrategy } from
    "src/strategies/mainnet/WETH/yearn/YearnCompoundV3WETHLenderStrategy.sol";
import { YearnV3WETHStrategy } from "src/strategies/mainnet/WETH/yearn/YearnV3WETHStrategy.sol";
// Sommelier strategies
import { SommelierMorphoEthMaximizerStrategy } from
    "src/strategies/mainnet/WETH/sommelier/SommelierMorphoEthMaximizerStrategy.sol";
import { SommelierStEthDepositTurboStEthStrategy } from
    "src/strategies/mainnet/WETH/sommelier/SommelierStEthDepositTurboStEthStrategy.sol";
import { SommelierTurboDivEthStrategy } from "src/strategies/mainnet/WETH/sommelier/SommelierTurboDivEthStrategy.sol";
import { SommelierTurboEEthV2Strategy } from "src/strategies/mainnet/WETH/sommelier/SommelierTurboEEthV2Strategy.sol";
import { SommelierTurboEthXStrategy } from "src/strategies/mainnet/WETH/sommelier/SommelierTurboEthXStrategy.sol";
import { SommelierTurboEzEthStrategy } from "src/strategies/mainnet/WETH/sommelier/SommelierTurboEzEthStrategy.sol";
import { SommelierTurboRsEthStrategy } from "src/strategies/mainnet/WETH/sommelier/SommelierTurboRsEthStrategy.sol";
import { SommelierTurboStEthStrategy } from "src/strategies/mainnet/WETH/sommelier/SommelierTurboStEthStrategy.sol";
import { SommelierTurboSwEthStrategy } from "src/strategies/mainnet/WETH/sommelier/SommelierTurboSwEthStrategy.sol";
import "src/helpers/AddressBook.sol";

//// USDC
import { SommelierTurboGHOStrategy } from "src/strategies/mainnet/USDC/sommelier/SommelierTurboGHOStrategy.sol";
import { YearnLUSDStrategy } from "src/strategies/mainnet/USDC/yearn/YearnLUSDStrategy.sol";
import { YearnUSDCStrategy } from "src/strategies/mainnet/USDC/yearn/YearnUSDCStrategy.sol";

//// Helpers(Factory , Router)
import { MaxApyRouter } from "src/MaxApyRouter.sol";
import { MaxApyVaultFactory } from "src/MaxApyVaultFactory.sol";

import { IWrappedToken } from "src/interfaces/IWrappedToken.sol";

/// @notice this is a simple test deployment of a mainnet WETH vault in a local rpc
contract EthereumDeploymentScript is Script, OwnableRoles {
    ////////////////////////////////////////////////////////////////
    ///                      CONSTANTS                           ///
    ////////////////////////////////////////////////////////////////

    /// WETH
    IERC20 public constant crv = IERC20(CRV_MAINNET);
    IERC20 public constant cvx = IERC20(CVX_MAINNET);
    IERC20 public constant frxEth = IERC20(FRXETH_MAINNET);

    IRouter public constant SUSHISWAP_ROUTER = IRouter(SUSHISWAP_ROUTER_MAINNET);

    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////
    // **********STRATS******************
    // WETH
    IStrategy public strategy1; // dETH+frxETH
    IStrategy public strategy2; // WETH V2
    IStrategy public strategy3; // Morpho ETH Maximizer
    IStrategy public strategy4; // Turbo stETH (stETH Deposit)
    IStrategy public strategy5; // Turbo divETH
    IStrategy public strategy6; // Turbo eETH V2
    IStrategy public strategy7; // Turbo ezETH
    IStrategy public strategy8; // Turbo rsETH
    IStrategy public strategy9; // Turbo stETH
    IStrategy public strategy10; // Turbo swETH
    IStrategy public strategy11; // Turbo ETHx
    IStrategy public strategy12; // Yearn - Compound V3 WETH Lender
    IStrategy public strategy13; // WETH V3

    // USDC
    IStrategy public strategy14; // Turbo GHO
    IStrategy public strategy15; // LUSD
    IStrategy public strategy16; // USDC

    // **********ROLES*******************
    address[] keepers;

    // **********LOCAL VARIABLES*****************
    // use storage variables to avoid stack too deep
    IMaxApyVault vaultWeth;
    IMaxApyVault vaultUsdc;
    ITransparentUpgradeableProxy proxy;
    ProxyAdmin proxyAdmin;
    address vaultAdmin;
    address vaultEmergencyAdmin;
    address strategyAdmin;
    address strategyEmergencyAdmin;
    address treasury;
    address vaultDeployment;
    address factoryAdmin;
    address factoryDeployer;
    address deployerAddress;
    MaxApyRouter router;
    MaxApyVaultFactory vaultFactory;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////

    function run() public {
        // use another private key here, dont use a keeper account for deployment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        keepers.push(vm.envAddress("KEEPER1_ADDRESS"));
        keepers.push(vm.envAddress("KEEPER2_ADDRESS"));
        keepers.push(vm.envAddress("KEEPER3_ADDRESS"));

        vaultAdmin = vm.envAddress("VAULT_ADMIN_ADDRESS");
        vaultEmergencyAdmin = vm.envAddress("VAULT_EMERGENCY_ADMIN_ADDRESS");
        strategyAdmin = vm.envAddress("STRATEGY_ADMIN_ADDRESS");
        strategyEmergencyAdmin = vm.envAddress("STRATEGY_EMERGENCY_ADMIN_ADDRESS");
        factoryAdmin = vm.envAddress("FACTORY_ADMIN");
        factoryDeployer = vm.envAddress("FACTORY_DEPLOYER");
        treasury = vm.envAddress("TREASURY_ADDRESS");
        bool isFork = vm.envBool("FORK");

        if (isFork) {
            revert("fork setup");
        }

        vm.startBroadcast(deployerPrivateKey);

        /////////////////////////////// HELPERS ///////////////////////////

        /// Deploy router
        router = new MaxApyRouter(IWrappedToken(WETH_MAINNET));

        /// Deploy factory and MaxApyVault
        vaultFactory = new MaxApyVaultFactory(treasury);
        vaultFactory.grantRoles(factoryAdmin, vaultFactory.ADMIN_ROLE());
        vaultFactory.grantRoles(factoryDeployer, vaultFactory.DEPLOYER_ROLE());

        /////////////////////////////// WETH ///////////////////////////
        _deployWethStrategies();
        /////////////////////////////// USDC ///////////////////////////
        //_deployUsdcStrategies();
        /////////////////////////////// Post-Deployment//////////////////////
        _log();
    }

    function _deployUsdcStrategies() private {
        /// Deploy MaxApyVault
        vaultDeployment = vaultFactory.deploy(address(USDC_MAINNET), deployerAddress, "Max APY USDC");

        vaultUsdc = IMaxApyVault(address(vaultDeployment));
        // grant roles
        vaultUsdc.grantRoles(vaultAdmin, vaultUsdc.ADMIN_ROLE());
        vaultUsdc.grantRoles(vaultEmergencyAdmin, vaultUsdc.EMERGENCY_ADMIN_ROLE());

        // Deploy strategy14(Sommelier TurboGHO)
        SommelierTurboGHOStrategy implementation14 = new SommelierTurboGHOStrategy();
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation14),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultUsdc),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier TurboGHO")),
                strategyAdmin,
                SOMMELIER_TURBO_GHO_CELLAR_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy14 = IStrategy(address(_proxy));
        strategy14.grantRoles(strategyAdmin, strategy14.ADMIN_ROLE());
        strategy14.grantRoles(strategyEmergencyAdmin, strategy14.EMERGENCY_ADMIN_ROLE());

        // Deploy strategy15(Yearn LUSD)
        YearnLUSDStrategy implementation15 = new YearnLUSDStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation15),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultUsdc),
                keepers,
                bytes32(abi.encode("MaxApy Yearn LUSD")),
                strategyAdmin,
                YEARN_LUSD_YVAULT_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy15 = IStrategy(address(_proxy));
        strategy15.grantRoles(strategyAdmin, strategy15.ADMIN_ROLE());
        strategy15.grantRoles(strategyEmergencyAdmin, strategy15.EMERGENCY_ADMIN_ROLE());

        // Deploy strategy16(Yearn USDC )
        YearnUSDCStrategy implementation16 = new YearnUSDCStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation16),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultUsdc),
                keepers,
                bytes32(abi.encode("MaxApy Yearn USDC")),
                strategyAdmin,
                YEARN_USDC_YVAULT_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy16 = IStrategy(address(_proxy));
        strategy16.grantRoles(strategyAdmin, strategy16.ADMIN_ROLE());
        strategy16.grantRoles(strategyEmergencyAdmin, strategy16.EMERGENCY_ADMIN_ROLE());
    }

    function _deployWethStrategies() private {
        /// Deploy MaxApyVault
        vaultDeployment = vaultFactory.deploy(WETH_MAINNET, deployerAddress, "Max APY WETH");
        vaultWeth = IMaxApyVault(address(vaultDeployment));
        // grant roles
        vaultWeth.grantRoles(vaultAdmin, vaultWeth.ADMIN_ROLE());
        vaultWeth.grantRoles(vaultEmergencyAdmin, vaultWeth.EMERGENCY_ADMIN_ROLE());

        // Deploy strategy1 (Convex) dETH+frxETH
        ConvexdETHFrxETHStrategy implementation1 = new ConvexdETHFrxETHStrategy();
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation1),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address,address)",
                address(vaultWeth),
                keepers,
                strategyAdmin,
                bytes32(abi.encode("MaxApy dETH<>frxETH")),
                CURVE_DETH_FRXETH_POOL_MAINNET,
                CURVE_ETH_FRXETH_POOL_MAINNET,
                address(SUSHISWAP_ROUTER)
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy1 = IStrategy(address(_proxy));
        strategy1.grantRoles(strategyAdmin, strategy1.ADMIN_ROLE());
        strategy1.grantRoles(strategyEmergencyAdmin, strategy1.EMERGENCY_ADMIN_ROLE());

        // Deploy strategy2 (Yearn WETH V2)
        YearnWETHStrategy implementation2 = new YearnWETHStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation2),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultWeth),
                keepers,
                bytes32(abi.encode("MaxApy Yearn WETH V2")),
                strategyAdmin,
                YEARN_WETH_YVAULT_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy2 = IStrategy(address(_proxy));
        strategy2.grantRoles(strategyAdmin, strategy2.ADMIN_ROLE());
        strategy2.grantRoles(strategyEmergencyAdmin, strategy2.EMERGENCY_ADMIN_ROLE());

        // Deploy strategy3(Morpho Eth maximizer)
        SommelierMorphoEthMaximizerStrategy implementation3 = new SommelierMorphoEthMaximizerStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation3),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultWeth),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier TurboMorphoETH")),
                strategyAdmin,
                SOMMELIER_MORPHO_ETH_MAXIMIZER_CELLAR_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy3 = IStrategy(address(_proxy));
        strategy3.grantRoles(strategyAdmin, strategy3.ADMIN_ROLE());
        strategy3.grantRoles(strategyEmergencyAdmin, strategy3.EMERGENCY_ADMIN_ROLE());

        // Deploy strategy4(StEthDeposit)
        SommelierStEthDepositTurboStEthStrategy implementation4 = new SommelierStEthDepositTurboStEthStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation4),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultWeth),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier(StEth deposit) Turbo StEth")),
                strategyAdmin,
                SOMMELIER_ST_ETH_DEPOSIT_TURBO_STETH_CELLAR_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy4 = IStrategy(address(_proxy));
        strategy4.grantRoles(strategyAdmin, strategy4.ADMIN_ROLE());
        strategy4.grantRoles(strategyEmergencyAdmin, strategy4.EMERGENCY_ADMIN_ROLE());

        // Deploy strategy5(DivEth)
        SommelierTurboDivEthStrategy implementation5 = new SommelierTurboDivEthStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation5),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultWeth),
                keepers,
                bytes32(abi.encode("MaxApy TurboDivEth")),
                strategyAdmin,
                SOMMELIER_TURBO_DIV_ETH_CELLAR_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy5 = IStrategy(address(_proxy));
        strategy5.grantRoles(strategyAdmin, strategy5.ADMIN_ROLE());
        strategy5.grantRoles(strategyEmergencyAdmin, strategy5.EMERGENCY_ADMIN_ROLE());

        // Deploy strategy6(EEth)
        SommelierTurboEEthV2Strategy implementation6 = new SommelierTurboEEthV2Strategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation6),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultWeth),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier TurboEEth")),
                strategyAdmin,
                SOMMELIER_TURBO_EETHV2_CELLAR_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy6 = IStrategy(address(_proxy));
        strategy6.grantRoles(strategyAdmin, strategy6.ADMIN_ROLE());
        strategy6.grantRoles(strategyEmergencyAdmin, strategy6.EMERGENCY_ADMIN_ROLE());

        // Deploy strategy7(ezETH)
        SommelierTurboEzEthStrategy implementation7 = new SommelierTurboEzEthStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation7),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultWeth),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier TurboEzEth")),
                strategyAdmin,
                SOMMELIER_TURBO_EZETH_CELLAR_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy7 = IStrategy(address(_proxy));
        strategy7.grantRoles(strategyAdmin, strategy7.ADMIN_ROLE());
        strategy7.grantRoles(strategyEmergencyAdmin, strategy7.EMERGENCY_ADMIN_ROLE());

        // Deploy strategy8(rsEth)
        SommelierTurboRsEthStrategy implementation8 = new SommelierTurboRsEthStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation8),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultWeth),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier TurboRsETh")),
                strategyAdmin,
                SOMMELIER_TURBO_RSETH_CELLAR_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy8 = IStrategy(address(_proxy));
        strategy8.grantRoles(strategyAdmin, strategy8.ADMIN_ROLE());
        strategy8.grantRoles(strategyEmergencyAdmin, strategy8.EMERGENCY_ADMIN_ROLE());

        // Deploy strategy9(stEth)
        SommelierTurboStEthStrategy implementation9 = new SommelierTurboStEthStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation9),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultWeth),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier TutboStEth")),
                strategyAdmin,
                SOMMELIER_TURBO_STETH_CELLAR_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy9 = IStrategy(address(_proxy));
        strategy9.grantRoles(strategyAdmin, strategy9.ADMIN_ROLE());
        strategy9.grantRoles(strategyEmergencyAdmin, strategy9.EMERGENCY_ADMIN_ROLE());

        // Deploy strategy10(SwEth)
        SommelierTurboSwEthStrategy implementation10 = new SommelierTurboSwEthStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation10),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultWeth),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier TutboSwEth")),
                strategyAdmin,
                SOMMELIER_TURBO_SWETH_CELLAR_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy10 = IStrategy(address(_proxy));
        strategy10.grantRoles(strategyAdmin, strategy10.ADMIN_ROLE());
        strategy10.grantRoles(strategyEmergencyAdmin, strategy10.EMERGENCY_ADMIN_ROLE());

        // Deploy strategy11(Turbo ETHx)
        SommelierTurboEthXStrategy implementation11 = new SommelierTurboEthXStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation11),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultWeth),
                keepers,
                bytes32(abi.encode("MaxApy Sommelier TutboEthx")),
                strategyAdmin,
                SOMMELIER_TURBO_EETHX_CELLAR_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy11 = IStrategy(address(_proxy));
        strategy11.grantRoles(strategyAdmin, strategy11.ADMIN_ROLE());
        strategy11.grantRoles(strategyEmergencyAdmin, strategy11.EMERGENCY_ADMIN_ROLE());

        // Deploy strategy12(Yearn Compound V3 WETH Lender)
        YearnCompoundV3WETHLenderStrategy implementation12 = new YearnCompoundV3WETHLenderStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation12),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultWeth),
                keepers,
                bytes32(abi.encode("MaxApy Yearn CompoundV3WETHLender")),
                strategyAdmin,
                YEARN_COMPOUND_V3_WETH_LENDER_YVAULT_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy12 = IStrategy(address(_proxy));
        strategy12.grantRoles(strategyAdmin, strategy12.ADMIN_ROLE());
        strategy12.grantRoles(strategyEmergencyAdmin, strategy12.EMERGENCY_ADMIN_ROLE());

        // Deploy strategy13(Yearn WETH V3)
        YearnV3WETHStrategy implementation13 = new YearnV3WETHStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation13),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultWeth),
                keepers,
                bytes32(abi.encode("MaxApy YearnV3 WETH")),
                strategyAdmin,
                YEARNV3_WETH_YVAULT_MAINNET
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy13 = IStrategy(address(_proxy));
        strategy13.grantRoles(strategyAdmin, strategy13.ADMIN_ROLE());
        strategy13.grantRoles(strategyEmergencyAdmin, strategy13.EMERGENCY_ADMIN_ROLE());
    }

    function _log() private {
        console2.log("***************************DEPLOYMENT ADDRESSES**********************************");
        console2.log("[MAXAPY] Router :", address(router));
        console2.log("[MAXAPY] Factory :", address(vaultFactory));
        console2.log("[MAXAPY] WETH Vault :", address(vaultWeth));
        console2.log("[CONVEX] dETh-ETH Strategy:", address(strategy1));
        console2.log("[YEARN] WETH V2 Strategy:", address(strategy2));
        console2.log("[SOMMELIER] Morpho ETH Maximizer Strategy:", address(strategy3));
        console2.log("[SOMMELIER] Turbo stETH Strategy:", address(strategy4));
        console2.log("[SOMMELIER] Turbo divETH Strategy:", address(strategy5));
        console2.log("[SOMMELIER] Turbo eETH V2 Strategy:", address(strategy6));
        console2.log("[SOMMELIER] Turbo ezETH Strategy:", address(strategy7));
        console2.log("[SOMMELIER] Turbo rsETH Strategy:", address(strategy8));
        console2.log("[SOMMELIER] Turbo stETH Strategy:", address(strategy9));
        console2.log("[SOMMELIER] Turbo swETH Strategy:", address(strategy10));
        console2.log("[SOMMELIER] Turbo ETHx Strategy:", address(strategy11));
        console2.log("[YEARN] Compound V3 WETH Lender Strategy:", address(strategy12));
        console2.log("[YEARN] WETH V3 Strategy:", address(strategy13));

        console2.log("[MAXAPY] USDC Vault :", address(vaultUsdc));
        console2.log("[SOMMELIER] Turbo GHO :", address(strategy14));
        console2.log("[YEARN] LUSD Vault :", address(strategy15));
        console2.log("[YEARN] USDC Vault :", address(strategy16));
    }
}
