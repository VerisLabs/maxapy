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
import { HopETHStrategyWrapper } from "../mock/HopETHStrategyWrapper.sol";

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
    IStrategyWrapper public strategy1; 
    
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
            new MaxApyVault(users.alice, WETH_POLYGON, "MaxApyWETHVault", "maxApy", TREASURY);

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

        HopETHStrategyWrapper implementation1 = new HopETHStrategyWrapper();
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation1),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address)",
                address(vault),
                keepers,
                abi.encode("MaxApy HOP WETH"),
                users.alice,
                HOP_ETH_SWAP_POLYGON,
                HOP_ETH_SWAP_LP_TOKEN_POLYGON
            )
        );
        proxy = ITransparentUpgradeableProxy(address(_proxy));
        vm.label(address(proxy), "HopStrategy");
        strategy1 = IStrategyWrapper(address(proxy));

        address[] memory strategyList = new address[](1);

        strategyList[0] = address(strategy1);

        // Add all the strategies
        vault.addStrategy(address(strategy1), 9000, type(uint72).max, 0, 0);

        vm.label(address(WETH_POLYGON), "WETH");
        /// Alice approves vault for deposits
        IERC20(WETH_POLYGON).approve(address(vault), type(uint256).max);
        vm.startPrank(users.bob);
        IERC20(WETH_POLYGON).approve(address(vault), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(users.alice);

        // deploy fuzzers
        strategyFuzzer = new StrategyFuzzer(strategyList, vault, WETH_POLYGON);
        vaultFuzzer = new MaxApyVaultFuzzer(vault, WETH_POLYGON);

        vault.grantRoles(address(strategyFuzzer), vault.ADMIN_ROLE());
        uint256 _keeperRole = strategy1.KEEPER_ROLE();

        strategy1.grantRoles(address(strategyFuzzer), _keeperRole);
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
