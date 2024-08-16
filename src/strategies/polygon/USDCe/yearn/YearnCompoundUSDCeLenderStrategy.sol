// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { BaseYearnV3Strategy, IMaxApyVault, SafeTransferLib } from "src/strategies/base/BaseYearnV3Strategy.sol";

/// @title YearnCompoundUSDCeLenderStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/strategies.sol
/// @notice `YearnCompoundUSDCeLenderStrategy` supplies an underlying token into a generic Yearn Vault,
/// earning the Yearn Vault's yield
contract YearnCompoundUSDCeLenderStrategy is BaseYearnV3Strategy { }
