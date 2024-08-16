// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { BaseHandler, console2 } from "./BaseHandler.t.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { MaxApyVault } from "src/MaxApyVault.sol";

abstract contract BaseStrategyHandler is BaseHandler {
    ////////////////////////////////////////////////////////////////
    ///                      GHOST VARIABLES                     ///
    ////////////////////////////////////////////////////////////////
    uint256 public expectedEstimatedTotalAssets;
    uint256 public actualEstimatedTotalAssets;

    ////////////////////////////////////////////////////////////////
    ///                      ENTRY POINTS                        ///
    ////////////////////////////////////////////////////////////////
    function harvest() public virtual;

    function gain(uint256 amount) public virtual;

    function triggerLoss(uint256 amount) public virtual;

    ////////////////////////////////////////////////////////////////
    ///                      HELPERS                             ///
    ////////////////////////////////////////////////////////////////
    function getEntryPoints() public pure override returns (bytes4[] memory) {
        bytes4[] memory _entryPoints = new bytes4[](3);
        _entryPoints[0] = this.harvest.selector;
        _entryPoints[1] = this.gain.selector;
        _entryPoints[2] = this.triggerLoss.selector;
        return _entryPoints;
    }

    function callSummary() public view override {
        console2.log("");
        console2.log("");
        console2.log("Call summary:");
        console2.log("-------------------");
        console2.log("gain", calls["gain"]);
        console2.log("trigerLoss", calls["trigerLoss"]);
        console2.log("harvest", calls["harvest"]);
        console2.log("-------------------");
    }

    uint256 constant MAX_BPS = 10_000;

    struct TempVars {
        uint256 vaultTotalAssets;
        uint256 vaultDebtLimit;
        uint256 vaultTotalDebt;
        uint256 vaultDebtRatio;
        uint256 strategyDebtRatio;
        uint256 strategyLastReport;
        uint256 strategyMaxDebtPerHarvest;
        uint256 strategyMinDebtPerHarvest;
        uint256 strategyTotalDebt;
        uint256 ratioChange;
    }

    function _creditAvailableAfterLoss(
        MaxApyVault vault,
        address strategy,
        uint256 loss
    )
        internal
        view
        returns (uint256)
    {
        TempVars memory temp;
        temp.vaultTotalAssets = vault.totalDeposits();
        temp.vaultTotalDebt = vault.totalDebt();
        temp.vaultDebtRatio = vault.debtRatio();
        (
            uint16 _strategyDebtRatio,
            ,
            ,
            uint48 _strategyLastReport,
            uint128 _strategyMaxDebtPerHarvest,
            uint128 _strategyMinDebtPerHarvest,
            ,
            uint128 _strategyTotalDebt,
            ,
        ) = vault.strategies(strategy);
        temp.strategyDebtRatio = uint256(_strategyDebtRatio);
        temp.strategyLastReport = uint256(_strategyLastReport);
        temp.strategyMaxDebtPerHarvest = uint256(_strategyMaxDebtPerHarvest);
        temp.strategyMinDebtPerHarvest = uint256(_strategyMinDebtPerHarvest);
        temp.strategyTotalDebt = uint256(_strategyTotalDebt);

        // report loss
        if (loss > temp.strategyTotalDebt) {
            loss = temp.strategyTotalDebt;
        }

        if (temp.vaultTotalDebt > 0) {
            temp.ratioChange = Math.min((loss * temp.vaultDebtRatio) / temp.vaultTotalDebt, temp.strategyDebtRatio);
        }

        // reduce debt => OK
        temp.vaultDebtRatio -= temp.ratioChange;
        temp.vaultTotalDebt -= loss;
        temp.strategyDebtRatio -= temp.ratioChange;
        temp.strategyTotalDebt -= loss;
        temp.vaultTotalAssets -= loss;

        // Compute necessary data regarding current state of the vault
        temp.vaultDebtLimit = _computeDebtLimit(temp.vaultDebtRatio, temp.vaultTotalAssets);
        require(temp.vaultTotalAssets == 0 || temp.strategyDebtRatio <= type(uint256).max / temp.vaultTotalAssets);
        uint256 strategyDebtLimit = (temp.strategyDebtRatio * temp.vaultTotalAssets) / MAX_BPS;

        if (temp.strategyTotalDebt > strategyDebtLimit || temp.vaultTotalDebt > temp.vaultDebtLimit) {
            return 0;
        }

        uint256 available;
        unchecked {
            available = Math.min(strategyDebtLimit - temp.strategyTotalDebt, temp.vaultDebtLimit - temp.vaultTotalDebt);
        }

        // Adjust by the idle amount of underlying the vault has
        available = Math.min(available, vault.totalIdle());
        return Math.min(available, temp.strategyMaxDebtPerHarvest);
    }

    function _computeDebtLimit(uint256 _debtRatio, uint256 totalAssets_) internal pure returns (uint256 debtLimit) {
        require(totalAssets_ == 0 || _debtRatio <= type(uint256).max / totalAssets_);
        return _debtRatio * totalAssets_ / MAX_BPS;
    }

    ////////////////////////////////////////////////////////////////
    ///                      INVARIANTS                          ///
    ////////////////////////////////////////////////////////////////
    function INVARIANT_A_ESTIMATED_TOTAL_ASSETS() public view virtual;
}
