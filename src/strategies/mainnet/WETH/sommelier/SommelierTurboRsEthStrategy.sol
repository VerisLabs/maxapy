// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { BaseSommelierStrategy, SafeTransferLib } from "src/strategies/base/BaseSommelierStrategy.sol";

/// @title SommelierTurboRsEthStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/strategies.sol
/// @notice `SommelierTurboRsEthStrategy` supplies an underlying token into a generic Sommelier Vault,
/// earning the Sommelier Vault's yield
contract SommelierTurboRsEthStrategy is BaseSommelierStrategy { }
