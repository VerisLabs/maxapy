// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { MaxApyHarvester } from "src/periphery/MaxApyHarvester.sol";
import "src/interfaces/IUniswap.sol";

import "forge-std/Script.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

import { IERC20, console2 } from "../../test/base/BaseTest.t.sol";
import { IStrategy } from "src/interfaces/IStrategy.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";
import { MaxApyVault, OwnableRoles } from "src/MaxApyVault.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { StrategyEvents } from "../../test/helpers/StrategyEvents.sol";
import { IUniswapV2Router02 as IRouter } from "src/interfaces/IUniswap.sol";

// +------------+
// | STRATEGIES |
// +------------+
// Yearn
import { YearnAjnaUSDCStrategy } from "src/strategies/polygon/USDCe/yearn/YearnAjnaUSDCStrategy.sol";
import { YearnCompoundUSDCeLenderStrategy } from "src/strategies/polygon/USDCe/yearn/YearnCompoundUSDCeLenderStrategy.sol";
import { YearnMaticUSDCStakingStrategy } from "src/strategies/polygon/USDCe/yearn/YearnMaticUSDCStakingStrategy.sol";
import { YearnUSDCeLenderStrategy } from "src/strategies/polygon/USDCe/yearn/YearnUSDCeLenderStrategy.sol";
import { YearnUSDCeStrategy } from "src/strategies/polygon/USDCe/yearn/YearnUSDCeStrategy.sol";
import { YearnUSDTStrategy }  from "src/strategies/polygon/USDCe/yearn/YearnUSDTStrategy.sol";
import { YearnDAIStrategy } from "src/strategies/polygon/USDCe/yearn/YearnDAIStrategy.sol";
import { YearnDAILenderStrategy } from "src/strategies/polygon/USDCe/yearn/YearnDAILenderStrategy.sol";

// Convex
import { ConvexUSDCCrvUSDStrategy } from "src/strategies/polygon/USDCe/convex/ConvexUSDCCrvUSDStrategy.sol";
import { ConvexUSDTCrvUSDStrategy } from "src/strategies/polygon/USDCe/convex/ConvexUSDTCrvUSDStrategy.sol";

// Beefy
import { BeefyMaiUSDCeStrategy } from "src/strategies/polygon/USDCe/beefy/BeefyMaiUSDCeStrategy.sol";

// +---------------------------+
// | HELPERS(FACTORY , ROUTER) |
// +---------------------------+
import { MaxApyRouter } from "src/MaxApyRouter.sol";

import { IWrappedToken } from "src/interfaces/IWrappedToken.sol";
import "src/helpers/AddressBook.sol";

/// @notice this is a simple test deployment of a polygon USDCe vault in a local rpc
contract PolygonDeploymentScript is Script, OwnableRoles {
    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////
    // **********STRATS******************
    // USDCE
    IStrategy public strategy1; // Yearn-Ajna USDC               | YearnAjnaUSDC 
    IStrategy public strategy2; // Compound V3 USDC.e Lender     | YearnCompoundUSDCeLender 
    IStrategy public strategy3; // Extra APR USDC (USDC.e)       | YearnMaticUSDCStaking 
    IStrategy public strategy4; // Aave V3 USDC.e Lender         | YearnUSDCeLender 
    IStrategy public strategy5; // USDC.e                        | YearnUSDCe 
    
    IStrategy public strategy6; // Beefy - MAI/USDC.e            | BeefyMaiUSDCeStrategy 
    IStrategy public strategy7; // Convex - crvUSD+USDC.e        | ConvexUSDCCrvUSDStrategy 
    IStrategy public strategy8; // Convex - crvUSD+USDT          | ConvexUSDTCrvUSDStrategy 
    IStrategy public strategy9; // YearnV3 - USDT                | YearnUSDTStrategy 
    IStrategy public strategy10; // YearnV3 - DAI                | YearnDAIStrategy 
    IStrategy public strategy11; // YearnV3 - Aave V3 DAI Lender | YearnDAILenderStrategy   

    // **********ROLES*******************
    address[] keepers;

    // **********LOCAL VARIABLES*****************
    // use storage variables to avoid stack too deep
    IMaxApyVault vaultUsdce;
    ITransparentUpgradeableProxy proxy;
    address vaultAdmin;
    address vaultEmergencyAdmin;
    address strategyAdmin;
    address strategyEmergencyAdmin;
    address treasury;
    MaxApyRouter router;
    address factoryAdmin;
    address factoryDeployer;

    MaxApyHarvester harvester;

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
        keepers.push(vaultAdmin);

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

        // Deploy harvester (multicall)
        harvester = new MaxApyHarvester(deployerAddress, keepers, keepers);
        keepers.push(address(harvester));

        /// Deploy MaxApyVault
        vaultUsdce = IMaxApyVault(0xbc45ee5275fC1FaEB129b755C67fc6Fc992109DE);

        // Strategy1(YearnAjnaUSDCStrategy)
        YearnAjnaUSDCStrategy strategy1 = YearnAjnaUSDCStrategy(0x17365C38aDf84d3195B3470ce87493BFA75f28a9);
       
        // Strategy2(YearnCompoundUSDCeLender)
        YearnCompoundUSDCeLenderStrategy strategy2 = YearnCompoundUSDCeLenderStrategy(0x2719aeb131Ba2Fb7F8d35c5C684CD14fABF1F1f5);

        // Strategy3(YearnMaticUSDCStakingStrategy)
        YearnMaticUSDCStakingStrategy strategy3 = YearnMaticUSDCStakingStrategy(0x3243C319376696b61F1998C969e9d96529988C27);

        // Strategy4(YearnUSDCeStrategy)
        YearnUSDCeStrategy strategy4 = YearnUSDCeStrategy(0xfEf651Fea0a20420dB94B86f9459e161320250C9);

        // Strategy5(YearnUSDCeLender)
        YearnUSDCeLenderStrategy strategy5 = YearnUSDCeLenderStrategy(0x6Cf9d942185FEeE8608860859B5982CA4895Aa0b);
        
        // Strategy6(BeefyMaiUSDCeStrategy)
        BeefyMaiUSDCeStrategy strategy6 = BeefyMaiUSDCeStrategy(0x3A2D48a58504333AA1021085F23cA38f85A7C43e);

        // Strategy7(crvUSD+USDC.e)
        ConvexUSDCCrvUSDStrategy strategy7 = ConvexUSDCCrvUSDStrategy(0xE2eB586C9ECA6C9838887Bd059449567b9E40C4e);

        // Strategy8(crvUSD+USDT)
        ConvexUSDTCrvUSDStrategy strategy8 = ConvexUSDTCrvUSDStrategy(0x3fbC5a7dF84464997Bf7e92a970Ae324E8a07218);

        // Strategy9(YearnV3 USDT)
        YearnUSDTStrategy strategy9 = YearnUSDTStrategy(0x6aC1B938401a0F41AbA07cB6bE8a3fadB6D280D8);

        // Strategy10(YearnV3 - DAI)
        YearnDAIStrategy strategy10 = YearnDAIStrategy(0xF21F0101c786C08e243c7aC216d0Dd57D1a27531);

        // Strategy11(YearnV3 - Aave V3 DAI Lender)
        YearnDAILenderStrategy strategy11 = YearnDAILenderStrategy(0xc30829f8Cc96114220194a2D29b9D44AB2c14285   ); 

        console2.log("***************************DEPLOYMENT ADDRESSES**********************************");
        console2.log("[MAXAPY] Router :", address(router));

        console2.log("[MAXAPY] USDCE Vault :", address(vaultUsdce));
        console2.log("[YEARN] AjnaUSDC:", address(strategy1));
        console2.log("[YEARN] CompoundUSDCeLender:", address(strategy2));
        console2.log("[YEARN] MaticUSDCStaking:", address(strategy3));
        console2.log("[YEARN] USDCeLender:", address(strategy4));
        console2.log("[YEARN] USDCe:", address(strategy5));
        console2.log("[BEEFY] BeefyMaiUSDCeStrategy:", address(strategy6));
        console2.log("[CONVEX] ConvexUSDCCrvUSDStrategy:", address(strategy7));
        console2.log("[CONVEX] ConvexUSDTCrvUSDStrategy:", address(strategy8));
        console2.log("[YEARN] YearnUSDTStrategy:", address(strategy9));
        console2.log("[YEARN] YearnDAIStrategy:", address(strategy10));
        console2.log("[YEARN] YearnDAILenderStrategy:", address(strategy11));

        console2.log("[MAX_APY_HARVESTER]:", address(harvester));
    }
}
