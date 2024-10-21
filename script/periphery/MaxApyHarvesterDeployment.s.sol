// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import { MaxApyHarvester } from "../../src/periphery/MaxApyHarvester.sol";
import { IMaxApyVault } from "../../src/interfaces/IMaxApyVault.sol";
import { IStrategy } from "../../src/interfaces/IStrategy.sol";

contract MaxApyHarvesterDeployment is Script {
    IMaxApyVault public vault;

    IStrategy strategy1 = IStrategy(0x17365C38aDf84d3195B3470ce87493BFA75f28a9); // Yearn-Ajna USDC               |
        // YearnAjnaUSDC
    IStrategy strategy2 = IStrategy(0x2719aeb131Ba2Fb7F8d35c5C684CD14fABF1F1f5); // Compound V3 USDC.e Lender     |
        // YearnCompoundUSDCeLender
    IStrategy strategy3 = IStrategy(0x3243C319376696b61F1998C969e9d96529988C27); // Extra APR USDC (USDC.e)       |
        // YearnMaticUSDCStaking
    IStrategy strategy4 = IStrategy(0xfEf651Fea0a20420dB94B86f9459e161320250C9); // Aave V3 USDC.e Lender         |
        // YearnUSDCeLender
    IStrategy strategy5 = IStrategy(0x6Cf9d942185FEeE8608860859B5982CA4895Aa0b); // USDC.e                        |
        // YearnUSDCe

    IStrategy strategy6 = IStrategy(0x3A2D48a58504333AA1021085F23cA38f85A7C43e); // Beefy - MAI/USDC.e            |
        // BeefyMaiUSDCeStrategy
    IStrategy strategy7 = IStrategy(0xE2eB586C9ECA6C9838887Bd059449567b9E40C4e); // Convex - crvUSD+USDC          |
        // ConvexUSDCCrvUSDStrategy
    IStrategy strategy8 = IStrategy(0x3fbC5a7dF84464997Bf7e92a970Ae324E8a07218); // Convex - crvUSD+USDT          |
        // ConvexUSDTCrvUSDStrategy
    IStrategy strategy9 = IStrategy(0x6aC1B938401a0F41AbA07cB6bE8a3fadB6D280D8); // YearnV3 - USDT                |
        // YearnUSDTStrategy
    IStrategy strategy10 = IStrategy(0xF21F0101c786C08e243c7aC216d0Dd57D1a27531); // YearnV3 - DAI                |
        // YearnDAIStrategy
    IStrategy strategy11 = IStrategy(0xc30829f8Cc96114220194a2D29b9D44AB2c14285); // YearnV3 - Aave V3 DAI Lender |
        // YearnDAILenderStrategy

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address admin = vm.envAddress("DEPLOYER_ADDRESS");

        address[] memory keepers = new address[](2);
        keepers[0] = vm.envAddress("KEEPER1_ADDRESS"); // harvester address
        keepers[1] = vm.envAddress("KEEPER2_ADDRESS"); // allocator address

        MaxApyHarvester harvester = new MaxApyHarvester(admin, keepers);

        console.log("MaxApyHarvester deployed at:", address(harvester));

        vault = IMaxApyVault(0xbc45ee5275fC1FaEB129b755C67fc6Fc992109DE);
        vault.grantRoles(address(harvester), vault.ADMIN_ROLE());

        strategy1.grantRoles(address(harvester), strategy1.KEEPER_ROLE());
        strategy2.grantRoles(address(harvester), strategy2.KEEPER_ROLE());
        strategy3.grantRoles(address(harvester), strategy3.KEEPER_ROLE());
        strategy4.grantRoles(address(harvester), strategy4.KEEPER_ROLE());
        strategy5.grantRoles(address(harvester), strategy5.KEEPER_ROLE());
        strategy6.grantRoles(address(harvester), strategy6.KEEPER_ROLE());
        strategy7.grantRoles(address(harvester), strategy7.KEEPER_ROLE());
        strategy8.grantRoles(address(harvester), strategy8.KEEPER_ROLE());
        strategy9.grantRoles(address(harvester), strategy9.KEEPER_ROLE());
        strategy10.grantRoles(address(harvester), strategy10.KEEPER_ROLE());
        strategy11.grantRoles(address(harvester), strategy11.KEEPER_ROLE());

        vm.stopBroadcast();
    }
}
