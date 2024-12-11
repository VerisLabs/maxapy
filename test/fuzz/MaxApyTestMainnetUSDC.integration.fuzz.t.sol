// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

import { BaseTest, IERC20, Vm, console2 } from "../base/BaseTest.t.sol";

import { ICompoundV3StrategyWrapper } from "../interfaces/ICompoundV3StrategyWrapper.sol";
import { IStrategyWrapper } from "../interfaces/IStrategyWrapper.sol";

import { MaxApyVault } from "src/MaxApyVault.sol";

import "src/helpers/AddressBook.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";
import { StrategyEvents } from "test/helpers/StrategyEvents.sol";

// Compound v3
import { CompoundV3USDTStrategyWrapper } from "../mock/CompoundV3USDTStrategyWrapper.sol";

// Beefy
import { BeefythUSDDAIUSDCUSDTStrategyWrapper } from "../mock/BeefythUSDDAIUSDCUSDTStrategyWrapper.sol";

// Vault fuzzer
import { MaxApyVaultFuzzer } from "./fuzzers/MaxApyVaultFuzzer.t.sol";
import { StrategyFuzzer } from "./fuzzers/StrategyFuzzer.t.sol";

// Import Random Number Generator
import { LibPRNG } from "solady/utils/LibPRNG.sol";

/// @dev Integration fuzz tests for the mainnet WETH vault
contract MaxApyIntegrationTestMainnet is BaseTest, StrategyEvents {
    using LibPRNG for LibPRNG.PRNG;

    ////////////////////////////////////////////////////////////////
    ///                    CONSTANTS                             ///
    ////////////////////////////////////////////////////////////////

    // YearnV2 WETH
    address public constant YVAULT_WETH_MAINNET = YEARN_WETH_YVAULT_MAINNET;

    // Vault Fuzzer
    MaxApyVaultFuzzer public vaultFuzzer;
    // Strategies fuzzer
    StrategyFuzzer public strategyFuzzer;

    address public TREASURY;

    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////

    ICompoundV3StrategyWrapper public strategy1; // yearn weth
    IStrategyWrapper public strategy2;

    IMaxApyVault public vault;
    ITransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////

    function setUp() public {
        super._setUp("MAINNET");
        vm.rollFork(20_790_660);

        TREASURY = makeAddr("treasury");

        /// Deploy MaxApyVault
        MaxApyVault vaultDeployment = new MaxApyVault(users.alice, USDC_MAINNET, "MaxApyUSDCVault", "maxApy", TREASURY);

        vault = IMaxApyVault(address(vaultDeployment));
        /// Deploy transparent upgradeable proxy admin
        proxyAdmin = new ProxyAdmin(users.alice);

        address[] memory keepers = new address[](1);
        keepers[0] = users.keeper;

        /////////////////////////////////////////////////////////////////////////
        ///                        STRATEGIES                                 ///
        /////////////////////////////////////////////////////////////////////////
        /// Deploy transparent upgradeable proxy admin

        // Deploy strategy1
        CompoundV3USDTStrategyWrapper implementation1 = new CompoundV3USDTStrategyWrapper();
        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(implementation1),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address,address,address)",
                address(vault),
                keepers,
                bytes32("MaxApy USDT Strategy"),
                users.alice,
                COMPOUND_USDT_V3_COMMET_MAINNET,
                COMPOUND_USDT_V3_REWARDS_MAINNET,
                USDT_MAINNET,
                UNISWAP_V3_ROUTER_MAINNET
            )
        );
        vm.label(COMPOUND_USDT_V3_COMMET_MAINNET, "CompoundV3USDT");
        strategy1 = ICompoundV3StrategyWrapper(address(_proxy));

        // Deploy strategy2
        BeefythUSDDAIUSDCUSDTStrategyWrapper implementation2 = new BeefythUSDDAIUSDCUSDTStrategyWrapper();
        _proxy = new TransparentUpgradeableProxy(
            address(implementation2),
            address(proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address,address,address,address)",
                address(vault),
                keepers,
                bytes32("MaxApy thUSDDAIUSDCUSDT Strategy"),
                users.alice,
                CURVE_THUSD_DAI_USDC_USDT_MAINNET,
                BEEFY_THUSD_DAI_USDC_USDT_MAINNET,
                CURVE_3POOL_POOL_MAINNET,
                CRV3POOL_MAINNET
            )
        );
        vm.label(BEEFY_THUSD_DAI_USDC_USDT_MAINNET, "BeefythUSDTDAIUSDCUSDT");
        strategy2 = IStrategyWrapper(address(_proxy));

        address[] memory strategyList = new address[](2);

        strategyList[0] = address(strategy1);
        strategyList[1] = address(strategy2);

        // Add all the strategies
        vault.addStrategy(address(strategy1), 700, type(uint72).max, 0, 0);
        vault.addStrategy(address(strategy2), 700, type(uint72).max, 0, 0);

        vm.label(address(USDC_MAINNET), "USDC");
        /// Alice approves vault for deposits
        IERC20(USDC_MAINNET).approve(address(vault), type(uint256).max);
        vm.startPrank(users.bob);
        IERC20(USDC_MAINNET).approve(address(vault), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(users.alice);

        // deploy fuzzers
        strategyFuzzer = new StrategyFuzzer(strategyList, vault, USDC_MAINNET);
        vaultFuzzer = new MaxApyVaultFuzzer(vault, USDC_MAINNET);

        vault.grantRoles(address(strategyFuzzer), vault.ADMIN_ROLE());
        uint256 _keeperRole = strategy1.KEEPER_ROLE();

        strategy1.grantRoles(address(strategyFuzzer), _keeperRole);
        strategy2.grantRoles(address(strategyFuzzer), _keeperRole);
    }

    function testFuzzMaxApyIntegrationMainnet__DepositAndRedeemWithoutHarvests(
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

    function testFuzzMaxApyIntegrationMainnet__DepositAndRedeemWithHarvests(
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

    function testFuzzMaxApyIntegrationMainnet__DepositAndRedeemAfterExitStrategy(
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

    function testFuzzMaxApyIntegrationMainnet__DepositAndRedeemWithGainsAndLossesWithoutHarvests(
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

    function testFuzzMaxApyIntegrationMainnet__DepositAndRedeemWithGainsAndLossesWithHarvests(
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

    function testFuzzMaxApyIntegrationMainnet__MintAndWithdrawWithoutHarvests(
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

    function testFuzzMaxApyIntegrationMainnet__MintAndWithdrawWithHarvests(
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

    function testFuzzMaxApyIntegrationMainnet__MintAndWithdrawGainsAndLossesWithoutHarvests(
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

    function testFuzzMaxApyIntegrationMainnet__MintAndWithdrawGainsAndLossesWithHarvests(
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

    function testFuzzMaxApyIntegrationMainnet__RandomSequence(
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
