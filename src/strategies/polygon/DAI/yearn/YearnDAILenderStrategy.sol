// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { BaseYearnV3Strategy, IMaxApyVault, SafeTransferLib } from "src/strategies/base/BaseYearnV3Strategy.sol";

/// @title YearnDAILenderStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/strategies.sol
/// @notice `YearnDAILenderStrategy` supplies an underlying token into a generic Yearn Vault,
/// earning the Yearn Vault's yield
contract YearnDAILenderStrategy is BaseYearnV3Strategy { }
