// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { MaxApyHarvester } from "src/periphery/MaxApyHarvester.sol";
import "src/interfaces/IUniswap.sol";

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
        vaultUsdce.grantRoles(address(harvester), vaultUsdce.ADMIN_ROLE());

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

         // Add 13 strategies to the vault
        vaultUsdce.addStrategy(address(strategy1), 1900, type(uint72).max, 0, 0);  // -
        vaultUsdce.addStrategy(address(strategy2), 1900, type(uint72).max, 0, 0);  // -
        vaultUsdce.addStrategy(address(strategy3), 1900, type(uint72).max, 0, 0);  // -
        vaultUsdce.addStrategy(address(strategy4), 1900, type(uint72).max, 0, 0);  // -
        vaultUsdce.addStrategy(address(strategy5), 1900, type(uint72).max, 0, 0);  // -

        console2.log("***************************DEPLOYMENT ADDRESSES**********************************");
        console2.log("[MAXAPY] Router :", address(router));
        console2.log("[MAXAPY] Factory :", address(vaultFactory));
        console2.log("[MAXAPY] USDCE Vault :", address(vaultUsdce));
        console2.log("[YEARN] AjnaUSDC:", address(strategy1));
        console2.log("[YEARN] CompoundUSDCeLender:", address(strategy2));
        console2.log("[YEARN] MaticUSDCStaking:", address(strategy3));
        console2.log("[YEARN] USDCeLender:", address(strategy4));
        console2.log("[YEARN] USDCe:", address(strategy5));
        console2.log("[MAX_APY_HARVESTER]:", address(harvester));

        // Simulate setup
        setUpProtocol(deployerAddress);
    }

    function setUpProtocol(address deployerAddress) internal {
        IUniswapV3Router unirouter = IUniswapV3Router(0xE592427A0AEce92De3Edee1F18E0157C05861564);
        IWrappedToken wrapper = IWrappedToken(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

        uint256[10] memory pks = [
            0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80, 
            0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d,
            0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a,
            0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6,
            0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a,
            0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba,
            0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e,
            0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356,
            0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97,
            0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6
        ];

        address[10] memory accs = [ 
            0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            0x70997970C51812dc3A010C7d01b50e0d17dc79C8,
            0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC,
            0x90F79bf6EB2c4f870365E785982E1f101E93b906,
            0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65,
            0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc,
            0x976EA74026E726554dB657fA54763abd0C3a0aa9,
            0x14dC79964da2C08b23698B3D3cc7Ca32193d9955,
            0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f,
            0xa0Ee7A142d267C1f36714E4a8F75612F20a79720
        ];

        for(uint i = 0; i < pks.length-1; i++) {
            console2.log("Transfering: ", accs[i].balance/10**18, "WMATIC to deployer");
            vm.stopBroadcast(); 
            vm.startBroadcast(pks[i]);
            payable(deployerAddress).transfer(accs[i].balance - 1 ether);
        }

        vm.stopBroadcast(); 
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        uint256 amount =  500_000 ether; //matic

        console2.log("balance:", deployerAddress.balance/10**18, "WMATIC");
        console2.log("amount:", amount/10**18, "WMATIC");

        wrapper.deposit{value: amount}();
        wrapper.approve(address(unirouter), amount);

        unirouter.exactInputSingle{value: amount}(
            IUniswapV3Router.ExactInputSingleParams({
                tokenIn: WMATIC_POLYGON,
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
        console2.log("[balanceOf] deployer USDC.e",balanceUsdce/10**6);

        IERC20(USDCE_POLYGON).approve(address(vaultUsdce), type(uint256).max);
        vaultUsdce.deposit(balanceUsdce/2, address(1));

        vm.stopBroadcast();

        uint256 keeperPrivateKey = vm.envUint("KEEPER1_PRIVATE_KEY");
        vm.startBroadcast(keeperPrivateKey);

        // strategy1.harvest(0,0,address(vaultUsdce), type(uint256).max);
        // strategy2.harvest(0,0,address(vaultUsdce), type(uint256).max);
        // strategy3.harvest(0,0,address(vaultUsdce), type(uint256).max);
        // strategy4.harvest(0,0,address(vaultUsdce), type(uint256).max);
        // strategy5.harvest(0,0,address(vaultUsdce), type(uint256).max);

        // HARVESTER TEST
        MaxApyHarvester.HarvestData []memory harvestData = new MaxApyHarvester.HarvestData[](5);
        harvestData[0] = MaxApyHarvester.HarvestData(address(strategy1), 0, 0, block.timestamp + 1000);
        harvestData[1] = MaxApyHarvester.HarvestData(address(strategy2), 0, 0, block.timestamp + 1000);
        harvestData[2] = MaxApyHarvester.HarvestData(address(strategy3), 0, 0, block.timestamp + 1000);
        harvestData[3] = MaxApyHarvester.HarvestData(address(strategy4), 0, 0, block.timestamp + 1000);
        harvestData[4] = MaxApyHarvester.HarvestData(address(strategy5), 0, 0, block.timestamp + 1000);

        harvester.batchHarvests(harvestData);
    }
}
