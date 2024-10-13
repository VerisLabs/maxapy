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
    address constant strategy1 = 0x17365C38aDf84d3195B3470ce87493BFA75f28a9; // Yearn-Ajna USDC | YearnAjnaUSDC 
    address constant strategy2 = 0x2719aeb131Ba2Fb7F8d35c5C684CD14fABF1F1f5; // Compound V3 USDC.e Lender     | YearnCompoundUSDCeLender 
    address constant strategy3 = 0x3243C319376696b61F1998C969e9d96529988C27; // Extra APR USDC (USDC.e)       | YearnMaticUSDCStaking 
    address constant strategy4 = 0xfEf651Fea0a20420dB94B86f9459e161320250C9; // Aave V3 USDC.e Lender         | YearnUSDCeLender 
    address constant strategy5 = 0x6Cf9d942185FEeE8608860859B5982CA4895Aa0b; // USDC.e                        | YearnUSDCe 
    
    address constant strategy6 = 0x3A2D48a58504333AA1021085F23cA38f85A7C43e; // Beefy - MAI/USDC.e            | BeefyMaiUSDCeStrategy 
    address constant strategy7 = 0xE2eB586C9ECA6C9838887Bd059449567b9E40C4e; // Convex - crvUSD+USDC.e        | ConvexUSDCCrvUSDStrategy 
    address constant strategy8 = 0x3fbC5a7dF84464997Bf7e92a970Ae324E8a07218; // Convex - crvUSD+USDT          | ConvexUSDTCrvUSDStrategy 
    address constant strategy9 = 0x6aC1B938401a0F41AbA07cB6bE8a3fadB6D280D8; // YearnV3 - USDT                | YearnUSDTStrategy 
    address constant strategy10 = 0xF21F0101c786C08e243c7aC216d0Dd57D1a27531; // YearnV3 - DAI                | YearnDAIStrategy
    address constant strategy11 = 0xc30829f8Cc96114220194a2D29b9D44AB2c14285; // YearnV3 - Aave V3 DAI Lender | YearnDAILenderStrategy   

    // **********ROLES*******************
    address[] keepers;

    // **********LOCAL VARIABLES*****************
    // use storage variables to avoid stack too deep
    MaxApyVault vaultUsdce = MaxApyVault(0xbc45ee5275fC1FaEB129b755C67fc6Fc992109DE);
    MaxApyHarvester harvester = MaxApyHarvester(payable(0x22B2a952Db13b9B326437a7AAc05345b071f179f));
    ITransparentUpgradeableProxy proxy;
    address vaultAdmin;
    address vaultEmergencyAdmin;
    address strategyAdmin;
    address strategyEmergencyAdmin;
    address treasury;
    MaxApyRouter router;
    address factoryAdmin;
    address factoryDeployer;


    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////

    function run() public {
        // use another private key here, dont use a keeper account for deployment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");                    

        vaultAdmin = vm.envAddress("VAULT_ADMIN_ADDRESS");

        vaultEmergencyAdmin = vm.envAddress("VAULT_EMERGENCY_ADMIN_ADDRESS");
        strategyAdmin = vm.envAddress("STRATEGY_ADMIN_ADDRESS");
        strategyEmergencyAdmin = vm.envAddress("STRATEGY_EMERGENCY_ADMIN_ADDRESS");
        factoryAdmin = vm.envAddress("FACTORY_ADMIN");
        factoryDeployer = vm.envAddress("FACTORY_DEPLOYER");
        treasury = vm.envAddress("TREASURY_ADDRESS_POLYGON");
        bool isFork = vm.envBool("FORK");

        if (isFork) {
            revert("fork setup, set isFork to FALSE!");
        }

        vm.startBroadcast(deployerPrivateKey);

        /// Deploy router
        router = new MaxApyRouter(IWrappedToken(USDCE_POLYGON));

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

        // Setup Protocol                                               
        IUniswapV3Router unirouter = IUniswapV3Router(0xE592427A0AEce92De3Edee1F18E0157C05861564);
        IWrappedToken wrapped_matic = IWrappedToken(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

        vm.stopBroadcast();                  
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        uint256 amount = 500_000 ether; //matic

        console2.log("balance:", deployerAddress.balance/10**18);
        console2.log("amount:", amount/10**18);

        wrapped_matic.deposit{value: amount}();
        wrapped_matic.approve(address(unirouter), amount);

        unirouter.exactInputSingle{value: amount}(
            IUniswapV3Router.ExactInputSingleParams({
                tokenIn: WPOL_POLYGON,
                tokenOut: USDCE_POLYGON,
                fee: 500,
                recipient: deployerAddress,
                deadline: block.timestamp + 1000,
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        uint256 balanceUsdce = IERC20(USDCE_POLYGON).balanceOf(deployerAddress);
        console2.log("[balanceOf] deployer USDCE", balanceUsdce/10**6);

        IERC20(USDCE_POLYGON).approve(address(vaultUsdce), type(uint256).max);
        vaultUsdce.deposit(balanceUsdce/2, address(1));

        vm.stopBroadcast();

        // MAXHARVESTER TEST
        vm.startBroadcast(vm.envUInt("ADMIN_PRIVATE_KEY"));             
        
        vaultUsdce.addStrategy(address(strategy1), 818, type(uint256).max, 0, 0);   
        vaultUsdce.addStrategy(address(strategy2), 818, type(uint256).max, 0, 0);
        vaultUsdce.addStrategy(address(strategy3), 818, type(uint256).max, 0, 0);
        vaultUsdce.addStrategy(address(strategy4), 818, type(uint256).max, 0, 0);
        vaultUsdce.addStrategy(address(strategy5), 818, type(uint256).max, 0, 0);
        vaultUsdce.addStrategy(address(strategy6), 818, type(uint256).max, 0, 0);
        vaultUsdce.addStrategy(address(strategy7), 818, type(uint256).max, 0, 0);
        vaultUsdce.addStrategy(address(strategy8), 818, type(uint256).max, 0, 0);
        vaultUsdce.addStrategy(address(strategy9), 818, type(uint256).max, 0, 0);
        vaultUsdce.addStrategy(address(strategy10), 818, type(uint256).max, 0, 0);
        vaultUsdce.addStrategy(address(strategy11), 818, type(uint256).max, 0, 0);
        
        vm.stopBroadcast();

        // > RUN FROM BACKEND!!!
        // WE DO NOT RUN THIS AS WE DO NOT HAVE THE PRIVATE KEY FOR KEEPER
        // vm.startBroadcast(0xfdf5B1aA4587fC02689d09A730fd80A72fdd940c);   

        // MaxApyHarvester.HarvestData []memory harvestData = new MaxApyHarvester.HarvestData[](11);                   
        // harvestData[0] = MaxApyHarvester.HarvestData(address(strategy1), 0, 0, block.timestamp + 1000);
        // harvestData[1] = MaxApyHarvester.HarvestData(address(strategy2), 0, 0, block.timestamp + 1000);
        // harvestData[2] = MaxApyHarvester.HarvestData(address(strategy3), 0, 0, block.timestamp + 1000);
        // harvestData[3] = MaxApyHarvester.HarvestData(address(strategy4), 0, 0, block.timestamp + 1000);
        // harvestData[4] = MaxApyHarvester.HarvestData(address(strategy5), 0, 0, block.timestamp + 1000);
        // harvestData[5] = MaxApyHarvester.HarvestData(address(strategy6), 0, 0, block.timestamp + 1000);
        // harvestData[6] = MaxApyHarvester.HarvestData(address(strategy7), 0, 0, block.timestamp + 1000);
        // harvestData[7] = MaxApyHarvester.HarvestData(address(strategy8), 0, 0, block.timestamp + 1000);
        // harvestData[8] = MaxApyHarvester.HarvestData(address(strategy9), 0, 0, block.timestamp + 1000);
        // harvestData[9] = MaxApyHarvester.HarvestData(address(strategy10), 0, 0, block.timestamp + 1000);
        // harvestData[10] = MaxApyHarvester.HarvestData(address(strategy11), 0, 0, block.timestamp + 1000);

        // harvester.batchHarvests(harvestData);
        // vm.stopBroadcast();                               
    }
}
