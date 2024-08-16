// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { MockERC20 } from "./MockERC20.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

contract MockYVaultV2 is MockERC20 {
    using SafeTransferLib for address;
    ////////////////////////////////////////////////////////////////
    ///                         CONSTANTS                        ///
    ////////////////////////////////////////////////////////////////

    uint256 public constant MAX_BPS = 10_000;
    uint256 public constant DEGRADATION_COEFFICIENT = 1e18;

    /// @notice block.timestamp of last report
    uint256 public lastReport;
    /// @notice How much profit is locked and cant be withdrawn
    uint256 public lockedProfit;
    /// @notice Rate per block of degradation. DEGRADATION_COEFFICIENT is 100% per block
    uint256 public lockedProfitDegradation;

    address asset;

    constructor(address underlying_, string memory name_, string memory symbol_) MockERC20(name_, symbol_, 18) {
        asset = underlying_;
        lastReport = block.timestamp;
        lockedProfitDegradation = (DEGRADATION_COEFFICIENT * 46) / 10 ** 6; // 6 hours in blocks
    }

    function deposit(uint256 amount) external returns (uint256) {
        if (amount == 0) revert();

        uint256 vaultTotalSupply = totalSupply();
        uint256 shares = amount;
        /// By default minting 1:1 shares

        if (vaultTotalSupply != 0) {
            /// Mint amount of tokens based on what the Vault is managing overall
            shares = (amount * vaultTotalSupply) / _freeFunds();
        }

        require(shares != 0, "zero shares");

        _mint(msg.sender, shares);

        asset.safeTransferFrom(msg.sender, address(this), amount);

        return shares;
    }

    function withdraw(uint256 shares) external returns (uint256) {
        require(shares != 0, "0 shares");

        uint256 valueToWithdraw = _shareValue(shares);
        _burn(msg.sender, shares);
        asset.safeTransfer(msg.sender, valueToWithdraw);
        return valueToWithdraw;
    }

    function totalAssets() external view returns (uint256) {
        return _totalAssets();
    }

    function _shareValue(uint256 shares) internal view returns (uint256 shareValue) {
        uint256 totalSupply_ = totalSupply();
        // Return price = 1:1 if vault is empty
        if (totalSupply_ == 0) return shares;
        uint256 freeFunds = _freeFunds();
        assembly {
            // Overflow check equivalent to require(freeFunds == 0 || shares <= type(uint256).max / freeFunds)
            if iszero(iszero(mul(freeFunds, gt(shares, div(not(0), freeFunds))))) { revert(0, 0) }
            // shares * freeFunds / totalSupply_
            shareValue := div(mul(shares, freeFunds), totalSupply_)
        }
    }

    function _freeFunds() internal view returns (uint256) {
        return _totalAssets() - _calculateLockedProfit();
    }

    function _totalAssets() internal view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function _calculateLockedProfit() internal view returns (uint256 calculatedLockedProfit) {
        assembly {
            // No need to check for underflow, since block.timestamp is always greater or equal than lastReport
            let difference := sub(timestamp(), sload(lastReport.slot)) // difference = block.timestamp - lastReport
            let lockedProfitDegradation_ := sload(lockedProfitDegradation.slot)

            // Overflow check equivalent to require(lockedProfitDegradation_ == 0 || difference <= type(uint256).max /
            // lockedProfitDegradation_)
            if iszero(iszero(mul(lockedProfitDegradation_, gt(difference, div(not(0), lockedProfitDegradation_))))) {
                revert(0, 0)
            }

            // lockedFundsRatio = (block.timestamp - lastReport) * lockedProfitDegradation
            let lockedFundsRatio := mul(difference, lockedProfitDegradation_)

            if lt(lockedFundsRatio, DEGRADATION_COEFFICIENT) {
                let vaultLockedProfit := sload(lockedProfit.slot)
                // Overflow check equivalent to require(vaultLockedProfit == 0 || lockedFundsRatio <= type(uint256).max
                // / vaultLockedProfit)
                if iszero(iszero(mul(vaultLockedProfit, gt(lockedFundsRatio, div(not(0), vaultLockedProfit))))) {
                    revert(0, 0)
                }
                // ((lockedFundsRatio * vaultLockedProfit) / DEGRADATION_COEFFICIENT
                let degradation := div(mul(lockedFundsRatio, vaultLockedProfit), DEGRADATION_COEFFICIENT)
                // Overflow check
                if gt(degradation, vaultLockedProfit) { revert(0, 0) }
                // calculatedLockedProfit = vaultLockedProfit - ((lockedFundsRatio * vaultLockedProfit) /
                // DEGRADATION_COEFFICIENT);
                calculatedLockedProfit := sub(vaultLockedProfit, degradation)
            }
        }
    }
}
