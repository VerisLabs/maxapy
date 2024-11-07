// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

// helpers
import "forge-std/Script.sol";
import { BaseTest, IERC20, Vm, console2 } from "../base/BaseTest.t.sol";
import { StrategyEvents } from "../../test/helpers/StrategyEvents.sol";
import "src/helpers/AddressBook.sol";

// proxies
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";

// interfaces
import { IStrategyWrapper } from "../interfaces/IStrategyWrapper.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";
import { IWrappedToken } from "src/interfaces/IWrappedToken.sol";

//// Strategies
import { BeefyMaiUSDCeStrategyWrapper } from "../mock/BeefyMaiUSDCeStrategyWrapper.sol";
import { ConvexUSDCCrvUSDStrategyWrapper } from "../mock/ConvexUSDCCrvUSDStrategyWrapper.sol";
import { ConvexUSDTCrvUSDStrategyWrapper } from "../mock/ConvexUSDTCrvUSDStrategyWrapper.sol";
import { YearnMaticUSDCStakingStrategyWrapper } from "../mock/YearnMaticUSDCStakingStrategyWrapper.sol";
import { YearnAjnaUSDCStrategyWrapper } from "../mock/YearnAjnaUSDCStrategyWrapper.sol";
import { YearnUSDTStrategyWrapper } from "../mock/YearnUSDTStrategyWrapper-polygon.sol";
import { YearnUSDCeLenderStrategyWrapper } from "../mock/YearnUSDCeLenderStrategyWrapper.sol";
import { YearnUSDCeStrategyWrapper } from "../mock/YearnUSDCeStrategyWrapper.sol";
import { YearnDAIStrategyWrapper } from "../mock/YearnDAIStrategyWrapper-polygon.sol";
import { YearnDAILenderStrategyWrapper } from "../mock/YearnDAILenderStrategyWrapper.sol";
import { YearnCompoundUSDCeLenderStrategyWrapper } from "../mock/YearnCompoundUSDCeLenderStrategyWrapper.sol";
import { BeefyCrvUSDUSDCeStrategyWrapper } from "../mock/BeefyCrvUSDUSDCeStrategyWrapper.sol";
import { BeefyUSDCeDAIStrategyWrapper } from "../mock/BeefyUSDCeDAIStrategyWrapper.sol";
import { YearnAaveV3USDTLenderStrategyWrapper } from "../mock/YearnAaveV3USDTLenderStrategyWrapper.sol";

//// Vault
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { MaxApyRouter } from "src/MaxApyRouter.sol";
import { MaxApyVaultFactory } from "src/MaxApyVaultFactory.sol";
import { MaxApyHarvester } from "src/periphery/MaxApyHarvester.sol";
import { MaxApyVault, OwnableRoles } from "src/MaxApyVault.sol";

// Vault fuzzer
import { MaxApyVaultFuzzer } from "./fuzzers/MaxApyVaultFuzzer.t.sol";
import { StrategyFuzzer } from "./fuzzers/StrategyFuzzer.t.sol";

// Import Random Number Generator
import { LibPRNG } from "solady/utils/LibPRNG.sol";

contract MaxApyPolygonIntegrationTest is BaseTest, StrategyEvents {
    using LibPRNG for LibPRNG.PRNG;

    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////
    // **********STRATS******************
    // USDCE
    IStrategyWrapper public strategy1; // BeefyMaiUSDCeStrategyWrapper
    IStrategyWrapper public strategy2; // ConvexUSDCCrvUSDStrategyWrapper
    IStrategyWrapper public strategy3; // ConvexUSDTCrvUSDStrategyWrapper
    IStrategyWrapper public strategy4; // YearnMaticUSDCStaking
    IStrategyWrapper public strategy5; // YearnAjnaUSDC
    IStrategyWrapper public strategy6; // YearnUSDTStrategyWrapper
    IStrategyWrapper public strategy7; // YearnUSDCeLender
    IStrategyWrapper public strategy8; // YearnUSDCe
    IStrategyWrapper public strategy9; // YearnDAIStrategyWrapper
    IStrategyWrapper public strategy10; // YearnDAILenderStrategyWrapper
    IStrategyWrapper public strategy11; // YearnCompoundUSDCeLender
    IStrategyWrapper public strategy12; // BeefyCrvUSDUSDCeStrategyWrapper
    IStrategyWrapper public strategy13; //BeefyUSDCeDAIStrategyWrapper
    IStrategyWrapper public strategy14; // YearnAaveV3USDTLenderStrategyWrapper

    // Vault Fuzzer
    MaxApyVaultFuzzer public vaultFuzzer;
    // Strategies fuzzer
    StrategyFuzzer public strategyFuzzer;

    address public TREASURY;

    // **********LOCAL VARIABLES*****************
    // use storage variables to avoid stack too deep
    IMaxApyVault public vault;

    // Proxies
    ITransparentUpgradeableProxy proxy;
    ProxyAdmin proxyAdmin;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////

    function setUp() public {
        /////////////////////////////////////////////////////////////////////////
        ///                             ACTORS                                ///
        /////////////////////////////////////////////////////////////////////////
        super._setUp("POLYGON");
        vm.rollFork(61_767_099);

        TREASURY = makeAddr("treasury");

        /// Deploy MaxApyVault
        MaxApyVault vaultDeployment =
            new MaxApyVault(users.alice, USDCE_POLYGON, "MaxApyUSDCEVault", "maxApy", TREASURY);

        vault = IMaxApyVault(address(vaultDeployment));
        /// Deploy transparent upgradeable proxy admin
        proxyAdmin = new ProxyAdmin(users.alice);

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;

        /////////////////////////////////////////////////////////////////////////
        ///                        STRATEGIES                                 ///
        /////////////////////////////////////////////////////////////////////////
        /// Deploy transparent upgradeable proxy admin
        proxyAdmin = new ProxyAdmin(users.alice);

        // StrategyWrapper1(BeefyMaiUSDCeStrategyWrapper)
        BeefyMaiUSDCeStrategyWrapper implementation1 = new BeefyMaiUSDCeStrategyWrapper();
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation1),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Beefy MAI<>USDCe")),
                users.alice,
                CURVE_MAI_USDCE_POOL_POLYGON,
                BEEFY_MAI_USDCE_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "BeefyMaiUSDCeStrategy");
        strategy1 = IStrategyWrapper(address(proxy));

        // StrategyWrapper2(ConvexUSDCCrvUSDStrategyWrapper)
        ConvexUSDCCrvUSDStrategyWrapper implementation2 = new ConvexUSDCCrvUSDStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation2),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Convex USD<>USDCe")),
                users.alice,
                CURVE_CRVUSD_USDC_POOL_POLYGON,
                UNISWAP_V3_ROUTER_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "ConvexUSDCCrvUSDStrategy");
        strategy2 = IStrategyWrapper(address(proxy));

        // StrategyWrapper3(ConvexUSDTCrvUSDStrategyWrapper)
        ConvexUSDTCrvUSDStrategyWrapper implementation3 = new ConvexUSDTCrvUSDStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation3),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Convex USDT<>USDCe")),
                users.alice,
                CURVE_CRVUSD_USDT_POOL_POLYGON,
                UNISWAP_V3_ROUTER_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "ConvexUSDTCrvUSDStrategy");
        strategy3 = IStrategyWrapper(address(proxy));

        // StrategyWrapper4(YearnMaticUSDCStaking)
        YearnMaticUSDCStakingStrategyWrapper implementation4 = new YearnMaticUSDCStakingStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation4),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Matic<>USDCe")),
                users.alice,
                YEARN_MATIC_USDC_STAKING_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "YearnMaticUSDCStaking");
        strategy4 = IStrategyWrapper(address(proxy));

        // StrategyWrapper5(YearnAjnaUSDC)
        YearnAjnaUSDCStrategyWrapper implementation5 = new YearnAjnaUSDCStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation5),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Ajna<>USDCe")),
                users.alice,
                YEARN_AJNA_USDC_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "YearnAjnaUSDC");
        strategy5 = IStrategyWrapper(address(proxy));

        // StrategyWrapper6(YearnUSDTStrategyWrapper)
        YearnUSDTStrategyWrapper implementation6 = new YearnUSDTStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation6),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Yearn USDT<>USDCe")),
                users.alice,
                YEARN_USDT_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "YearnUSDTStrategyWrapper");
        strategy6 = IStrategyWrapper(address(proxy));

        // StrategyWrapper7(YearnUSDCeLender)
        YearnUSDCeLenderStrategyWrapper implementation7 = new YearnUSDCeLenderStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation7),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Lender USDCe")),
                users.alice,
                YEARN_USDCE_LENDER_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "YearnUSDCeLender");
        strategy7 = IStrategyWrapper(address(proxy));

        // StrategyWrapper8(YearnUSDCe)
        YearnUSDCeStrategyWrapper implementation8 = new YearnUSDCeStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation8),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Yearn USDCe")),
                users.alice,
                YEARN_USDCE_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "YearnUSDCe");
        strategy8 = IStrategyWrapper(address(proxy));

        // StrategyWrapper9(YearnDAIStrategyWrapper)
        YearnDAIStrategyWrapper implementation9 = new YearnDAIStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation9),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Yearn DAI<>USDCe")),
                users.alice,
                YEARN_DAI_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "YearnDAIStrategy");
        strategy9 = IStrategyWrapper(address(proxy));

        // StrategyWrapper10(YearnDAILenderStrategyWrapper)
        YearnDAILenderStrategyWrapper implementation10 = new YearnDAILenderStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation10),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Lender DAI<>USDCe")),
                users.alice,
                YEARN_DAI_LENDER_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "YearnDAILenderStrategy");
        strategy10 = IStrategyWrapper(address(proxy));

        // StrategyWrapper11(YearnCompoundUSDCeLender)
        YearnCompoundUSDCeLenderStrategyWrapper implementation11 = new YearnCompoundUSDCeLenderStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation11),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Compound Lender USDCe")),
                users.alice,
                YEARN_COMPOUND_USDC_LENDER_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "YearnCompoundUSDCeLender");
        strategy11 = IStrategyWrapper(address(proxy));

        // StrategyWrapper12(BeefyMaBeefyCrvUSDUSDCeStrategyWrapperiUSDCeStrategyWrapper)
        BeefyCrvUSDUSDCeStrategyWrapper implementation12 = new BeefyCrvUSDUSDCeStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation12),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy CrvUSD<>USDCe Strategy")),
                users.alice,
                CURVE_CRVUSD_USDCE_POOL_POLYGON,
                BEEFY_CRVUSD_USDCE_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "BeefyCrvUSDUSDCeStrategy");
        strategy12 = IStrategyWrapper(address(proxy));

        // StrategyWrapper13(BeefyUSDCeDAIStrategyWrapper)
        BeefyUSDCeDAIStrategyWrapper implementation13 = new BeefyUSDCeDAIStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation13),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy USDCe<>DAI Strategy")),
                users.alice,
                GAMMA_USDCE_DAI_UNIPROXY_POLYGON,
                GAMMA_USDCE_DAI_HYPERVISOR_POLYGON,
                BEEFY_USDCE_DAI_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "BeefyUSDCeDAIStrategy");
        strategy13 = IStrategyWrapper(address(proxy));

        // StrategyWrapper14(YearnAaveV3USDTLenderStrategyWrapper)
        YearnAaveV3USDTLenderStrategyWrapper implementation14 = new YearnAaveV3USDTLenderStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation14),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Yearn Strategy")),
                users.alice,
                YEARN_AAVE_V3_USDT_LENDER_YVAULT_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "YearnAaveV3USDTLenderStrategy");
        strategy14 = IStrategyWrapper(address(proxy));

        address[] memory strategyList = new address[](14);

        strategyList[0] = address(strategy1);
        strategyList[1] = address(strategy2);
        strategyList[2] = address(strategy3);
        strategyList[3] = address(strategy4);
        strategyList[4] = address(strategy5);
        strategyList[5] = address(strategy6);
        strategyList[6] = address(strategy7);
        strategyList[7] = address(strategy8);
        strategyList[8] = address(strategy9);
        strategyList[9] = address(strategy10);
        strategyList[10] = address(strategy11);
        strategyList[11] = address(strategy12);
        strategyList[12] = address(strategy13);
        strategyList[13] = address(strategy14);

        // Add all the strategies
        vault.addStrategy(address(strategy1), 700, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy2), 700, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy3), 700, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy4), 700, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy5), 700, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy6), 700, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy7), 700, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy8), 700, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy9), 700, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy10), 700, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy11), 700, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy12), 700, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy13), 700, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy14), 700, type(uint72).max, 0, 0);

        vm.label(address(USDCE_POLYGON), "USDCE");
        /// Alice approves vault for deposits
        IERC20(USDCE_POLYGON).approve(address(vault), type(uint256).max);
        vm.startPrank(users.bob);
        IERC20(USDCE_POLYGON).approve(address(vault), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(users.alice);

        // deploy fuzzers
        strategyFuzzer = new StrategyFuzzer(strategyList, vault, USDCE_POLYGON);
        vaultFuzzer = new MaxApyVaultFuzzer(vault, USDCE_POLYGON);

        vault.grantRoles(address(strategyFuzzer), vault.ADMIN_ROLE());
        uint256 _keeperRole = strategy1.KEEPER_ROLE();

        strategy1.grantRoles(address(strategyFuzzer), _keeperRole);
        strategy2.grantRoles(address(strategyFuzzer), _keeperRole);
        strategy3.grantRoles(address(strategyFuzzer), _keeperRole);
        strategy4.grantRoles(address(strategyFuzzer), _keeperRole);
        strategy5.grantRoles(address(strategyFuzzer), _keeperRole);
        strategy6.grantRoles(address(strategyFuzzer), _keeperRole);
        strategy7.grantRoles(address(strategyFuzzer), _keeperRole);
        strategy8.grantRoles(address(strategyFuzzer), _keeperRole);
        strategy9.grantRoles(address(strategyFuzzer), _keeperRole);
        strategy10.grantRoles(address(strategyFuzzer), _keeperRole);
        strategy11.grantRoles(address(strategyFuzzer), _keeperRole);
        strategy12.grantRoles(address(strategyFuzzer), _keeperRole);
        strategy13.grantRoles(address(strategyFuzzer), _keeperRole);
    }

    function testFuzzMaxApyIntegrationPolygon__DepositAndRedeemWithoutHarvests(
        uint256 actorSeed,
        uint256 assets,
        uint256 shares
    )
        public
    {
        LibPRNG.PRNG memory actorSeedRNG;
        actorSeedRNG.seed(actorSeed);
        vaultFuzzer.deposit(assets);
        vaultFuzzer.deposit(assets);
        vaultFuzzer.deposit(assets);
        vaultFuzzer.redeem(actorSeedRNG, shares);
        vaultFuzzer.redeem(actorSeedRNG, shares);
        vaultFuzzer.redeem(actorSeedRNG, shares);
    }

    function testFuzzMaxApyIntegrationPolygon__DepositAndRedeemWithHarvests(
        uint256 actorSeed,
        uint256 strategySeed,
        uint256 assets,
        uint256 shares
    )
        public
    {
        LibPRNG.PRNG memory actorSeedRNG;
        LibPRNG.PRNG memory strategyRNG;
        actorSeedRNG.seed(actorSeed);
        strategyRNG.seed(strategySeed);

        vaultFuzzer.deposit(assets);
        strategyFuzzer.harvest(strategyRNG);
        vaultFuzzer.deposit(assets);
        strategyFuzzer.harvest(strategyRNG);
        vaultFuzzer.deposit(assets);
        vaultFuzzer.redeem(actorSeedRNG, shares);
        strategyFuzzer.harvest(strategyRNG);
        vaultFuzzer.redeem(actorSeedRNG, shares);
        vaultFuzzer.redeem(actorSeedRNG, shares);
    }

    function testFuzzMaxApyIntegrationPolygon__DepositAndRedeemAfterExitStrategy(
        uint256 actorSeed,
        uint256 strategySeed,
        uint256 assets,
        uint256 shares
    )
        public
    {
        LibPRNG.PRNG memory actorSeedRNG;
        LibPRNG.PRNG memory strategyRNG;
        actorSeedRNG.seed(actorSeed);
        strategyRNG.seed(strategySeed);

        vaultFuzzer.deposit(assets);
        strategyFuzzer.exitStrategy(strategyRNG);
        vaultFuzzer.deposit(assets);
        strategyFuzzer.exitStrategy(strategyRNG);
        vaultFuzzer.deposit(assets);
        vaultFuzzer.redeem(actorSeedRNG, shares);
        strategyFuzzer.exitStrategy(strategyRNG);
        vaultFuzzer.redeem(actorSeedRNG, shares);
        vaultFuzzer.redeem(actorSeedRNG, shares);
    }

    function testFuzzMaxApyIntegrationPolygon__DepositAndRedeemWithGainsAndLossesWithoutHarvests(
        uint256 actorSeed,
        uint256 strategySeed,
        uint256 gainsAndLossesSeed,
        uint256 assets,
        uint256 shares
    )
        public
    {
        LibPRNG.PRNG memory actorSeedRNG;
        LibPRNG.PRNG memory strategyRNG;
        LibPRNG.PRNG memory gainAndLossesRNG;

        actorSeedRNG.seed(actorSeed);
        strategyFuzzer.harvest(strategyRNG);
        strategyFuzzer.harvest(strategyRNG);
        strategyRNG.seed(strategySeed);
        gainAndLossesRNG.seed(gainsAndLossesSeed);
        strategyFuzzer.harvest(strategyRNG);
        vaultFuzzer.deposit(assets);
        strategyFuzzer.harvest(strategyRNG);
        strategyFuzzer.gain(strategyRNG, gainAndLossesRNG.next());
        vaultFuzzer.deposit(assets);
        strategyFuzzer.harvest(strategyRNG);
        strategyFuzzer.gain(strategyRNG, gainAndLossesRNG.next());
        strategyFuzzer.harvest(strategyRNG);
        strategyFuzzer.harvest(strategyRNG);
        strategyFuzzer.harvest(strategyRNG);
        vaultFuzzer.deposit(assets);
        vaultFuzzer.redeem(actorSeedRNG, shares);
        strategyFuzzer.loss(strategyRNG, gainAndLossesRNG.next());
        strategyFuzzer.harvest(strategyRNG);
        strategyFuzzer.harvest(strategyRNG);
        strategyFuzzer.harvest(strategyRNG);
        vaultFuzzer.redeem(actorSeedRNG, shares);
        vaultFuzzer.redeem(actorSeedRNG, shares);
    }

    function testFuzzMaxApyIntegrationPolygon__DepositAndRedeemWithGainsAndLossesWithHarvests(
        uint256 actorSeed,
        uint256 strategySeed,
        uint256 gainsAndLossesSeed,
        uint256 assets,
        uint256 shares
    )
        public
    {
        LibPRNG.PRNG memory actorSeedRNG;
        LibPRNG.PRNG memory strategyRNG;
        LibPRNG.PRNG memory gainAndLossesRNG;

        actorSeedRNG.seed(actorSeed);
        strategyRNG.seed(strategySeed);
        gainAndLossesRNG.seed(gainsAndLossesSeed);

        vaultFuzzer.deposit(assets);
        strategyFuzzer.gain(strategyRNG, gainAndLossesRNG.next());
        vaultFuzzer.deposit(assets);
        strategyFuzzer.gain(strategyRNG, gainAndLossesRNG.next());
        vaultFuzzer.deposit(assets);
        vaultFuzzer.redeem(actorSeedRNG, shares);
        strategyFuzzer.loss(strategyRNG, gainAndLossesRNG.next());
        vaultFuzzer.redeem(actorSeedRNG, shares);
        vaultFuzzer.redeem(actorSeedRNG, shares);
    }

    function testFuzzMaxApyIntegrationPolygon__MintAndWithdrawWithoutHarvests(
        uint256 actorSeed,
        uint256 assets,
        uint256 shares
    )
        public
    {
        LibPRNG.PRNG memory actorSeedRNG;
        actorSeedRNG.seed(actorSeed);
        vaultFuzzer.mint(shares);
        vaultFuzzer.mint(shares);
        vaultFuzzer.mint(shares);
        vaultFuzzer.withdraw(actorSeedRNG, assets);
        vaultFuzzer.withdraw(actorSeedRNG, assets);
        vaultFuzzer.withdraw(actorSeedRNG, assets);
    }

    function testFuzzMaxApyIntegrationPolygon__MintAndWithdrawWithHarvests(
        uint256 actorSeed,
        uint256 strategySeed,
        uint256 shares,
        uint256 assets
    )
        public
    {
        LibPRNG.PRNG memory actorSeedRNG;
        LibPRNG.PRNG memory strategySeedRNG;
        actorSeedRNG.seed(actorSeed);
        strategySeedRNG.seed(strategySeed);

        vaultFuzzer.mint(shares);
        strategyFuzzer.harvest(strategySeedRNG);
        vaultFuzzer.mint(shares);
        strategyFuzzer.harvest(strategySeedRNG);
        vaultFuzzer.mint(shares);
        vaultFuzzer.withdraw(actorSeedRNG, assets);
        strategyFuzzer.harvest(strategySeedRNG);
        vaultFuzzer.withdraw(actorSeedRNG, assets);
        vaultFuzzer.withdraw(actorSeedRNG, assets);
    }

    function testFuzzMaxApyIntegrationPolygon__MintAndWithdrawGainsAndLossesWithoutHarvests(
        uint256 actorSeed,
        uint256 strategySeed,
        uint256 gainsAndLossesSeed,
        uint256 shares,
        uint256 assets
    )
        public
    {
        LibPRNG.PRNG memory actorSeedRNG;
        LibPRNG.PRNG memory strategyRNG;
        LibPRNG.PRNG memory gainAndLossesRNG;

        actorSeedRNG.seed(actorSeed);
        strategyRNG.seed(strategySeed);
        gainAndLossesRNG.seed(gainsAndLossesSeed);

        vaultFuzzer.mint(shares);
        strategyFuzzer.gain(strategyRNG, gainAndLossesRNG.next());
        vaultFuzzer.mint(shares);
        strategyFuzzer.gain(strategyRNG, gainAndLossesRNG.next());
        vaultFuzzer.mint(shares);
        vaultFuzzer.withdraw(actorSeedRNG, assets);
        strategyFuzzer.loss(strategyRNG, gainAndLossesRNG.next());
        vaultFuzzer.withdraw(actorSeedRNG, assets);
        vaultFuzzer.withdraw(actorSeedRNG, assets);
    }

    function testFuzzMaxApyIntegrationPolygon__MintAndWithdrawGainsAndLossesWithHarvests(
        uint256 actorSeed,
        uint256 strategySeed,
        uint256 gainsAndLossesSeed,
        uint256 shares,
        uint256 assets
    )
        public
    {
        LibPRNG.PRNG memory actorRNG;
        LibPRNG.PRNG memory strategyRNG;
        LibPRNG.PRNG memory gainAndLossesRNG;

        actorRNG.seed(actorSeed);
        strategyRNG.seed(strategySeed);
        gainAndLossesRNG.seed(gainsAndLossesSeed);

        vaultFuzzer.mint(shares);
        strategyFuzzer.gain(strategyRNG, gainAndLossesRNG.next());
        strategyFuzzer.harvest(strategyRNG);
        strategyFuzzer.harvest(strategyRNG);
        vaultFuzzer.mint(shares);
        strategyFuzzer.gain(strategyRNG, gainAndLossesRNG.next());
        strategyFuzzer.harvest(strategyRNG);
        vaultFuzzer.mint(shares);
        strategyFuzzer.loss(strategyRNG, gainAndLossesRNG.next());
        vaultFuzzer.withdraw(actorRNG, assets);
        strategyFuzzer.harvest(strategyRNG);
        strategyFuzzer.harvest(strategyRNG);
        strategyFuzzer.harvest(strategyRNG);
        vaultFuzzer.withdraw(actorRNG, assets);
        strategyFuzzer.loss(strategyRNG, gainAndLossesRNG.next());
        vaultFuzzer.withdraw(actorRNG, assets);
        strategyFuzzer.harvest(strategyRNG);
    }

    function testFuzzMaxApyIntegrationPolygon__RandomSequence(
        uint256 actorSeed,
        uint256 strategySeed,
        uint256 functionSeed,
        uint256 argumentsSeed
    )
        public
    {
        LibPRNG.PRNG memory actorRNG;
        LibPRNG.PRNG memory strategyRNG;
        LibPRNG.PRNG memory functionRNG;
        LibPRNG.PRNG memory argumentsRNG;

        actorRNG.seed(actorSeed);
        strategyRNG.seed(strategySeed);
        functionRNG.seed(functionSeed);
        argumentsRNG.seed(argumentsSeed);

        vaultFuzzer.rand(actorRNG, functionRNG, argumentsRNG);
        strategyFuzzer.rand(functionRNG, strategyRNG, argumentsRNG);
        vaultFuzzer.rand(actorRNG, functionRNG, argumentsRNG);
        strategyFuzzer.rand(functionRNG, strategyRNG, argumentsRNG);
        vaultFuzzer.rand(actorRNG, functionRNG, argumentsRNG);
        strategyFuzzer.rand(functionRNG, strategyRNG, argumentsRNG);
    }
}
