// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";

// import { FRXETH_MAINNET } from "src/helpers/AddressBook.sol";
// import { IBeefyVault } from "src/interfaces/IBeefyVault.sol";
// import { ICurveLpPool } from "src/interfaces/ICurve.sol";
// import { IWETH } from "src/interfaces/IWETH.sol";
import { BaseBeefyCurveMetaPoolStrategy } from "src/strategies/base/BaseBeefyCurveMetaPoolStrategy.sol";
import { BaseBeefyStrategy, IMaxApyVault, SafeTransferLib } from "src/strategies/base/BaseBeefyStrategy.sol";

// import { console2 } from "forge-std/console2.sol";

/// @title BeefythUSDDAIUSDCUSDTStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/strategies.sol
/// @notice `BeefythUSDDAIUSDCUSDTStrategy` supplies an underlying token into a generic Beefy Vault,
/// earning the Beefy Vault's yield
contract BeefythUSDDAIUSDCUSDTStrategy is BaseBeefyCurveMetaPoolStrategy {}
