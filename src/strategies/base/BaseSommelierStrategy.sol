// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { ICellar } from "src/interfaces/ICellar.sol";
import { IWETH } from "src/interfaces/IWETH.sol";
import { BaseStrategy, IERC20Metadata, IMaxApyVault, SafeTransferLib } from "src/strategies/base/BaseStrategy.sol";

import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";

/// @title BaseSommelierStrategy
/// @author MaxApy
/// @notice `BaseSommelierStrategy` sets the base functionality to be implemented by MaxApy Sommelier strategies.
/// @dev Some functions can be overriden if needed
contract BaseSommelierStrategy is BaseStrategy {
    using SafeTransferLib for address;

    ////////////////////////////////////////////////////////////////
    ///                         ERRORS                           ///
    ////////////////////////////////////////////////////////////////
    error NotEnoughFundsToInvest();
    error CellarIsPaused();
    error InvalidZeroAddress();

    ////////////////////////////////////////////////////////////////
    ///                         EVENTS                           ///
    ////////////////////////////////////////////////////////////////

    /// @notice Emitted when underlying asset is deposited into the Sommelier Vault
    event Invested(address indexed strategy, uint256 amountInvested);

    /// @notice Emitted when the `requestedShares` are divested from the Sommelier Vault
    event Divested(address indexed strategy, uint256 requestedShares, uint256 amountDivested);

    /// @notice Emitted when the strategy's min single trade value is updated
    event MinSingleTradeUpdated(uint256 minSingleTrade);

    /// @notice Emitted when the strategy's max single trade value is updated
    event MaxSingleTradeUpdated(uint256 maxSingleTrade);

    /// @dev `keccak256(bytes("Invested(uint256,uint256)"))`.
    uint256 internal constant _INVESTED_EVENT_SIGNATURE =
        0xc3f75dfc78f6efac88ad5abb5e606276b903647d97b2a62a1ef89840a658bbc3;

    /// @dev `keccak256(bytes("Divested(uint256,uint256,uint256)"))`.
    uint256 internal constant _DIVESTED_EVENT_SIGNATURE =
        0xf44b6ecb6421462dee6400bd4e3bb57864c0f428d0f7e7d49771f9fd7c30d4fa;

    /// @dev `keccak256(bytes("MaxSingleTradeUpdated(uint256)"))`.
    uint256 internal constant _MAX_SINGLE_TRADE_UPDATED_EVENT_SIGNATURE =
        0xe8b08f84dc067e4182670384e9556796d3a831058322b7e55f9ddb3ec48d7c10;

    /// @dev `keccak256(bytes("MinSingleTradeUpdated(uint256)"))`.
    uint256 internal constant _MIN_SINGLE_TRADE_UPDATED_EVENT_SIGNATURE =
        0x70bc59027d7d0bba6fbf38b995e26c84f6c1805fc3ead71ec1d7ebeb7d76399b;

    ////////////////////////////////////////////////////////////////
    ///            STRATEGY GLOBAL STATE VARIABLES               ///
    ////////////////////////////////////////////////////////////////

    /// @notice The Sommelier Vault the strategy interacts with
    ICellar public cellar;

    /// @notice The maximum single trade allowed in the strategy
    uint256 public maxSingleTrade;

    /// @notice Minimun trade size within the strategy
    uint256 public minSingleTrade;

    ////////////////////////////////////////////////////////////////
    ///                     INITIALIZATION                       ///
    ////////////////////////////////////////////////////////////////
    constructor() initializer { }

    /// @dev the initialization function must be defined in each strategy
    /// @notice Initialize the Strategy
    /// @param _vault The address of the MaxApy Vault associated to the strategy
    /// @param _keepers The addresses of the keepers to be added as valid keepers to the strategy
    /// @param _strategyName the name of the strategy
    /// @param _cellar The address of the Sommelier Turbo-stETH cellar
    function initialize(
        IMaxApyVault _vault,
        address[] calldata _keepers,
        bytes32 _strategyName,
        address _strategist,
        ICellar _cellar
    )
        public
        virtual
        initializer
    {
        __BaseStrategy_init(_vault, _keepers, _strategyName, _strategist);
        cellar = _cellar;
        /// Approve Cellar Vault to transfer underlying
        underlyingAsset.safeApprove(address(_cellar), type(uint256).max);

        /// Unlimited max single trade by default
        maxSingleTrade = type(uint256).max;
    }

    /////////////////////////////////////////////////////////////////
    ///                    CORE LOGIC                             ///
    /////////////////////////////////////////////////////////////////
    /// @notice Withdraws exactly `amountNeeded` to `vault`.
    /// @dev This may only be called by the respective Vault.
    /// @param amountNeeded How much `underlyingAsset` to withdraw.
    /// @return loss Any realized losses
    function liquidateExact(uint256 amountNeeded)
        external
        virtual
        override
        checkRoles(VAULT_ROLE)
        returns (uint256 loss)
    {
        uint256 underlyingBalance = _underlyingBalance();
        if (underlyingBalance < amountNeeded) {
            uint256 amountToWithdraw;
            unchecked {
                amountToWithdraw = amountNeeded - underlyingBalance;
            }
            uint256 burntShares = cellar.withdraw(amountToWithdraw, address(this), address(this));
            // use sub zero because shares could be fewer than expected and underflow
            loss = _sub0(_shareValue(burntShares), amountToWithdraw);
        }
        underlyingAsset.safeTransfer(address(vault), amountNeeded);
        // Note: Reinvest anything leftover on next `harvest`
        _snapshotEstimatedTotalAssets();
    }

    /////////////////////////////////////////////////////////////////
    ///                    VIEW FUNCTIONS                        ///
    ////////////////////////////////////////////////////////////////

    /// @notice This function is meant to be called from the vault
    /// @dev calculates estunated the real output of a withdrawal(including losses) for a @param requestedAmount
    /// for the vault to be able to provide an accurate amount when calling `previewRedeem`
    /// @return liquidatedAmount output in assets
    function previewLiquidate(uint256 requestedAmount)
        public
        view
        virtual
        override
        returns (uint256 liquidatedAmount)
    {
        uint256 loss;
        uint256 underlyingBalance = _underlyingBalance();
        // If underlying balance currently held by strategy is not enough to cover
        // the requested amount, we divest from the Cellar Vault
        if (underlyingBalance < requestedAmount) {
            uint256 amountToWithdraw;
            unchecked {
                amountToWithdraw = requestedAmount - underlyingBalance;
            }
            uint256 shares = _sharesForAmount(amountToWithdraw);
            uint256 withdrawn = cellar.previewRedeem(shares);
            if (withdrawn < amountToWithdraw) loss = amountToWithdraw - withdrawn;
        }
        liquidatedAmount = requestedAmount - loss;
    }

    /// @notice This function is meant to be called from the vault
    /// @dev calculates estimated the @param requestedAmount the vault has to request to this strategy
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
            unchecked {
                liquidatedAmount = liquidatedAmount - underlyingBalance;
            }
            requestedAmount = _shareValue(cellar.previewWithdraw(liquidatedAmount));
        }
        return requestedAmount + underlyingBalance;
    }

    /// @notice Returns the max amount of assets that the strategy can withdraw after losses
    function maxLiquidate() public view virtual override returns (uint256) {
        return _estimatedTotalAssets();
    }

    /// @notice Returns the max amount of assets that the strategy can liquidate, before realizing losses
    function maxLiquidateExact() public view virtual override returns (uint256) {
        // only can request harvested assets
        return _underlyingBalance() + cellar.maxWithdraw(address(this));
    }

    ////////////////////////////////////////////////////////////////
    ///                 STRATEGY CONFIGURATION                   ///
    ////////////////////////////////////////////////////////////////
    /// @notice Sets the minimum single trade amount allowed
    /// @param _minSingleTrade The new minimum single trade value
    function setMinSingleTrade(uint256 _minSingleTrade) external checkRoles(ADMIN_ROLE) {
        assembly {
            // if _minSingleTrade == 0 revert()
            if iszero(_minSingleTrade) {
                // Throw the `InvalidZeroAmount` error
                mstore(0x00, 0xdd484e70)
                revert(0x1c, 0x04)
            }
            sstore(minSingleTrade.slot, _minSingleTrade)
            // Emit the `MinSingleTradeUpdated` event
            mstore(0x00, _minSingleTrade)
            log1(0x00, 0x20, _MIN_SINGLE_TRADE_UPDATED_EVENT_SIGNATURE)
        }
    }

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
        virtual
        override
        returns (uint256 unrealizedProfit, uint256 loss, uint256 debtPayment)
    {
        if (cellar.isPaused()) return (0, 0, 0);
        // Fetch initial strategy state
        uint256 underlyingBalance = _underlyingBalance();
        uint256 _estimatedTotalAssets_ = _estimatedTotalAssets();
        uint256 _lastEstimatedTotalAssets = lastEstimatedTotalAssets;

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
            // If not, divest from Cellar
            if (amountToWithdraw > underlyingBalance) {
                uint256 expectedAmountToWithdraw = amountToWithdraw - underlyingBalance;

                // We cannot withdraw more than actual balance or maxSingleTrade
                expectedAmountToWithdraw =
                    Math.min(Math.min(expectedAmountToWithdraw, _shareValue(_shareBalance())), maxSingleTrade);

                uint256 sharesToWithdraw = _sharesForAmount(expectedAmountToWithdraw);

                uint256 withdrawn = _divest(sharesToWithdraw);

                // Overwrite underlyingBalance with the proper amount after withdrawing
                underlyingBalance = _underlyingBalance();

                assembly ("memory-safe") {
                    if lt(underlyingBalance, minExpectedBalance) {
                        // throw the `MinExpectedBalanceNotReached` error
                        mstore(0x00, 0xbd277fff)
                        revert(0x1c, 0x04)
                    }

                    if lt(withdrawn, expectedAmountToWithdraw) { loss := sub(expectedAmountToWithdraw, withdrawn) }
                }
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
    function _adjustPosition(uint256, uint256 minOutputAfterInvestment) internal virtual override {
        uint256 toInvest = _underlyingBalance();
        _invest(toInvest, minOutputAfterInvestment);
    }

    /// @notice Invests `amount` of underlying, depositing it in the Cellar Vault
    /// @param amount The amount of underlying to be deposited in the vault
    /// @param minOutputAfterInvestment minimum expected output after `_invest()` (designated in Cellar receipt tokens)
    /// @return depositedAmount The amount of shares received, in terms of underlying
    function _invest(
        uint256 amount,
        uint256 minOutputAfterInvestment
    )
        internal
        virtual
        returns (uint256 depositedAmount)
    {
        // Don't do anything if amount to invest is 0
        if (amount == 0) return 0;
        // Dont't do anything if cellar is paused or shutdown
        if (cellar.isShutdown() || cellar.isPaused()) return 0;
        uint256 underlyingBalance = _underlyingBalance();
        if (amount > underlyingBalance) revert NotEnoughFundsToInvest();

        // Check max deposit just in case
        uint256 maxDeposit = cellar.maxDeposit(address(this));
        amount = Math.min(amount, maxDeposit);

        uint256 shares = cellar.deposit(amount, address(this));

        assembly ("memory-safe") {
            // if (shares < minOutputAfterInvestment)
            if lt(shares, minOutputAfterInvestment) {
                // throw the `MinOutputAmountNotReached` error
                mstore(0x00, 0xf7c67a48)
                revert(0x1c, 0x04)
            }
        }

        depositedAmount = _shareValue(shares);

        assembly {
            // Emit the `Invested` event
            mstore(0x00, amount)
            log2(0x00, 0x20, _INVESTED_EVENT_SIGNATURE, address())
        }
    }

    /// @notice Divests amount `shares` from Cellar Vault
    /// Note that divesting from Cellar could potentially cause loss (set to 0.01% as default in
    /// the Vault implementation), so the divested amount might actually be different from
    /// the requested `shares` to divest
    /// @dev care should be taken, as the `shares` parameter is *not* in terms of underlying,
    /// but in terms of cellar shares
    /// @return withdrawn the total amount divested, in terms of underlying asset
    function _divest(uint256 shares) internal virtual returns (uint256 withdrawn) {
        // if cellar is paused dont liquidate, skips revert
        if (cellar.isPaused()) return 0;
        withdrawn = cellar.redeem(shares, address(this), address(this));
        emit Divested(address(this), shares, withdrawn);
    }

    /// @notice Liquidate up to `amountNeeded` of MaxApy Vault's `underlyingAsset` of this strategy's positions,
    /// irregardless of slippage. Any excess will be re-invested with `_adjustPosition()`.
    /// @dev This function should return the amount of MaxApy Vault's `underlyingAsset` tokens made available by the
    /// liquidation. If there is a difference between `amountNeeded` and `liquidatedAmount`, `loss` indicates whether
    /// the
    /// difference is due to a realized loss, or if there is some other sitution at play
    /// (e.g. locked funds) where the amount made available is less than what is needed.
    /// NOTE: The invariant `liquidatedAmount + loss <= amountNeeded` should always be maintained
    /// @param amountNeeded amount of MaxApy Vault's `underlyingAsset` needed to be liquidated
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
        // if cellar is paused dont liquidate, skips revert
        if (cellar.isPaused()) {
            uint256 amountOut = Math.min(underlyingBalance, amountNeeded);
            return (amountOut, amountNeeded - amountOut);
        }
        // If underlying balance currently held by strategy is not enough to cover
        // the requested amount, we divest from the Cellar Vault
        if (underlyingBalance < amountNeeded) {
            uint256 amountToWithdraw;
            unchecked {
                amountToWithdraw = amountNeeded - underlyingBalance;
            }
            uint256 shares = _sharesForAmount(amountToWithdraw);
            if (shares == 0) return (0, 0);
            uint256 withdrawn = _divest(shares);
            assembly {
                // if withdrawn < amountToWithdraw
                if lt(withdrawn, amountToWithdraw) { loss := sub(amountToWithdraw, withdrawn) }
            }
        }
        // liquidatedAmount = amountNeeded - loss;
        assembly {
            liquidatedAmount := sub(amountNeeded, loss)
        }
    }

    /// @notice Liquidates everything and returns the amount that got freed.
    /// @dev This function is used during emergency exit instead of `_prepareReturn()` to
    /// liquidate all of the Strategy's positions back to the MaxApy Vault.
    function _liquidateAllPositions() internal virtual override returns (uint256 amountFreed) {
        if (cellar.isPaused()) revert CellarIsPaused();
        _divest(_shareBalance());
        amountFreed = _underlyingBalance();
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL VIEW FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////

    /// @notice Determines the current value of `shares`.
    /// @return _assets the estimated amount of underlying computed from shares `shares`
    function _shareValue(uint256 shares) internal view virtual returns (uint256 _assets) {
        assembly {
            // return cellar.previewRedeem(shares);
            mstore(0x00, 0x4cdad506)
            mstore(0x20, shares)
            if iszero(staticcall(gas(), sload(cellar.slot), 0x1c, 0x24, 0x00, 0x20)) { revert(0x00, 0x04) }
            _assets := mload(0x00)
        }
    }

    /// @notice Determines how many shares depositor of `amount` of underlying would receive.
    /// @return _shares the estimated amount of shares computed in exchange for underlying `amount`
    function _sharesForAmount(uint256 amount) internal view virtual returns (uint256 _shares) {
        assembly {
            // return cellar.convertToShares(amount);
            mstore(0x00, 0xc6e6f592)
            mstore(0x20, amount)
            if iszero(staticcall(gas(), sload(cellar.slot), 0x1c, 0x24, 0x00, 0x20)) { revert(0x00, 0x04) }
            _shares := mload(0x00)
        }
    }

    /// @notice Returns the current strategy's amount of Cellar vault shares
    /// @return _balance balance the strategy's balance of Cellar vault shares
    function _shareBalance() internal view virtual returns (uint256 _balance) {
        assembly {
            // return cellar.balanceOf(address(this));
            mstore(0x00, 0x70a08231)
            mstore(0x20, address())
            if iszero(staticcall(gas(), sload(cellar.slot), 0x1c, 0x24, 0x00, 0x20)) { revert(0x00, 0x04) }
            _balance := mload(0x00)
        }
    }

    /// @notice Returns the real time estimation of the value in assets held by the strategy
    /// @return the strategy's total assets(idle + investment positions)
    function _estimatedTotalAssets() internal view virtual override returns (uint256) {
        return _underlyingBalance() + _shareValue(_shareBalance());
    }

    ////////////////////////////////////////////////////////////////
    ///                      SIMULATION                          ///
    ////////////////////////////////////////////////////////////////

    /// @dev internal helper function that reverts and returns needed values in the revert message
    function _simulateHarvest() public override {
        address harvester = address(0);

        uint256 expectedBalance;
        uint256 outputAfterInvestment;
        uint256 intendedDivest;
        uint256 actualDivest;
        uint256 intendedInvest;
        uint256 actualInvest;

        // normally the treasury would get the management fee
        address managementFeeReceiver = address(0);

        uint256 unrealizedProfit;
        uint256 loss;
        uint256 debtPayment;
        uint256 debtOutstanding;

        address cachedVault = address(vault); // Cache `vault` address to avoid multiple SLOAD's

        assembly ("memory-safe") {
            // Store `vault`'s `debtOutstanding()` function selector:
            // `bytes4(keccak256("debtOutstanding(address)"))`
            mstore(0x00, 0xbdcf36bb)
            mstore(0x20, address()) // append the current address as parameter

            // query `vault`'s `debtOutstanding()`
            if iszero(
                staticcall(
                    gas(), // Remaining amount of gas
                    cachedVault, // Address of `vault`
                    0x1c, // byte offset in memory where calldata starts
                    0x24, // size of the calldata to copy
                    0x00, // byte offset in memory to store the return data
                    0x20 // size of the return data
                )
            ) {
                // Revert if debt outstanding query fails
                revert(0x00, 0x04)
            }

            // Store debt outstanding returned by staticcall into `debtOutstanding`
            debtOutstanding := mload(0x00)
        }

        intendedDivest = debtOutstanding;

        if (emergencyExit == 2) {
            // Do what needed before
            _beforePrepareReturn();

            uint256 balanceBefore = _estimatedTotalAssets();
            // Free up as much capital as possible
            uint256 amountFreed = _liquidateAllPositions();

            // silence compiler warnings
            amountFreed;

            uint256 balanceAfter = _estimatedTotalAssets();

            assembly {
                // send everything back to the vault
                debtPayment := balanceAfter
                if lt(balanceAfter, balanceBefore) { loss := sub(balanceBefore, balanceAfter) }
            }
        } else {
            // Do what needed before
            _beforePrepareReturn();
            // Free up returns for vault to pull
            (unrealizedProfit, loss, debtPayment) = _prepareReturn(debtOutstanding, 0);

            expectedBalance = _underlyingBalance();
        }

        actualDivest = debtPayment;

        assembly ("memory-safe") {
            let m := mload(0x40) // Store free memory pointer
            // Store `vault`'s `report()` function selector:
            // `bytes4(keccak256("report(uint128,uint128,uint128,address)"))`
            mstore(0x00, 0x80919dd5)
            mstore(0x20, unrealizedProfit) // append the `profit` argument
            mstore(0x40, loss) // append the `loss` argument
            mstore(0x60, debtPayment) // append the `debtPayment` argument
            mstore(0x80, managementFeeReceiver) // append the `debtPayment` argument

            // Report to vault
            if iszero(
                call(
                    gas(), // Remaining amount of gas
                    cachedVault, // Address of `vault`
                    0, // `msg.value`
                    0x1c, // byte offset in memory where calldata starts
                    0x84, // size of the calldata to copy
                    0x00, // byte offset in memory to store the return data
                    0x20 // size of the return data
                )
            ) {
                // If call failed, throw the error thrown in the previous `call`
                revert(0x00, 0x04)
            }

            // Store debt outstanding returned by call to `report()` into `debtOutstanding`
            debtOutstanding := mload(0x00)

            mstore(0x60, 0) // Restore the zero slot
            mstore(0x40, m) // Restore the free memory pointer
        }
        intendedInvest = _underlyingBalance();
        uint256 sharesBalanceBefore = _shareBalance();
        // Check if vault transferred underlying and re-invest it
        _adjustPosition(debtOutstanding, 0);
        outputAfterInvestment = _shareBalance() - sharesBalanceBefore;
        actualInvest = _shareValue(outputAfterInvestment);
        _snapshotEstimatedTotalAssets();

        // revert with data we need
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, expectedBalance)
            mstore(add(ptr, 32), outputAfterInvestment)
            mstore(add(ptr, 64), intendedDivest)
            mstore(add(ptr, 96), actualDivest)
            mstore(add(ptr, 128), intendedInvest)
            mstore(add(ptr, 160), actualInvest)
            revert(ptr, 192)
        }
    }
}
