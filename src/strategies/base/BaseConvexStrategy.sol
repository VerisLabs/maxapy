// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { BaseStrategy, IMaxApyVault, SafeTransferLib } from "src/strategies/base/BaseStrategy.sol";
import { IConvexRewards } from "src/interfaces/IConvexRewards.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";

/// @title BaseConvexStrategy
/// @author MaxApy
/// @notice `BaseConvexStrategy` sets the base functionality to be implemented by MaxApy Convex strategies.
/// @dev Some functions can be overriden if needed
abstract contract BaseConvexStrategy is BaseStrategy {
    using SafeTransferLib for address;

    ////////////////////////////////////////////////////////////////
    ///                         ERRORS                           ///
    ////////////////////////////////////////////////////////////////
    error ConvexPoolShutdown();
    error InvalidCoinIndex();
    error NotEnoughFundsToInvest();
    error InvalidZeroAddress();
    error CurveWithdrawAdminFeesFailed();
    error InvalidHarvestedProfit();
    error MinOutputAmountNotReached();
    error InvalidZeroAmount();
    error MinExpectedBalanceAfterSwapNotReached();

    ////////////////////////////////////////////////////////////////
    ///                         EVENTS                           ///
    ////////////////////////////////////////////////////////////////

    /// @notice Emitted when underlying asset is deposited into Convex
    event Invested(address indexed strategy, uint256 amountInvested);

    /// @notice Emitted when the `requestedShares` are divested from Convex
    event Divested(address indexed strategy, uint256 amountDivested);

    /// @notice Emitted when the strategy's max single trade value is updated
    event MaxSingleTradeUpdated(uint256 maxSingleTrade);

    /// @notice Emitted when the min swap for crv token is updated
    event MinSwapCrvUpdated(uint256 newMinSwapCrv);

    /// @notice Emitted when the min swap for cvx token is updated
    event MinSwapCvxUpdated(uint256 newMinSwapCvx);

    /// @notice Emitted when the router is updated
    event RouterUpdated(address newRouter);

    /// @dev `keccak256(bytes("Invested(address,uint256)"))`.
    uint256 internal constant _INVESTED_EVENT_SIGNATURE =
        0xc3f75dfc78f6efac88ad5abb5e606276b903647d97b2a62a1ef89840a658bbc3;

    /// @dev `keccak256(bytes("Divested(address,uint256)"))`.
    uint256 internal constant _DIVESTED_EVENT_SIGNATURE =
        0x2253aebe2fe8682635bbe60d9b78df72efaf785a596910a8ad66e8c6e37584fd;

    /// @dev `keccak256(bytes("MaxSingleTradeUpdated(uint256)"))`.
    uint256 internal constant _MAX_SINGLE_TRADE_UPDATED_EVENT_SIGNATURE =
        0xe8b08f84dc067e4182670384e9556796d3a831058322b7e55f9ddb3ec48d7c10;

    /// @dev `keccak256(bytes("MinSwapCrvUpdated(uint256)"))`.
    uint256 internal constant _MIN_SWAP_CRV_UPDATED_EVENT_SIGNATURE =
        0x404d194eed8bead0d0fcfd4ac84a258a6bb29cd2b997166137d0324563d0bf24;

    /// @dev `keccak256(bytes("MinSwapCvxUpdated(uint256)"))`.
    uint256 internal constant _MIN_SWAP_CVX_UPDATED_EVENT_SIGNATURE =
        0x2f0d6e0ffbe791dbba2e5087b74693bf6c57a13062b3fbd6991106624e269fc3;

    /// @dev `keccak256(bytes("RouterUpdated(address)"))`.
    uint256 internal constant _ROUTER_UPDATED_EVENT_SIGNATURE =
        0x7aed1d3e8155a07ccf395e44ea3109a0e2d6c9b29bbbe9f142d9790596f4dc80;

    ////////////////////////////////////////////////////////////////
    ///            STRATEGY GLOBAL STATE VARIABLES               ///
    ////////////////////////////////////////////////////////////////

    /*==================CONVEX-RELATED STORAGE VARIABLES==================*/
    /// @notice Main Convex's reward contract for all Convex LP pools
    IConvexRewards public convexRewardPool;
    /// @notice Convex pool's lp token address
    address public convexLpToken;
    /// @notice Main reward token for `convexRewardPool`
    address public rewardToken;

    /*==================STRATEGY'S STORAGE VARIABLES==================*/

    /// @notice The maximum single trade allowed in the strategy
    uint256 public maxSingleTrade;
    /// @notice miminum amount allowed to swap for CRV tokens
    uint256 public minSwapCrv;
    /// @notice miminum amount allowed to swap for CVX tokens
    uint256 public minSwapCvx;

    ////////////////////////////////////////////////////////////////
    ///                     INITIALIZATION                       ///
    ////////////////////////////////////////////////////////////////
    constructor() initializer { }

    ////////////////////////////////////////////////////////////////
    ///                 STRATEGY CONFIGURATION                   ///
    ////////////////////////////////////////////////////////////////

    /// @notice Sets the maximum single trade amount allowed
    /// @param _maxSingleTrade The new maximum single trade value
    function setMaxSingleTrade(uint256 _maxSingleTrade) external checkRoles(ADMIN_ROLE) {
        assembly ("memory-safe") {
            // revert if `_maxSingleTrade` is zero
            if iszero(_maxSingleTrade) {
                // throw the `InvalidZeroAmount` error
                mstore(0x00, 0xdd484e70)
                revert(0x1c, 0x04)
            }

            sstore(maxSingleTrade.slot, _maxSingleTrade) // set the max single trade value in storage

            // Emit the `MaxSingleTradeUpdated` event
            mstore(0x00, _maxSingleTrade)
            log1(0x00, 0x20, _MAX_SINGLE_TRADE_UPDATED_EVENT_SIGNATURE)
        }
    }

    /// @notice Sets the new minimum swap allowed for the CRV token
    /// @param _minSwapCrv The new minimum swap value
    function setMinSwapCrv(uint256 _minSwapCrv) external checkRoles(ADMIN_ROLE) {
        assembly ("memory-safe") {
            sstore(minSwapCrv.slot, _minSwapCrv) // set the min swap in storage

            // Emit the `MinSwapCrvUpdated` event
            mstore(0x00, _minSwapCrv)
            log1(0x00, 0x20, _MIN_SWAP_CRV_UPDATED_EVENT_SIGNATURE)
        }
    }

    /// @notice Sets the new minimum swap allowed for the CVX token
    /// @param _minSwapCvx The new minimum swap value
    function setMinSwapCvx(uint256 _minSwapCvx) external checkRoles(ADMIN_ROLE) {
        assembly ("memory-safe") {
            sstore(minSwapCvx.slot, _minSwapCvx) // set the min swap in storage

            // Emit the `MinSwapCvxUpdated` event
            mstore(0x00, _minSwapCvx)
            log1(0x00, 0x20, _MIN_SWAP_CVX_UPDATED_EVENT_SIGNATURE)
        }
    }

    ////////////////////////////////////////////////////////////////
    ///                    VIEW FUNCTIONS                        ///
    ////////////////////////////////////////////////////////////////

    /// @notice This function is meant to be called from the vault
    /// @dev calculates the estimated real output of a withdrawal(including losses) for a @param requestedAmount
    /// for the vault to be able to provide an accurate amount when calling `previewRedeem`
    /// @return liquidatedAmount output in assets
    function previewLiquidate(uint256 requestedAmount)
        public
        view
        virtual
        override
        returns (uint256 liquidatedAmount);

    /// @notice This function is meant to be called from the vault
    /// @dev calculates the estimated @param requestedAmount the vault has to request to this strategy
    /// in order to actually get @param liquidatedAmount assets when calling `previewWithdraw`
    /// @return requestedAmount
    function previewLiquidateExact(uint256 liquidatedAmount)
        public
        view
        virtual
        override
        returns (uint256 requestedAmount)
    {
        uint256 underlyingBalance = _underlyingBalance();
        if (underlyingBalance < liquidatedAmount) {
            requestedAmount = liquidatedAmount - underlyingBalance;
            // increase 1% to be pessimistic
            requestedAmount = previewLiquidate(requestedAmount) * 101 / 100;
        }
        return requestedAmount + underlyingBalance;
    }

    /// @notice Returns the max amount of assets that the strategy can withdraw after losses
    function maxLiquidate() public view override returns (uint256) {
        return _estimatedTotalAssets();
    }

    /// @notice Returns the max amount of assets that the strategy can liquidate, before realizing losses
    function maxLiquidateExact() public view virtual override returns (uint256) {
        return previewLiquidate(_estimatedTotalAssets()) * 99 / 100;
    }

    /// @notice Returns the amount of Curve LP tokens staked in Convex
    /// @return the amount of staked LP tokens
    function stakedBalance() external view virtual returns (uint256) {
        return _stakedBalance(convexRewardPool);
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL CORE FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////
    /// @notice Perform any Strategy unwinding or other calls necessary to capture the
    /// "free return" this Strategy has generated since the last time its core
    /// position(s) were adjusted. Examples include unwrapping extra rewards.
    /// This call is only used during "normal operation" of a Strategy, and
    /// should be optimized to minimize losses as much as possible.
    /// @dev This method returns any realized profits and/or realized losses
    /// incurred, and should return the total amounts of profits/losses/debt
    /// payments (in MaxApy Vault's `underlyingAsset` tokens) for the MaxApy Vault's accounting (e.g.
    /// `underlyingAsset.balanceOf(this) >= debtPayment + profit`).
    ///
    /// `debtOutstanding` will be 0 if the Strategy is not past the configured
    /// debt limit, otherwise its value will be how far past the debt limit
    /// the Strategy is. The Strategy's debt limit is configured in the MaxApy Vault.
    ///
    /// NOTE: `debtPayment` should be less than or equal to `debtOutstanding`.
    ///       It is okay for it to be less than `debtOutstanding`, as that
    ///       should only be used as a guide for how much is left to pay back.
    ///       Payments should be made to minimize loss from slippage, debt,
    ///       withdrawal fees, etc.
    /// See `MaxApy.debtOutstanding()`.
    function _prepareReturn(
        uint256 debtOutstanding,
        uint256 minExpectedBalance
    )
        internal
        override
        returns (uint256 unrealizedProfit, uint256 loss, uint256 debtPayment)
    {
        // Cache reward pool
        IConvexRewards rewardPool = convexRewardPool;

        _unwindRewards(rewardPool);

        uint256 underlyingBalance = _underlyingBalance();
        uint256 _estimatedTotalAssets_ = _estimatedTotalAssets();
        uint256 _lastEstimatedTotalAssets = lastEstimatedTotalAssets;

        assembly {
            // If current underlying balance after swapping does not match swap output expectations, revert
            if gt(minExpectedBalance, underlyingBalance) {
                // throw the `MinExpectedBalanceAfterSwapNotReached` error
                mstore(0x00, 0xf52187c0)
                revert(0x1c, 0x04)
            }
        }

        uint256 debt;
        assembly {
            // debt = vault.strategies(address(this)).strategyTotalDebt;
            mstore(0x00, 0xd81d5e87)
            mstore(0x20, address())
            if iszero(call(gas(), sload(vault.slot), 0, 0x1c, 0x24, 0x00, 0x20)) { revert(0x00, 0x04) }
            debt := mload(0x00)
        }

        // initialize the lastEstimatedTotalAssets in case it is not
        if (_lastEstimatedTotalAssets == 0) _lastEstimatedTotalAssets = debt;

        assembly {
            switch lt(_estimatedTotalAssets_, _lastEstimatedTotalAssets)
            // if _estimatedTotalAssets_ < _lastEstimatedTotalAssets
            case true { loss := sub(_lastEstimatedTotalAssets, _estimatedTotalAssets_) }
            // else
            case false { unrealizedProfit := sub(_estimatedTotalAssets_, _lastEstimatedTotalAssets) }
        }

        if (_estimatedTotalAssets_ >= _lastEstimatedTotalAssets) {
            // Strategy has obtained profit or holds more funds than it should
            // considering the current debt

            // Cannot repay all debt if it does not have enough assets
            uint256 amountToWithdraw = Math.min(debtOutstanding, _estimatedTotalAssets_);

            // Check if underlying funds held in the strategy are enough to cover withdrawal.
            // If not, divest from Convex
            if (amountToWithdraw > underlyingBalance) {
                uint256 expectedAmountToWithdraw = Math.min(maxSingleTrade, amountToWithdraw - underlyingBalance);

                // We cannot withdraw more than actual balance
                expectedAmountToWithdraw =
                    Math.min(expectedAmountToWithdraw, _lpValue(_stakedBalance(convexRewardPool)));

                uint256 lpToWithdraw = _lpForAmount(expectedAmountToWithdraw);

                uint256 staked = _stakedBalance(convexRewardPool);

                if (lpToWithdraw > staked) {
                    lpToWithdraw = staked;
                }

                uint256 withdrawn = _divest(lpToWithdraw);

                // Account for loss occured on withdrawal from Convex
                if (withdrawn < expectedAmountToWithdraw) {
                    unchecked {
                        loss = expectedAmountToWithdraw - withdrawn;
                    }
                }
                // Overwrite underlyingBalance with the proper amount after withdrawing
                underlyingBalance = _underlyingBalance();
            }

            assembly {
                // Net off unrealized profit and loss
                switch lt(unrealizedProfit, loss)
                // if (unrealizedProfit < loss)
                case true {
                    loss := sub(loss, unrealizedProfit)
                    unrealizedProfit := 0
                }
                case false {
                    unrealizedProfit := sub(unrealizedProfit, loss)
                    loss := 0
                }

                // `profit` + `debtOutstanding` must be <= `underlyingBalance`. Prioritise profit first
                switch gt(amountToWithdraw, underlyingBalance)
                case true {
                    // same as `profit` + `debtOutstanding` > `underlyingBalance`
                    // Extract debt payment from divested amount
                    debtPayment := underlyingBalance
                }
                case false { debtPayment := amountToWithdraw }
            }
        }
    }

    /// @notice Performs any adjustments to the core position(s) of this Strategy given
    /// what change the MaxApy Vault made in the "investable capital" available to the
    /// Strategy.
    /// @dev Note that all "free capital" (capital not invested) in the Strategy after the report
    /// was made is available for reinvestment. This number could be 0, and this scenario should be handled accordingly.
    /// Also note that other implementations might use the debtOutstanding param, but not this one.
    function _adjustPosition(uint256, uint256 minOutputAfterInvestment) internal virtual override {
        uint256 toInvest = _underlyingBalance();
        if (toInvest > 0) {
            _invest(toInvest, minOutputAfterInvestment);
        }
    }

    /// @notice Invests `amount` of underlying into the Convex pool
    /// @dev We don't perform any reward claim. All assets must have been
    /// previously converted to `underlyingAsset`.
    /// Note that because of Curve's bonus/penalty approach, we check if it is best to
    /// add liquidity with native ETH or with pegged ETH. It is then expected to always receive
    /// at least `amount` if we perform an exchange from ETH to pegged ETH.
    /// @param amount The amount of underlying to be deposited in the pool
    /// @param minOutputAfterInvestment minimum expected output after `_invest()` (designated in Curve LP tokens)
    /// @return The amount of tokens received, in terms of underlying
    function _invest(uint256 amount, uint256 minOutputAfterInvestment) internal virtual returns (uint256);

    /// @notice Divests amount `amount` from the Convex pool
    /// Note that divesting from the pool could potentially cause loss, so the divested amount might actually be
    /// different from
    /// the requested `amount` to divest
    /// @dev care should be taken, as the `amount` parameter is not in terms of underlying,
    /// but in terms of Curve's LP tokens
    /// Note that if minimum withdrawal amount is not reached, funds will not be divested, and this
    /// will be accounted as a loss later.
    /// @return the total amount divested, in terms of underlying asset
    function _divest(uint256 amount) internal virtual returns (uint256);

    /// @notice Liquidate up to `amountNeeded` of MaxApy vaul's `underlyingAsset` of this strategy's positions,
    /// irregardless of slippage. Any excess will be re-invested with `_adjustPosition()`.
    /// @dev This function should return the amount of MaxApy vault's `underlyingAsset` tokens made available by the
    /// liquidation. If there is a difference between `amountNeeded` and `liquidatedAmount`, `loss` indicates whether
    /// the
    /// difference is due to a realized loss, or if there is some other sitution at play
    /// (e.g. locked funds) where the amount made available is less than what is needed.
    /// NOTE: The invariant `liquidatedAmount + loss <= amountNeeded` should always be maintained
    /// @param amountNeeded amount of MaxApy vault's `underlyingAsset` needed to be liquidated
    /// @return liquidatedAmount the actual liquidated amount
    /// @return loss difference between the expected amount needed to reach `amountNeeded` and the actual liquidated
    /// amount
    function _liquidatePosition(uint256 amountNeeded)
        internal
        virtual
        override
        returns (uint256 liquidatedAmount, uint256 loss)
    {
        uint256 underlyingBalance = _underlyingBalance();

        // If underlying balance currently held by strategy is not enough to cover
        // the requested amount, we divest from Convex
        if (underlyingBalance < amountNeeded) {
            uint256 amountToWithdraw;
            unchecked {
                amountToWithdraw = amountNeeded - underlyingBalance;
            }

            uint256 lp = _lpForAmount(amountToWithdraw);

            uint256 staked = _stakedBalance(convexRewardPool);

            assembly {
                // Adjust computed lp amount by current lp balance
                if gt(lp, staked) { lp := staked }
            }

            if (lp == 0) return (0, 0);

            uint256 withdrawn = _divest(lp);

            assembly {
                if lt(withdrawn, amountToWithdraw) {
                    // if (withdrawn < amountToWithdraw)
                    loss := sub(amountToWithdraw, withdrawn) // loss = amountToWithdraw - withdrawn. Can never underflow
                }
            }
        }
        assembly {
            //  liquidatedAmount = amountNeeded - loss;
            liquidatedAmount := sub(amountNeeded, loss) // can never underflow
        }
    }

    /// @notice Liquidates everything and returns the amount that got freed.
    /// @dev This function is used during emergency exit instead of `_prepareReturn()` to
    /// liquidate all of the Strategy's positions back to the MaxApy vault.
    function _liquidateAllPositions() internal virtual override returns (uint256 amountFreed) {
        IConvexRewards rewardPool = convexRewardPool;
        _unwindRewards(convexRewardPool);
        _divest(_stakedBalance(rewardPool));
        amountFreed = _underlyingBalance();
    }

    /// @notice Claims rewards, converting them to `underlyingAsset`.
    /// @dev MinOutputAmounts are left as 0 and properly asserted globally on `harvest()`.
    function _unwindRewards(IConvexRewards rewardPool) internal virtual;

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL VIEW FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////

    /// @notice Returns the CVX token balane of the strategy
    /// @return The amount of CVX tokens held by the current contract
    function _cvxBalance() internal view returns (uint256) {
        return _cvx().balanceOf(address(this));
    }

    /// @notice Returns the CRV token balane of the strategy
    /// @return The amount of CRV tokens held by the current contract
    function _crvBalance() internal view returns (uint256) {
        return _crv().balanceOf(address(this));
    }

    /// @notice Returns the amount of Curve LP tokens staked in Convex
    /// @return the amount of staked LP tokens
    function _stakedBalance(IConvexRewards rewardPool) internal view returns (uint256) {
        return rewardPool.balanceOf(address(this));
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

    /// @notice Returns the real time estimation of the value in assets held by the strategy
    /// @return the strategy's total assets(idle + investment positions)
    function _estimatedTotalAssets() internal view virtual override returns (uint256) {
        return _underlyingBalance() + _lpValue(_stakedBalance(convexRewardPool));
    }

    /// @dev returns the address of the CRV token for this context
    function _crv() internal pure virtual returns (address);

    /// @dev returns the address of the CVX token for this context
    function _cvx() internal pure virtual returns (address);
}
