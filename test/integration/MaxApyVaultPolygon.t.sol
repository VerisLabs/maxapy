// SPDX-Licence-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "../helpers/Tokens.sol";

import { StrategyData } from "src/helpers/VaultTypes.sol";

import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";

import { BaseTest, IERC20, Vm, console2 } from "../base/BaseTest.t.sol";
import { IStrategyWrapper } from "../interfaces/IStrategyWrapper.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";
import { MaxApyVault } from "src/MaxApyVault.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { StrategyEvents } from "../helpers/StrategyEvents.sol";
import { ICurveLpPool } from "src/interfaces/ICurve.sol";
import { IUniswapV2Router02 as IRouter } from "src/interfaces/IUniswap.sol";

import { ConvexdETHFrxETHStrategyWrapper } from "../mock/ConvexdETHFrxETHStrategyWrapper.sol";
import { ConvexdETHFrxETHStrategyEvents } from "../helpers/ConvexdETHFrxETHStrategyEvents.sol";

import { SommelierMorphoEthMaximizerStrategyWrapper } from "../mock/SommelierMorphoEthMaximizerStrategyWrapper.sol";
import { SommelierMorphoEthMaximizerStrategy } from
    "src/strategies/mainnet/WETH/sommelier/SommelierMorphoEthMaximizerStrategy.sol";

import { SommelierTurboStEthStrategy } from "src/strategies/mainnet/WETH/sommelier/SommelierTurboStEthStrategy.sol";
import { SommelierTurboStEthStrategyWrapper } from "../mock/SommelierTurboStEthStrategyWrapper.sol";

import { SommelierStEthDepositTurboStEthStrategyWrapper } from
    "../mock/SommelierStEthDepositTurboStEthStrategyWrapper.sol";

import { YearnWETHStrategyWrapper } from "../mock/YearnWETHStrategyWrapper.sol";
import { MockRevertingStrategy } from "../mock/MockRevertingStrategy.sol";
import "src/helpers/AddressBook.sol";

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
import { YearnDAIStrategy} from "src/strategies/polygon/USDCe/yearn/YearnDAIStrategy.sol";

//// Helpers(Factory , Router)f
import { MaxApyRouter } from "src/MaxApyRouter.sol";
import { MaxApyVaultFactory } from "src/MaxApyVaultFactory.sol";

import { IWrappedToken } from "src/interfaces/IWrappedToken.sol";
import "src/helpers/AddressBook.sol";

contract MaxApyVaultPolygonIntegrationTest is BaseTest, StrategyEvents {
    // USDCE
    IStrategy public strategy1; // YeearnAjnaUSDC
    IStrategy public strategy2; // YearnCompoundUSDCeLender
    IStrategy public strategy3; // YearnMaticUSDCStraking
    IStrategy public strategy4; // YearnUSDCeLender
    IStrategy public strategy5; // YearnUSDCe
    IStrategy public strategy6; // YearnDAI

    address[] strategyAddresses;
    address[] public keepers;
    address public TREASURY;

    // Local Variables
    IMaxApyVault vaultUsdce;
    ITransparentUpgradeableProxy proxy;
    ProxyAdmin proxyAdmin;
    
    address treasury;
    address vaultDeployment;    
    address factoryAdmin;
    address factoryDeployer;

    MaxApyRouter router;
    MaxApyVaultFactory vaultFactory;
    MaxApyHarvester harvester;

    function logStatus(address strategyAddress) internal {
        StrategyData memory data = vaultUsdce.strategies(strategyAddress);

        console2.log("");
        console2.log(strategyAddress);
        console2.log("debt ratio:",data.strategyDebtRatio);
        console2.log("total debt:", data.strategyTotalDebt);
        console2.log("uPnL:", data.strategyTotalUnrealizedGain);
        console2.log("unharvested:", IStrategy(strategyAddress).unharvestedAmount());
        console2.log("unharvested: $", IStrategy(strategyAddress).unharvestedAmount()/10**6);
    }

    function logStatusAllStrategies() internal {
        for(uint256 i=0; i<6; ++i) logStatus(strategyAddresses[i]);
        console2.log("*********************************************************************************");
    }

    function setUp() public {
        super._setUp("POLYGON");
        TREASURY = makeAddr("treasury");

        // Grant keeper roles
        keepers.push(users.alice);
        keepers.push(address(harvester));

        // Deploy router
        router = new MaxApyRouter(IWrappedToken(USDCE_POLYGON));

        // Deploy harvester (multicall)
        harvester = new MaxApyHarvester(users.alice, keepers, keepers);
        keepers.push(address(harvester));

        /// Deploy factory and MaxApyVault
        vaultFactory = new MaxApyVaultFactory(treasury);
        vaultFactory.grantRoles(users.alice, vaultFactory.ADMIN_ROLE());
        vaultFactory.grantRoles(users.alice, vaultFactory.DEPLOYER_ROLE());

        /// Deploy MaxApyVault
        vaultDeployment = vaultFactory.deploy(address(USDCE_POLYGON), users.alice, "Max APY");
        vaultUsdce = IMaxApyVault(address(vaultDeployment));

        // grant roles
        vaultUsdce.grantRoles(users.alice, vaultUsdce.ADMIN_ROLE());
        vaultUsdce.grantRoles(address(harvester), vaultUsdce.ADMIN_ROLE());

        vaultUsdce.grantRoles(users.alice, vaultUsdce.EMERGENCY_ADMIN_ROLE());
        vaultUsdce.grantRoles(address(harvester), vaultUsdce.ADMIN_ROLE());
        
        /// Deploy transparent upgradeable proxy admin
        proxyAdmin = new ProxyAdmin(users.alice);

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
                users.alice,
                YEARN_AJNA_USDC_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy1 = IStrategy(address(proxy));
        strategy1.grantRoles(users.alice, strategy1.ADMIN_ROLE());
        strategy1.grantRoles(users.alice, strategy1.EMERGENCY_ADMIN_ROLE());
        strategyAddresses.push(address(strategy1));

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
                users.alice,
                YEARN_COMPOUND_USDC_LENDER_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy2 = IStrategy(address(proxy));
        strategy2.grantRoles(users.alice, strategy2.ADMIN_ROLE());
        strategy2.grantRoles(users.alice, strategy2.EMERGENCY_ADMIN_ROLE());
        strategyAddresses.push(address(strategy2));


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
                users.alice,
                YEARN_MATIC_USDC_STAKING_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy3 = IStrategy(address(proxy));
        strategy3.grantRoles(users.alice, strategy3.ADMIN_ROLE());
        strategy3.grantRoles(users.alice, strategy3.EMERGENCY_ADMIN_ROLE());
        strategyAddresses.push(address(strategy3));


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
                users.alice,
                YEARN_USDCE_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy4 = IStrategy(address(proxy));
        strategy4.grantRoles(users.alice, strategy4.ADMIN_ROLE());
        strategy4.grantRoles(users.alice, strategy4.EMERGENCY_ADMIN_ROLE());
        strategyAddresses.push(address(strategy4));


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
                users.alice,
                YEARN_USDCE_LENDER_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy5 = IStrategy(address(proxy));
        strategy5.grantRoles(users.alice, strategy5.ADMIN_ROLE());
        strategy5.grantRoles(users.alice, strategy5.EMERGENCY_ADMIN_ROLE());
        strategyAddresses.push(address(strategy5));

        // Strategy6(YearnDAI)
        YearnDAIStrategy implementation6 = new YearnDAIStrategy();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation6),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vaultUsdce),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Strategy")),
                users.alice,
                YEARN_DAI_POLYGON_VAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        strategy6 = IStrategy(address(proxy));
        strategy6.grantRoles(users.alice, strategy6.ADMIN_ROLE());
        strategy6.grantRoles(users.alice, strategy6.EMERGENCY_ADMIN_ROLE());
        strategyAddresses.push(address(strategy6));

         // Add 13 strategies to the vault
        vaultUsdce.addStrategy(address(strategy1), 1500, type(uint72).max, 0, 0);  // -
        vaultUsdce.addStrategy(address(strategy2), 1500, type(uint72).max, 0, 0);  // -
        vaultUsdce.addStrategy(address(strategy3), 1500, type(uint72).max, 0, 0);  // -
        vaultUsdce.addStrategy(address(strategy4), 1500, type(uint72).max, 0, 0);  // -
        vaultUsdce.addStrategy(address(strategy5), 1500, type(uint72).max, 0, 0);  // -
        vaultUsdce.addStrategy(address(strategy6), 1500, type(uint72).max, 0, 0);  // -


        console2.log("***************************DEPLOYMENT ADDRESSES**********************************");
        console2.log("[MAXAPY] Router :", address(router));
        console2.log("[MAXAPY] Factory :", address(vaultFactory));
        console2.log("[MAXAPY] USDCE Vault :", address(vaultUsdce));
        console2.log("[YEARN] AjnaUSDC:", address(strategy1));
        console2.log("[YEARN] CompoundUSDCeLender:", address(strategy2));
        console2.log("[YEARN] MaticUSDCStaking:", address(strategy3));
        console2.log("[YEARN] USDCeLender:", address(strategy4));
        console2.log("[YEARN] USDCe:", address(strategy5));
        console2.log("[YEARN] YearnDAI:", address(strategy6));
        console2.log("[MAX_APY_HARVESTER]:", address(harvester));
        console2.log("*********************************************************************************");

        IERC20(USDCE_POLYGON).approve(address(vaultUsdce), type(uint256).max);
    }

    function testMaxApyVaultPolygon_firstTest() public {
        vaultUsdce.setDepositLimit(100_000_000_000*_1_USDCE);
        vaultUsdce.deposit(1_000_000*_1_USDCE, users.alice);

        // HARVESTER
        MaxApyHarvester.HarvestData []memory harvestData = new MaxApyHarvester.HarvestData[](1);
        // harvestData[0] = MaxApyHarvester.HarvestData(address(strategy1), 0, 0, block.timestamp + 1000);
        // harvestData[1] = MaxApyHarvester.HarvestData(address(strategy2), 0, 0, block.timestamp + 1000);
        // harvestData[2] = MaxApyHarvester.HarvestData(address(strategy3), 0, 0, block.timestamp + 1000);
        // harvestData[3] = MaxApyHarvester.HarvestData(address(strategy4), 0, 0, block.timestamp + 1000);
        // harvestData[4] = MaxApyHarvester.HarvestData(address(strategy5), 0, 0, block.timestamp + 1000);
        harvestData[0] = MaxApyHarvester.HarvestData(address(strategy6), 0, 0, block.timestamp + 1000);

        harvester.batchHarvests(harvestData);
        
        logStatusAllStrategies();
        console2.log(vaultUsdce.totalAssets());
        console2.log(vaultUsdce.totalDeposits());

        skip(30 days);      
        logStatusAllStrategies();     
        console2.log(vaultUsdce.totalAssets());
        console2.log(vaultUsdce.totalDeposits());                 
    }
}