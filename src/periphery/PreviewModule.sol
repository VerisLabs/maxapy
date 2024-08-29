// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { IStrategyWrapper } from "../../test/interfaces/IStrategyWrapper.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";
import { IYVaultV3 } from "src/interfaces/IYVaultV3.sol";
import { IYVault } from "src/interfaces/IYVault.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { ICurveLpPool, ICurveLendingPool } from "../../test/interfaces/ICurve.sol";


/// @title PreviewModule
/// @notice helper contract that implements the logic to preview all the money flow
/// in strategy harvests
contract PreviewModule {
    ////////////////////////////////////////////////////////////////
    ///                        CONSTANTS                         ///
    ////////////////////////////////////////////////////////////////
    uint256 internal DEGRADATION_COEFFICIENT = 10 ** 18;

    ////////////////////////////////////////////////////////////////
    ///                     VIEW FUNCTIONS                       ///
    ////////////////////////////////////////////////////////////////
    /// @notice simulates the investment of a strategy after harvesting it
    /// @param strategy instance of strategy to preview
    function previewInvest(IStrategyWrapper strategy, uint256 amount) public view returns (uint256 investedAmount) {
        uint256 strategyType = _getStrategyType(strategy);
        IMaxApyVault vault = IMaxApyVault(strategy.vault());
        uint256 minSingleTrade;

        try strategy.minSingleTrade() returns (uint256 _minSingleTrade) {
            minSingleTrade = _minSingleTrade;
        } catch { }

        /// Yearn V2
        if (strategyType == 1) {
            if (amount > minSingleTrade) {
                IYVault yVault = IYVault(strategy.yVault());
                return _shareValue(yVault, _sharesForAmount(yVault, amount));
            }
        }
        /// Yearn V3
        else if (strategyType == 2) {
            if (amount > minSingleTrade) {
                IYVaultV3 yVault = IYVaultV3(strategy.yVault());
                return yVault.convertToAssets(yVault.previewDeposit(amount));
            }
        }
        /// Sommelier
        else if (strategyType == 3) {
            if (amount > minSingleTrade) {
                IYVaultV3 cellar = IYVaultV3(strategy.cellar());
                return cellar.convertToAssets(cellar.previewDeposit(amount));
            }
        }
        /// Convex Lp Pool
        else if (strategyType == 4) {
            if (amount > minSingleTrade) {
                uint256 shares = ICurveLpPool(strategy.curveLpPool()).previewDeposit();

            }
        }
        /// Convex Lending Pool
        else if (strategyType == 5) {
            if (amount > minSingleTrade) {
                ICurveLendingPool lendingPool = ICurveLendingPool(strategy.curveLendingPool());
                return lendingPool.previewRedeem(lendingPool.previewDeposit(amount));
            }
        }
        /// Other
        else {
            revert();
        }
    }
    /// @notice simulates the divestment of a strategy after harvesting it
    /// @param strategy instance of strategy to preview
    function previewDivest(IStrategyWrapper strategy, uint256 amount) public view returns (uint256) {
        int256 unharvestedAmount = strategy.unharvestedAmount();
        if (unharvestedAmount < 0) return 0;
        IMaxApyVault vault = IMaxApyVault(strategy.vault());
        return strategy.previewLiquidate(amount);
    }

    /// @notice returns the type of the strategy
    /// @param strategy instance
    /// @return _strategyType strategy type as integer
    function _getStrategyType(IStrategyWrapper strategy) internal view returns (uint256 _strategyType) {
        try strategy.yVault() returns (address _yVault) {
            IYVaultV3 vault = IYVaultV3(_yVault);
            try vault.asset() returns (address _asset) {
                _asset;
                return 2;
            } catch {
                return 1;
            }
        } catch { }

        try strategy.cellar() returns (address _cellar) {
            _cellar;
            return 3;
        } catch { }

        try strategy.curveLpPool() returns (address _curveLpPool) {
            _curveLpPool;
            return 4;
        } catch { }

        try strategy.curveLendingPool() returns (address _curveLendingPool) {
            _curveLendingPool;
            return 5;
        } catch { }
    }

    /// @notice Determines the current value of `shares`.
    /// @dev if sqrt(yVault.totalAssets()) >>> 1e39, this could potentially revert
    /// @return returns the estimated amount of underlying computed from shares `shares`
    function _shareValue(IYVault yVault, uint256 shares) internal view virtual returns (uint256) {
        uint256 vaultTotalSupply;
        assembly {
            // get yVault.totalSupply()
            mstore(0x00, 0x18160ddd)
            if iszero(staticcall(gas(), sload(yVault), 0x1c, 0x04, 0x00, 0x20)) { revert(0x00, 0x04) }
            vaultTotalSupply := mload(0x00)
        }
        if (vaultTotalSupply == 0) return shares;

        return Math.mulDiv(shares, _freeFunds(yVault), vaultTotalSupply);
    }

    /// @notice Determines how many shares depositor of `amount` of underlying would receive.
    /// @return shares returns the estimated amount of shares computed in exchange for the underlying `amount`
    function _sharesForAmount(IYVault yVault, uint256 amount) internal view virtual returns (uint256 shares) {
        uint256 freeFunds = _freeFunds(yVault);
        assembly {
            // if freeFunds != 0 return amount
            if gt(freeFunds, 0) {
                // get yVault.totalSupply()
                mstore(0x00, 0x18160ddd)
                if iszero(staticcall(gas(), yVault, 0x1c, 0x04, 0x00, 0x20)) { revert(0x00, 0x04) }
                let totalSupply := mload(0x00)

                // Overflow check equivalent to require(totalSupply == 0 || amount <= type(uint256).max / totalSupply)
                if iszero(iszero(mul(totalSupply, gt(amount, div(not(0), totalSupply))))) { revert(0, 0) }

                shares := div(mul(amount, totalSupply), freeFunds)
            }
        }
    }

    /// @notice Calculates the yearn vault free funds considering the locked profit
    /// @return returns the computed yearn vault free funds
    function _freeFunds(IYVault yVault) internal view returns (uint256) {
        return yVault.totalAssets() - _calculateLockedProfit(yVault);
    }

    /// @notice Calculates the yearn vault locked profit i.e. how much profit is locked and cant be withdrawn
    /// @return lockedProfit returns the computed locked profit value
    function _calculateLockedProfit(IYVault yVault) internal view returns (uint256 lockedProfit) {
        assembly {
            let _degradationCoefficient := sload(DEGRADATION_COEFFICIENT.slot)

            // get yVault.lastReport()
            mstore(0x00, 0xc3535b52)
            if iszero(staticcall(gas(), yVault, 0x1c, 0x04, 0x00, 0x20)) { revert(0x00, 0x04) }
            let lastReport := mload(0x00)
            // get yVault.lockedProfitDegradation()
            mstore(0x00, 0x42232716)
            if iszero(staticcall(gas(), yVault, 0x1c, 0x04, 0x00, 0x20)) { revert(0x00, 0x04) }
            let lockedProfitDegradation := mload(0x00)

            // Check overflow
            if gt(lastReport, timestamp()) { revert(0, 0) }

            //temporary value to save gas
            let lockedFundsRatio := sub(timestamp(), lastReport)

            // Overflow check equivalent to require(lockedProfitDegradation == 0 || lockedFundsRatio <=
            // type(uint256).max / lockedProfitDegradation)
            if iszero(iszero(mul(lockedProfitDegradation, gt(lockedFundsRatio, div(not(0), lockedProfitDegradation)))))
            {
                revert(0, 0)
            }

            lockedFundsRatio := mul(lockedFundsRatio, lockedProfitDegradation)

            //if (lockedFundsRatio < DEGRADATION_COEFFICIENT)
            if lt(lockedFundsRatio, _degradationCoefficient) {
                // get yVault.lockedProfit()
                mstore(0x00, 0x44b81396)
                if iszero(staticcall(gas(), yVault, 0x1c, 0x04, 0x00, 0x20)) { revert(0x00, 0x04) }
                lockedProfit := mload(0x00)

                // Overflow check equivalent to require(lockedProfit == 0 || lockedFundsRatio <= type(uint256).max /
                // lockedProfit)
                if iszero(iszero(mul(lockedProfit, gt(lockedFundsRatio, div(not(0), lockedProfit))))) { revert(0, 0) }

                //return lockedProfit - ((lockedFundsRatio * lockedProfit) / _degradationCoefficient);
                lockedProfit := sub(lockedProfit, div(mul(lockedFundsRatio, lockedProfit), _degradationCoefficient))
            }
        }
    }

    /// @notice Determines how many lp tokens depositor of `amount` of underlying would receive.
    /// @dev Some loss of precision is occured, but it is not critical as this is only an underestimation of
    /// the actual assets, and profit will be later accounted for.
    /// @return returns the estimated amount of lp tokens computed in exchange for underlying `amount`
    function _lpValue(uint256 lp) internal view virtual returns (uint256) {
        return (lp * _lpPrice()) / 1e18;
    }

    /// @notice Determines how many lp tokens depositor of `amount` of underlying would receive.
    /// @return returns the estimated amount of lp tokens computed in exchange for underlying `amount`
    function _lpForAmount(uint256 amount) internal view virtual returns (uint256) {
        return (amount * 1e18) / _lpPrice();
    }

    /// @notice Returns the estimated price for the strategy's Convex's LP token
    /// @return returns the estimated lp token price
    function _lpPrice() internal view virtual returns (uint256);
}
