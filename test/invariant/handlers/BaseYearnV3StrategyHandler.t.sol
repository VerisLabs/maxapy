// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { IStrategyWrapper } from "../../interfaces/IStrategyWrapper.sol";
import { BaseYearnV3StrategyWrapper } from "../../mock/BaseYearnV3StrategyWrapper.sol";
import { MockERC20 } from "../../mock/MockERC20.sol";
import { BaseERC4626StrategyHandler } from "./base/BaseERC4626StrategyHandler.t.sol";
import { ERC4626, MaxApyVault } from "src/MaxApyVault.sol";

contract BaseYearnV3StrategyHandler is BaseERC4626StrategyHandler {
    constructor(
        MaxApyVault _vault,
        BaseYearnV3StrategyWrapper _strategy,
        MockERC20 _token,
        ERC4626 _strategyUnderlyingVault
    )
        BaseERC4626StrategyHandler(_vault, IStrategyWrapper(address(_strategy)), _token, _strategyUnderlyingVault)
    { }
}
