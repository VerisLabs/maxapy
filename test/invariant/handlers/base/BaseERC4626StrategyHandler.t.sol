// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { AddressSet, LibAddressSet } from "../../../helpers/AddressSet.sol";
import { IStrategyWrapper } from "../../../interfaces/IStrategyWrapper.sol";

import { MockERC20 } from "../../../mock/MockERC20.sol";
import { BaseStrategyHandler } from "./BaseStrategyHandler.t.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { ERC4626, MaxApyVault } from "src/MaxApyVault.sol";

contract BaseERC4626StrategyHandler is BaseStrategyHandler {
    MaxApyVault vault;
    IStrategyWrapper strategy;
    MockERC20 token;
    ERC4626 strategyUnderlyingVault;

    ////////////////////////////////////////////////////////////////
    ///                      SETUP                               ///
    ////////////////////////////////////////////////////////////////
    constructor(MaxApyVault _vault, IStrategyWrapper _strategy, MockERC20 _token, ERC4626 _strategyUnderlyingVault) {
        strategy = _strategy;
        token = _token;
        vault = _vault;
        strategyUnderlyingVault = _strategyUnderlyingVault;
    }

    ////////////////////////////////////////////////////////////////
    ///                      ENTRY POINTS                        ///
    ////////////////////////////////////////////////////////////////
    function gain(uint256 amount) public override countCall("gain") {
        amount = bound(amount, 0, 1_000_000 ether);
        token.mint(address(strategy), amount);
    }

    function triggerLoss(uint256 amount) public override countCall("triggerLoss") {
        int256 unharvestedAmount = strategy.unharvestedAmount();
        amount = bound(amount, 0, strategy.estimatedTotalAssets());
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
        assertEq(expectedEstimatedTotalAssets, actualEstimatedTotalAssets);
    }
}
