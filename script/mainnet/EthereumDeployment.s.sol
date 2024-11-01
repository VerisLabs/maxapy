// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "openzeppelin/proxy/transparent/ProxyAdmin.sol";

import {IERC20, console2} from "../../test/base/BaseTest.t.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {IMaxApyVault} from "src/interfaces/IMaxApyVault.sol";
import {MaxApyVault, OwnableRoles} from "src/MaxApyVault.sol";
import {StrategyData} from "src/helpers/VaultTypes.sol";
import {StrategyEvents} from "../../test/helpers/StrategyEvents.sol";
import {IUniswapV2Router02 as IRouter} from "src/interfaces/IUniswap.sol";

//// WETH
// Convex strategies
import {ConvexdETHFrxETHStrategy} from "src/strategies/mainnet/WETH/convex/ConvexdETHFrxETHStrategy.sol";
// Yearn strategies
import {YearnWETHStrategy} from "src/strategies/mainnet/WETH/yearn/YearnWETHStrategy.sol";
import {YearnCompoundV3WETHLenderStrategy} from "src/strategies/mainnet/WETH/yearn/YearnCompoundV3WETHLenderStrategy.sol";
import {YearnV3WETHStrategy} from "src/strategies/mainnet/WETH/yearn/YearnV3WETHStrategy.sol";
// Sommelier strategies
import {SommelierMorphoEthMaximizerStrategy} from "src/strategies/mainnet/WETH/sommelier/SommelierMorphoEthMaximizerStrategy.sol";
import {SommelierStEthDepositTurboStEthStrategy} from "src/strategies/mainnet/WETH/sommelier/SommelierStEthDepositTurboStEthStrategy.sol";
import {SommelierTurboDivEthStrategy} from "src/strategies/mainnet/WETH/sommelier/SommelierTurboDivEthStrategy.sol";
import {SommelierTurboEEthV2Strategy} from "src/strategies/mainnet/WETH/sommelier/SommelierTurboEEthV2Strategy.sol";
import {SommelierTurboEthXStrategy} from "src/strategies/mainnet/WETH/sommelier/SommelierTurboEthXStrategy.sol";
import {SommelierTurboEzEthStrategy} from "src/strategies/mainnet/WETH/sommelier/SommelierTurboEzEthStrategy.sol";
import {SommelierTurboRsEthStrategy} from "src/strategies/mainnet/WETH/sommelier/SommelierTurboRsEthStrategy.sol";
import {SommelierTurboStEthStrategy} from "src/strategies/mainnet/WETH/sommelier/SommelierTurboStEthStrategy.sol";
import {SommelierTurboSwEthStrategy} from "src/strategies/mainnet/WETH/sommelier/SommelierTurboSwEthStrategy.sol";
import "src/helpers/AddressBook.sol";

//// USDC
import {SommelierTurboGHOStrategy} from "src/strategies/mainnet/USDC/sommelier/SommelierTurboGHOStrategy.sol";
import {YearnLUSDStrategy} from "src/strategies/mainnet/USDC/yearn/YearnLUSDStrategy.sol";
import {YearnUSDCStrategy} from "src/strategies/mainnet/USDC/yearn/YearnUSDCStrategy.sol";

//// Helpers(Factory , Router)
import {MaxApyRouter} from "src/MaxApyRouter.sol";
import {MaxApyVaultFactory} from "src/MaxApyVaultFactory.sol";
import {MaxApyHarvester} from "src/periphery/MaxApyHarvester.sol";
import {IWrappedToken} from "src/interfaces/IWrappedToken.sol";

/// @notice this is a simple test deployment of a mainnet WETH vault in a local rpc
contract EthereumDeploymentScript is Script, OwnableRoles {
    ////////////////////////////////////////////////////////////////
    ///                      CONSTANTS                           ///
    ////////////////////////////////////////////////////////////////

    /// WETH
    IERC20 public constant crv = IERC20(CRV_MAINNET);
    IERC20 public constant cvx = IERC20(CVX_MAINNET);
    IERC20 public constant frxEth = IERC20(FRXETH_MAINNET);

    IRouter public constant SUSHISWAP_ROUTER =
        IRouter(SUSHISWAP_ROUTER_MAINNET);

    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////
    // **********STRATS******************
    // WETH
    IStrategy public strategy1; // dETH+frxETH
    IStrategy public strategy2; // WETH V2
    IStrategy public strategy3; // Morpho ETH Maximizer
    IStrategy public strategy4; // Turbo stETH (stETH Deposit)
    IStrategy public strategy5; // Turbo Ajna WETH
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
    IStrategy public strategy17; // crvUSDWETH

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
        address admin = 0x5c2B6ceC61c7A0741248445a14E62A3677C543b9;
        uint256 adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        keepers.push(vm.envAddress("KEEPER1_ADDRESS"));
        keepers.push(vm.envAddress("KEEPER2_ADDRESS"));

        vaultAdmin = vm.envAddress("VAULT_ADMIN_ADDRESS");
        vaultEmergencyAdmin = vm.envAddress("VAULT_EMERGENCY_ADMIN_ADDRESS");
        strategyAdmin = vm.envAddress("STRATEGY_ADMIN_ADDRESS");
        strategyEmergencyAdmin = vm.envAddress(
            "STRATEGY_EMERGENCY_ADMIN_ADDRESS"
        );
        factoryAdmin = vm.envAddress("FACTORY_ADMIN");
        factoryDeployer = vm.envAddress("FACTORY_DEPLOYER");
        treasury = vm.envAddress("TREASURY_ADDRESS");
        bool isFork = vm.envBool("FORK");

        if (isFork) {
            revert("fork setup");
        }

        vm.startBroadcast(deployerPrivateKey);

        /////////////////////////////// HELPERS ///////////////////////////
        MaxApyHarvester harvester = new MaxApyHarvester(admin, keepers);
        console.log("MaxApyHarvester deployed at:", address(harvester));

        vaultWeth = IMaxApyVault(0xA02aA8774E8C95F5105E33c2f73bdC87ea45BD29);
        vaultWeth.grantRoles(address(harvester), vaultWeth.ADMIN_ROLE());
        vaultUsdc = IMaxApyVault(0xE7FE898A1EC421f991B807288851241F91c7e376);
        vaultUsdc.grantRoles(address(harvester), vaultUsdc.ADMIN_ROLE());

        strategy1 = IStrategy(0x73a84b35E15c4c6309E9A237f677F109cc47c4F2);
        strategy1.grantRoles(address(harvester), strategy1.KEEPER_ROLE());
        strategy2 = IStrategy(0x862be55A3Eab69A964153717760E536E51d7670F);
        strategy2.grantRoles(address(harvester), strategy2.KEEPER_ROLE());
        strategy3 = IStrategy(0xB753B428732F2F5bB28219FcA3cD231b652C8B92);
        strategy3.grantRoles(address(harvester), strategy3.KEEPER_ROLE());
        strategy4 = IStrategy(0xcB6C0036c25b9E8171E7434A9b60D63AE2ad7633);
        strategy4.grantRoles(address(harvester), strategy4.KEEPER_ROLE());
        strategy5 = IStrategy(0x5d5881D238f590fBcf4F158DE0C1599ac5db2533);
        strategy5.grantRoles(address(harvester), strategy5.KEEPER_ROLE());
        strategy6 = IStrategy(0x3baa38bF86374050DeB949AD490b321Bcb74208d);
        strategy6.grantRoles(address(harvester), strategy6.KEEPER_ROLE());
        strategy7 = IStrategy(0x2996b347e616E37B511Fd983Bc177eF9Ea804354);
        strategy7.grantRoles(address(harvester), strategy7.KEEPER_ROLE());
        strategy8 = IStrategy(0x2488cfAa3b8dF8707b9EB715FF508561533E2356);
        strategy8.grantRoles(address(harvester), strategy8.KEEPER_ROLE());
        strategy9 = IStrategy(0x5Bb53F3aBF5744A26e5e458f4c74338af724A174);
        strategy9.grantRoles(address(harvester), strategy9.KEEPER_ROLE());
        strategy10 = IStrategy(0x47B22B910496eA557548733B06B7BB49245D2eeF);
        strategy10.grantRoles(address(harvester), strategy10.KEEPER_ROLE());
        strategy11 = IStrategy(0x5dA1914b0107107A7AE1Ed5A8768d21CE1cEf6E9);
        strategy11.grantRoles(address(harvester), strategy11.KEEPER_ROLE());
        strategy12 = IStrategy(0x18fc9545005587d403deD6B643D3172522FB0367);
        strategy12.grantRoles(address(harvester), strategy12.KEEPER_ROLE());
        strategy13 = IStrategy(0xa34c2F8fd94bD42B9D66A7dDcd9adF8BE971bdF8);
        strategy13.grantRoles(address(harvester), strategy13.KEEPER_ROLE());
        strategy14 = IStrategy(0x7875C1D4c1C16c656EB526fd76aB3cb180D1e64f);
        strategy14.grantRoles(address(harvester), strategy14.KEEPER_ROLE());
    }
}
