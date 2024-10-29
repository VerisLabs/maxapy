# MaxAPY · [![License](https://img.shields.io/badge/license-GPL-blue.svg)](LICENSE) [![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.19-orange)](https://docs.soliditylang.org/en/latest/)

MaxAPY is a yield farming **gas-optimized** and **capital-efficient** vault implemented in Solidity, designed to **optimize yield** through various strategies, and earn interest in ERC20 tokens. It relies on the safety of the battle-tested [Yearn&#39;s yVault](https://github.com/yearn/yearn-vaults/blob/efb47d8a84fcb13ceebd3ceb11b126b323bcc05d/contracts/Vault.vy) and the innovation of MaxAPY.

## Contracts

```ml
src/
├── MaxApyRouter.sol
├── MaxApyVault.sol
├── MaxApyVaultFactory.sol
├── helpers
│   ├── AddressBook.sol
│   └── VaultTypes.sol
├── interfaces
│   ├── Hop
│   │   └── ISwap.sol
│   ├── IAlgebraPool.sol
│   ├── IBalancer.sol
│   ├── IBeefyVault.sol
│   ├── ICellar.sol
│   ├── IConvexBooster.sol
│   ├── IConvexRewards.sol
│   ├── ICurve.sol
│   ├── IHypervisor.sol
│   ├── IMaxApyRouter.sol
│   ├── IMaxApyVault.sol
│   ├── IStakingRewardsMulti.sol
│   ├── IStrategy.sol
│   ├── IUniProxy.sol
│   ├── IUniswap.sol
│   ├── IWETH.sol
│   ├── IWrappedToken.sol
│   ├── IWrappedTokenGateway.sol
│   ├── IYVault.sol
│   └── IYVaultV3.sol
├── lib
│   ├── Constants.sol
│   ├── ERC20.sol
│   ├── FixedPoint96.sol
│   ├── Initializable.sol
│   ├── LiquidityRangePool.sol
│   ├── LiquidityTokenMath.sol
│   ├── OracleLibrary.sol
│   └── ReentrancyGuard.sol
├── periphery
│   └── MaxApyHarvester.sol
└── strategies
    ├── base
    │   ├── BaseBeefyCurveStrategy.sol
    │   ├── BaseBeefyStrategy.sol
    │   ├── BaseConvexStrategy.sol
    │   ├── BaseConvexStrategyPolygon.sol
    │   ├── BaseHopStrategy.sol
    │   ├── BaseSommelierStrategy.sol
    │   ├── BaseStrategy.sol
    │   ├── BaseYearnV2Strategy.sol
    │   └── BaseYearnV3Strategy.sol
    ├── mainnet
    │   ├── USDC
    │   │   ├── convex
    │   │   │   └── ConvexCrvUSDWethCollateralStrategy.sol
    │   │   ├── sommelier
    │   │   │   └── SommelierTurboGHOStrategy.sol
    │   │   └── yearn
    │   │       ├── YearnAjnaDAIStakingStrategy.sol
    │   │       ├── YearnDAIStrategy.sol
    │   │       ├── YearnLUSDStrategy.sol
    │   │       ├── YearnUSDCStrategy.sol
    │   │       └── YearnUSDTStrategy.sol
    │   └── WETH
    │       ├── convex
    │       │   └── ConvexdETHFrxETHStrategy.sol
    │       ├── sommelier
    │       │   ├── SommelierMorphoEthMaximizerStrategy.sol
    │       │   ├── SommelierStEthDepositTurboStEthStrategy.sol
    │       │   ├── SommelierTurboDivEthStrategy.sol
    │       │   ├── SommelierTurboEEthV2Strategy.sol
    │       │   ├── SommelierTurboEthXStrategy.sol
    │       │   ├── SommelierTurboEzEthStrategy.sol
    │       │   ├── SommelierTurboRsEthStrategy.sol
    │       │   ├── SommelierTurboStEthStrategy.sol
    │       │   └── SommelierTurboSwEthStrategy.sol
    │       └── yearn
    │           ├── YearnAaveV3WETHLenderStrategy.sol
    │           ├── YearnAjnaWETHStakingStrategy.sol
    │           ├── YearnCompoundV3WETHLenderStrategy.sol
    │           ├── YearnV3WETH2Strategy.sol
    │           ├── YearnV3WETHStrategy.sol
    │           └── YearnWETHStrategy.sol
    └── polygon
        ├── USDCe
        │   ├── beefy
        │   │   ├── BeefyCrvUSDUSDCeStrategy.sol
        │   │   ├── BeefyMaiUSDCeStrategy.sol
        │   │   └── BeefyUSDCeDAIStrategy.sol
        │   ├── convex
        │   │   ├── ConvexUSDCCrvUSDStrategy.sol
        │   │   └── ConvexUSDTCrvUSDStrategy.sol
        │   └── yearn
        │       ├── YearnAaveV3USDTLenderStrategy.sol
        │       ├── YearnAjnaUSDCStrategy.sol
        │       ├── YearnCompoundUSDCeLenderStrategy.sol
        │       ├── YearnDAILenderStrategy.sol
        │       ├── YearnDAIStrategy.sol
        │       ├── YearnMaticUSDCStakingStrategy.sol
        │       ├── YearnUSDCeLenderStrategy.sol
        │       ├── YearnUSDCeStrategy.sol
        │       └── YearnUSDTStrategy.sol
        └── WETH
            └── hop
                └── HopETHStrategy.sol

```

## Installation

### Prerequisites

To install Foundry:

```sh
curl -L https://foundry.paradigm.xyz | bash
```

This will download foundryup. To start Foundry, run:

```sh
foundryup
```

We are using a nightly version of Foundry, so you will need to run the following command to install the nightly version:

```sh
foundryup -v nightly-f625d0fa7c51e65b4bf1e8f7931cd1c6e2e285e9
```

To install Soldeer:

```sh
cargo install soldeer
```

### Clone the repo

```sh
git clone https://github.com/UnlockdFinance/maxapy.git
```

### Install the dependencies

```sh
soldeer install
```

### Compile

```sh
forge build
```

### Set local environment variables

Create a `.env` file and create the necessary environment variables following the example in `env.example`.

## Testing

To run the unit tests:

```sh
forge test --mt test
```

To run the invariant(stateful fuzz) tests:

```sh
forge test --mt invariant
```

To run the invariant(stateless fuzz) tests:

```sh
forge test --mt testFuzz
```

## Run a local simulation

We created a custom suite to run and test the protocol in a mainnet local fork.This allows to interact with a mock protocol in the most realistic environment possible.

Fetch the local environment variables from the dotenv file:

```sh
source .env
```

Run the local fork:

```sh
anvil --fork-url $RPC_MAINNET  --fork-block-number $FORK_BLOCK_NUMBER --accounts 10
```

**Note:** It's recommended using one of the private keys provided by anvil for testing

```sh
forge script script/local/MaxApy.s.sol:DeploymentScript --fork-url http://localhost:8545 --etherscan-api-key $ETHERSCAN_API_KEY --broadcast -vvv --legacy
```

### Interacting with the local fork

Use the sh utils for easier interactions :

```sh
./script/local/utils/setupProtocol.sh
```

## License

This project is licensed under the GPL License - see the [LICENSE](LICENSE) file for details.
