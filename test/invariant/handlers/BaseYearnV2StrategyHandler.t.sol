// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { AddressSet, LibAddressSet } from "../../helpers/AddressSet.sol";
import { BaseYearnV2StrategyWrapper } from "../../mock/BaseYearnV2StrategyWrapper.sol";
import { MaxApyVault } from "src/MaxApyVault.sol";
import { MockERC20 } from "../../mock/MockERC20.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { BaseStrategyHandler } from "./base/BaseStrategyHandler.t.sol";

contract BaseYearnV2StrategyHandler is BaseStrategyHandler {
    MaxApyVault vault;
    BaseYearnV2StrategyWrapper strategy;
    MockERC20 token;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////
    constructor(MaxApyVault _vault, BaseYearnV2StrategyWrapper _strategy, MockERC20 _token) {
        strategy = _strategy;
        token = _token;
        vault = _vault;
    }

    ////////////////////////////////////////////////////////////////
    ///                      ENTRY POINTS                        ///
    ////////////////////////////////////////////////////////////////
    function gain(uint256 amount) public override countCall("gain") {
        if (currentActor == address(0)) return;
        amount = bound(amount, 0, 1000 ether);
        token.mint(address(strategy), amount);
    }

    function triggerLoss(uint256 amount) public override countCall("triggerLoss") {
        int256 unharvestedAmount = strategy.unharvestedAmount();
        amount = bound(amount, 0, strategy.estimatedTotalAssets() * 99 / 100);
        if (amount == 0) return;

        if (unharvestedAmount >= 0 && amount < uint256(unharvestedAmount)) {
            expectedEstimatedTotalAssets = strategy.estimatedTotalAssets();
        } else if (unharvestedAmount >= 0 && amount >= uint256(unharvestedAmount)) {
            expectedEstimatedTotalAssets = strategy.estimatedTotalAssets() + uint256(unharvestedAmount) - amount;
        } else if (unharvestedAmount < 0) {
            expectedEstimatedTotalAssets = strategy.estimatedTotalAssets() - amount;
        }

        strategy.triggerLoss(amount);
        actualEstimatedTotalAssets = strategy.estimatedTotalAssets();
    }

    function harvest() public override countCall("harvest") {
        uint256 debtOutstanding = vault.debtOutstanding(address(strategy));
        int256 unharvestedAmount = strategy.unharvestedAmount();
        if (unharvestedAmount < 0) {
            uint256 creditAvailable = _creditAvailableAfterLoss(vault, address(strategy), uint256(-unharvestedAmount));
            expectedEstimatedTotalAssets = strategy.estimatedTotalAssets() + creditAvailable;
            strategy.harvest(0, 0, address(0), block.timestamp);
            actualEstimatedTotalAssets = strategy.estimatedTotalAssets();
        }

        if (unharvestedAmount >= 0) {
            uint256 creditAvailable = vault.creditAvailable(address(strategy));
            expectedEstimatedTotalAssets = strategy.estimatedTotalAssets() + uint256(unharvestedAmount)
                + creditAvailable - Math.min(debtOutstanding, strategy.estimatedTotalAssets() + uint256(unharvestedAmount));
            strategy.harvest(0, 0, address(0), block.timestamp);
            actualEstimatedTotalAssets = strategy.estimatedTotalAssets();
        }
    }

    ////////////////////////////////////////////////////////////////
    ///                      INVARIANTS                          ///
    ////////////////////////////////////////////////////////////////
    function INVARIANT_A_ESTIMATED_TOTAL_ASSETS() public view override {
        assertGe(expectedEstimatedTotalAssets, actualEstimatedTotalAssets);
    }
}
