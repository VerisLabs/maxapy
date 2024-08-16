// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { BaseYearnV2Strategy, IMaxApyVault, SafeTransferLib } from "src/strategies/base/BaseYearnV2Strategy.sol";

/// @title YearnDAIStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/strategies.sol
/// @notice `YearnDAIStrategy` supplies an underlying token into a generic Yearn Vault,
/// earning the Yearn Vault's yield
contract YearnDAIStrategy is BaseYearnV2Strategy { }
