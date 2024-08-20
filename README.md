# MaxAPY · [![License](https://img.shields.io/badge/license-GPL-blue.svg)](LICENSE) [![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.19-orange)](https://docs.soliditylang.org/en/latest/)

MaxAPY is a yield farming **gas-optimized** and **capital-efficient** vault implemented in Solidity, designed to **optimize yield** through various strategies, and earn interest in ERC20 tokens. It relies on the safety of the battle-tested [Yearn&#39;s yVault](https://github.com/yearn/yearn-vaults/blob/efb47d8a84fcb13ceebd3ceb11b126b323bcc05d/contracts/Vault.vy) and the innovation of MaxAPY.

## Contracts

```ml
├── src
│   ├── helpers
│   │   ├── AddressBook.sol
│   │   └── VaultTypes.sol
│   ├── interfaces
│   │   ├── IBalancer.sol
│   │   ├── ICellar.sol
│   │   ├── IConvexBooster.sol
│   │   ├── IConvexdETHFrxETHStrategy.sol
│   │   ├── IConvexRewards.sol
│   │   ├── ICurve.sol
│   │   ├── IMaxApyRouter.sol
│   │   ├── IMaxApyVault.sol
│   │   ├── ISommelierStrategy.sol
│   │   ├── IStakingRewardsMulti.sol
│   │   ├── IStrategy.sol
│   │   ├── IUniswap.sol
│   │   ├── IWETH.sol
│   │   ├── IWrappedTokenGateway.sol
│   │   ├── IWrappedToken.sol
│   │   ├── IYearnStrategy.sol
│   │   ├── IYVault.sol
│   │   └── IYVaultV3.sol
│   ├── lib
│   │   ├── ERC20.sol
│   │   ├── Initializable.sol
│   │   ├── OracleLibrary.sol
│   │   └── ReentrancyGuard.sol
│   ├── MaxApyRouter.sol
│   ├── MaxApyVault.sol
│   ├── strategies
│   │   ├── base
│   │   │   ├── BaseConvexStrategyPolygon.sol
│   │   │   ├── BaseConvexStrategy.sol
│   │   │   ├── BaseSommelierStrategy.sol
│   │   │   ├── BaseStrategy.sol
│   │   │   ├── BaseYearnV2Strategy.sol
│   │   │   └── BaseYearnV3Strategy.sol
│   │   ├── mainnet
│   │   │   ├── DAI
│   │   │   │   └── yearn
│   │   │   │       ├── YearnAjnaDAIStakingStrategy.sol
│   │   │   │       └── YearnDAIStrategy.sol
│   │   │   ├── USDC
│   │   │   │   ├── convex
│   │   │   │   │   └── ConvexCrvUSDWethCollateralStrategy.sol
│   │   │   │   ├── sommelier
│   │   │   │   │   └── SommelierTurboGHOStrategy.sol
│   │   │   │   └── yearn
│   │   │   │       ├── YearnLUSDStrategy.sol
│   │   │   │       └── YearnUSDCStrategy.sol
│   │   │   ├── USDT
│   │   │   │   └── yearn
│   │   │   │       └── YearnUSDTStrategy.sol
│   │   │   └── WETH
│   │   │       ├── convex
│   │   │       │   └── ConvexdETHFrxETHStrategy.sol
│   │   │       ├── sommelier
│   │   │       │   ├── SommelierMorphoEthMaximizerStrategy.sol
│   │   │       │   ├── SommelierStEthDepositTurboStEthStrategy.sol
│   │   │       │   ├── SommelierTurboDivEthStrategy.sol
│   │   │       │   ├── SommelierTurboEEthV2Strategy.sol
│   │   │       │   ├── SommelierTurboEthXStrategy.sol
│   │   │       │   ├── SommelierTurboEzEthStrategy.sol
│   │   │       │   ├── SommelierTurboRsEthStrategy.sol
│   │   │       │   ├── SommelierTurboStEthStrategy.sol
│   │   │       │   └── SommelierTurboSwEthStrategy.sol
│   │   │       └── yearn
│   │   │           ├── YearnAaveV3WETHLenderStrategy.sol
│   │   │           ├── YearnAjnaWETHStakingStrategy.sol
│   │   │           ├── YearnCompoundV3WETHLenderStrategy.sol
│   │   │           ├── YearnV3WETH2Strategy.sol
│   │   │           ├── YearnV3WETHStrategy.sol
│   │   │           └── YearnWETHStrategy.sol
│   │   └── polygon
│   │       ├── DAI
│   │       │   └── yearn
│   │       │       ├── YearnDAILenderStrategy.sol
│   │       │       └── YearnDAIStrategy.sol
│   │       ├── USDCe
│   │       │   └── yearn
│   │       │       ├── YearnAjnaUSDCStrategy.sol
│   │       │       ├── YearnCompoundUSDCeLenderStrategy.sol
│   │       │       ├── YearnMaticUSDCStakingStrategy.sol
│   │       │       ├── YearnUSDCeLenderStrategy.sol
│   │       │       └── YearnUSDCeStrategy.sol
│   │       └── USDT
│   │           ├── convex
│   │           │   └── ConvexUSDTCrvUSDStrategy.sol
│   │           └── yearn
│   │               └── YearnUSDTStrategy.sol
│   └── MaxApyVaultFactory.sol
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
