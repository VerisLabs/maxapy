// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { MaxApyHarvester } from "src/periphery/MaxApyHarvester.sol";
import "src/interfaces/IUniswap.sol";

import "forge-std/Script.sol";
import "forge-std/Test.sol";
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

// +---------------------------+
// | HELPERS(FACTORY , ROUTER) |
// +---------------------------+
import { IWrappedToken } from "src/interfaces/IWrappedToken.sol";
import "src/helpers/AddressBook.sol";

/// @notice this is a simple test deployment of a polygon USDCe vault in a local rpc
contract PolygonDeploymentScript is Script, OwnableRoles {
    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////
    // **********STRATS******************
    // USDCE
    address constant strategy1 = 0x17365C38aDf84d3195B3470ce87493BFA75f28a9; // Yearn-Ajna USDC               |
        // YearnAjnaUSDC
    address constant strategy2 = 0x2719aeb131Ba2Fb7F8d35c5C684CD14fABF1F1f5; // Compound V3 USDC.e Lender     |
        // YearnCompoundUSDCeLender
    address constant strategy3 = 0x3243C319376696b61F1998C969e9d96529988C27; // Extra APR USDC (USDC.e)       |
        // YearnMaticUSDCStaking
    address constant strategy4 = 0xfEf651Fea0a20420dB94B86f9459e161320250C9; // Aave V3 USDC.e Lender         |
        // YearnUSDCeLender
    address constant strategy5 = 0x6Cf9d942185FEeE8608860859B5982CA4895Aa0b; // USDC.e                        |
        // YearnUSDCe

    address constant strategy6 = 0x3A2D48a58504333AA1021085F23cA38f85A7C43e; // Beefy - MAI/USDC.e            |
        // BeefyMaiUSDCeStrategy
    address constant strategy7 = 0xE2eB586C9ECA6C9838887Bd059449567b9E40C4e; // Convex - crvUSD+USDC          |
        // ConvexUSDCCrvUSDStrategy
    address constant strategy8 = 0x3fbC5a7dF84464997Bf7e92a970Ae324E8a07218; // Convex - crvUSD+USDT          |
        // ConvexUSDTCrvUSDStrategy
    address constant strategy9 = 0x6aC1B938401a0F41AbA07cB6bE8a3fadB6D280D8; // YearnV3 - USDT                |
        // YearnUSDTStrategy
    address constant strategy10 = 0xF21F0101c786C08e243c7aC216d0Dd57D1a27531; // YearnV3 - DAI                |
        // YearnDAIStrategy
    address constant strategy11 = 0xc30829f8Cc96114220194a2D29b9D44AB2c14285; // YearnV3 - Aave V3 DAI Lender |
        // YearnDAILenderStrategy

    // **********LOCAL VARIABLES*****************
    // use storage variables to avoid stack too deep
    MaxApyVault vaultUsdce = MaxApyVault(0xbc45ee5275fC1FaEB129b755C67fc6Fc992109DE);

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////

    function run() public {
        // use another private key here, dont use a keeper account for deployment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address payable deployerAddress = payable(vm.envAddress("DEPLOYER_ADDRESS"));
        uint256 adminPrivateKey = vm.envUint("ADMIN_PRIVATE_KEY");
        address payable adminAddress = payable(vm.envAddress("ADMIN_ADDRESS"));
        bool isFork = vm.envBool("FORK");

        if (isFork) {
            revert("fork setup, set isFork to FALSE!");
        }

        // Setup Protocol
        IUniswapV3Router unirouter = IUniswapV3Router(0xE592427A0AEce92De3Edee1F18E0157C05861564);
        IWrappedToken wrapped_pol = IWrappedToken(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

        vm.startBroadcast(deployerPrivateKey);
        uint256 amount = 1_500_000 ether; //matic

        console2.log("balance:", deployerAddress.balance / 10 ** 18);
        console2.log("amount:", amount / 10 ** 18);

        // transfer 10 eth to admin for gas
        adminAddress.transfer(10 ether);

        wrapped_pol.deposit{ value: amount }();
        wrapped_pol.approve(address(unirouter), amount);

        unirouter.exactInputSingle{ value: amount }(
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
        console2.log("[balanceOf] deployer USDCE", balanceUsdce / 10 ** 6);

        IERC20(USDCE_POLYGON).approve(address(vaultUsdce), type(uint256).max);
        vaultUsdce.deposit(balanceUsdce, deployerAddress);

        vm.stopBroadcast();
        vm.startBroadcast(adminPrivateKey);
        vaultUsdce.addStrategy(address(strategy1), 818, type(uint256).max, 0, 0);
        vaultUsdce.addStrategy(address(strategy2), 818, type(uint256).max, 0, 0);
        vaultUsdce.addStrategy(address(strategy3), 818, type(uint256).max, 0, 0);
        vaultUsdce.addStrategy(address(strategy4), 818, type(uint256).max, 0, 0);
        vaultUsdce.addStrategy(address(strategy5), 818, type(uint256).max, 0, 0);
        vaultUsdce.addStrategy(address(strategy6), 818, type(uint256).max, 0, 0);
        vaultUsdce.addStrategy(address(strategy8), 818, type(uint256).max, 0, 0);
        vaultUsdce.addStrategy(address(strategy9), 818, type(uint256).max, 0, 0);
        vaultUsdce.addStrategy(address(strategy10), 818, type(uint256).max, 0, 0);
        vaultUsdce.addStrategy(address(strategy11), 818, type(uint256).max, 0, 0);
        vm.stopBroadcast();
    }
}
