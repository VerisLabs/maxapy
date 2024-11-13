// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { IBeefyVault } from "src/interfaces/IBeefyVault.sol";
import { ICurveLpPool } from "src/interfaces/ICurve.sol";
import { BaseBeefyCurveStrategy } from "src/strategies/base/BaseBeefyCurveStrategy.sol";
import { BaseBeefyStrategy, IMaxApyVault, SafeTransferLib } from "src/strategies/base/BaseBeefyStrategy.sol";

/// @title BeefyCrvUSDUSDCeStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/strategies.sol
/// @notice `BeefyCrvUSDUSDCeStrategy` supplies an underlying token into a generic Beefy Vault,
/// earning the Beefy Vault's yield
contract BeefyCrvUSDUSDCeStrategy is BaseBeefyCurveStrategy { }
