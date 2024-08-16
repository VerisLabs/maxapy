// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { BaseERC4626StrategyHandler } from "./base/BaseERC4626StrategyHandler.t.sol";
import { BaseSommelierStrategyWrapper } from "../../mock/BaseSommelierStrategyWrapper.sol";
import { MaxApyVault, ERC4626 } from "src/MaxApyVault.sol";
import { MockERC20 } from "../../mock/MockERC20.sol";
import { IStrategyWrapper } from "../../interfaces/IStrategyWrapper.sol";

contract BaseSommelierStrategyHandler is BaseERC4626StrategyHandler {
    constructor(
        MaxApyVault _vault,
        BaseSommelierStrategyWrapper _strategy,
        MockERC20 _token,
        ERC4626 _strategyUnderlyingVault
    )
        BaseERC4626StrategyHandler(_vault, IStrategyWrapper(address(_strategy)), _token, _strategyUnderlyingVault)
    { }
}
