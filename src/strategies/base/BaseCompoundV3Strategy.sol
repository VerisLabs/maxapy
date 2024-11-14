// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import "openzeppelin/interfaces/IERC20.sol";
import { ICommet } from "src/interfaces/CompoundV2/ICommet.sol";
import { RewardOwed, ICommetRewards } from "src/interfaces/CompoundV2/ICommetRewards.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { BaseStrategy, IERC20Metadata, IMaxApyVault, SafeTransferLib } from "src/strategies/base/BaseStrategy.sol";

import { IUniswapV3Pool, IUniswapV3Router as IRouter } from "src/interfaces/IUniswap.sol";
import { OracleLibrary } from "src/lib/OracleLibrary.sol";

/// @title BaseCompoundV2Strategy
/// @author MaxApy
/// @notice `BaseCompoundV2Strategy` sets the base functionality to be implemented by MaxApy CompoundV2 strategies.
/// @dev Some functions can be overriden if needed
contract BaseCompoundV3Strategy is BaseStrategy {
    using SafeTransferLib for address;

    ////////////////////////////////////////////////////////////////
    ///                        CONSTANTS                         ///
    ////////////////////////////////////////////////////////////////
    uint256 internal constant DEGRADATION_COEFFICIENT = 10 ** 18;
    /// @notice the reward accrued for an account on a Comet deployment
    uint256 public totalAccruedReward;

    ////////////////////////////////////////////////////////////////
    ///                         ERRORS                           ///
    ////////////////////////////////////////////////////////////////
    error NotEnoughFundsToInvest();
    error InvalidZeroAddress();
    error InitialInvestmentTooLow();


    ////////////////////////////////////////////////////////////////
    ///                         EVENTS                           ///
    ////////////////////////////////////////////////////////////////

    /// @notice Emitted when underlying asset is deposited into the Compound Vault
    event Invested(address indexed strategy, uint256 amountInvested);

    /// @notice Emitted when the `requestedShares` are divested from the Compound Vault
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

    /// @dev `keccak256(bytes("MinSingleTradeUpdated(uint256)"))`.
    uint256 internal constant _MIN_SINGLE_TRADE_UPDATED_EVENT_SIGNATURE =
        0x70bc59027d7d0bba6fbf38b995e26c84f6c1805fc3ead71ec1d7ebeb7d76399b;

    /// @dev `keccak256(bytes("MaxSingleTradeUpdated(uint256)"))`.
    uint256 internal constant _MAX_SINGLE_TRADE_UPDATED_EVENT_SIGNATURE =
        0xe8b08f84dc067e4182670384e9556796d3a831058322b7e55f9ddb3ec48d7c10;

    /// @dev `keccak256(bytes("RouterUpdated(address)"))`.
    uint256 internal constant _ROUTER_UPDATED_EVENT_SIGNATURE =
        0x7aed1d3e8155a07ccf395e44ea3109a0e2d6c9b29bbbe9f142d9790596f4dc80;

    ////////////////////////////////////////////////////////////////
    ///            STRATEGY GLOBAL STATE VARIABLES               ///
    ////////////////////////////////////////////////////////////////

    /// @notice The Compound Vault the strategy interacts with
    ICommet public commet;
    ICommetRewards public commetRewards;
    address public tokenSupplyAddress;
    /// @notice Minimun trade size within the strategy
    uint256 public minSingleTrade;
    /// @notice Maximum trade size within the strategy
    uint256 public maxSingleTrade;

    ////////////////////////////////////////////////////////////////
    ///                     INITIALIZATION                       ///
    ////////////////////////////////////////////////////////////////
    constructor() initializer { }

    /// @notice Initialize the Strategy
    /// @param _vault The address of the MaxApy Vault associated to the strategy
    /// @param _keepers The addresses of the keepers to be added as valid keepers to the strategy
    /// @param _strategyName the name of the strategy
    /// @param _commet The Compound Finance vault this strategy will interact with
    function initialize(
        IMaxApyVault _vault,
        address[] calldata _keepers,
        bytes32 _strategyName,
        address _strategist,
        ICommet _commet,
        ICommetRewards _commetRewards,
        address _tokenSupplyAddress
    )
        public
        virtual
        initializer
    {
        __BaseStrategy_init(_vault, _keepers, _strategyName, _strategist);
        commet = _commet;
        commetRewards = _commetRewards;
        tokenSupplyAddress = _tokenSupplyAddress;

        /// Mininmum single trade is 0.01 token units
        minSingleTrade = 10 ** IERC20Metadata(underlyingAsset).decimals() / 100;

        /// Unlimited max single trade by default
        maxSingleTrade = type(uint256).max;
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
        returns (uint256 liquidatedAmount)
    {
        uint256 loss;
        uint256 underlyingBalance = _underlyingBalance();
        // If underlying balance currently held by strategy is not enough to cover
        // the requested amount, we divest from the Compound Vault
        if (underlyingBalance < requestedAmount) {
            uint256 amountToWithdraw;
            unchecked {
                amountToWithdraw = requestedAmount - underlyingBalance;
            }
            uint256 investedUnderlyingAsset = _totalInvestedValue();
            // If underlying assest invest currently by strategy is not enough to cover
            // the requested amount, we divest from the Compound rewards
            if (amountToWithdraw > investedUnderlyingAsset) {
                unchecked {
                    amountToWithdraw = amountToWithdraw - investedUnderlyingAsset;
                }
                uint256 rewardsUsdc = _accruedRewardValue();
                assembly {
                    // if withdrawn < amountToWithdraw
                    if gt(amountToWithdraw, rewardsUsdc) { loss := sub(amountToWithdraw, rewardsUsdc) }
                }
            }
        }
        liquidatedAmount = requestedAmount - loss;
    }

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
        // we cannot predict losses so return as if there were not
        // increase 1% to be pessimistic
        return previewLiquidate(liquidatedAmount) * 101 / 100;
    }

    /// @notice Returns the max amount of assets that the strategy can withdraw after losses
    function maxLiquidate() public view override returns (uint256) {
        return _estimatedTotalAssets();
    }

    /// @notice Returns the max amount of assets that the strategy can liquidate, before realizing losses
    function maxLiquidateExact() public view override returns (uint256) {
        // make sure it doesnt revert when increaseing it 1% in the withdraw
        return previewLiquidate(estimatedTotalAssets()) * 99 / 100;
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
            uint256 withdrawn;

            // Check if underlying funds held in the strategy are enough to cover withdrawal.
            // If not, divest from Compound Vault
            if (amountToWithdraw > underlyingBalance) {
                uint256 expectedAmountToWithdraw = amountToWithdraw - underlyingBalance;

                uint256 totalInvestedValue = _totalInvestedValue();
                // If underlying assest invested currently by strategy is not enough to cover
                // the requested amount, we divest from the Compound rewards
                if (expectedAmountToWithdraw > totalInvestedValue) {
                    uint256 expectedAmountLeftToWithdraw;
                    unchecked {
                        expectedAmountLeftToWithdraw = expectedAmountToWithdraw - totalInvestedValue;
                    }
                    uint256 rewardsUsdc = _accruedRewardValue();
                    if (expectedAmountLeftToWithdraw > rewardsUsdc) {
                        withdrawn = _divest(_totalInvestedBaseAsset(), totalAccruedReward, false);
                    } else {
                        unchecked {
                            expectedAmountLeftToWithdraw = rewardsUsdc - expectedAmountLeftToWithdraw;
                        }
                        withdrawn = _divest(_totalInvestedBaseAsset(), _convertUsdcTobaseAsset(expectedAmountLeftToWithdraw), true);
                    } 
                } else {
                    withdrawn = _divest(_convertUsdcTobaseAsset(expectedAmountToWithdraw), 0, true);
                }

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
        if (toInvest > minSingleTrade) {
            _invest(toInvest, minOutputAfterInvestment);
        }
    }

    /// @notice Invests `amount` of underlying, depositing it in the Compound Vault
    /// @param amount The amount of underlying to be deposited in the vault
    /// @param minOutputAfterInvestment minimum expected output after `_invest()` (designated in Compound receipt
    /// tokens)
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

        uint256 underlyingBalance = _underlyingBalance();
        if (amount > underlyingBalance) revert NotEnoughFundsToInvest();
        
        commet.supply(tokenSupplyAddress, amount);

    }

    /// @notice Divests amount `amount` from Compound Vault
    /// Note that divesting from Compound could potentially cause loss (set to 0.01% as default in
    /// the Vault implementation), so the divested amount might actually be different from
    /// the requested `amount` to divest
    /// @dev care should be taken, as the `amount` parameter is *not* in terms of underlying,
    /// but in terms of yvault amount
    /// @return withdrawn the total amount divested, in terms of base asset of compoundV3
    function _divest(uint256 amount, bool reinvestRewards) internal virtual returns (uint256 withdrawn) {

        RewardOwed memory reward = commetRewards.getRewardOwed(address(commet), address(this));
        uint256 _rewardBefore = IERC20(reward.token).balanceOf(address(this));
        commetRewards.claim(address(commet), address(this), true);
        uint256 _rewardAfter = IERC20(reward.token).balanceOf(address(this));

        uint256 rewardsWithdrawn = _rewardAfter - _rewardBefore;

        // TODO - swap the COMP reward into USDT 

        uint256 _before = IERC20(tokenSupplyAddress).balanceOf(address(this));
        commet.withdraw(tokenSupplyAddress, amount);
        uint256 _after = IERC20(tokenSupplyAddress).balanceOf(address(this));
        withdrawn = _after - _before;
    }

    /// @notice Liquidate up to `amountNeeded` of MaxApy Vault's `underlyingAsset` of this strategy's positions,
    /// regardless of slippage. Any excess will be re-invested with `_adjustPosition()`.
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
        override
        returns (uint256 liquidatedAmount, uint256 loss)
    {
        uint256 underlyingBalance = _underlyingBalance();
        // If underlying balance currently held by strategy is not enough to cover
        // the requested amount, we divest from the Compound Vault
        if (amountNeeded > underlyingBalance) {
                uint256 withdrawn;
                uint256 expectedAmountToWithdraw = amountNeeded - underlyingBalance;

                uint256 totalInvestedValue = _totalInvestedValue();
                // If underlying assest invested currently by strategy is not enough to cover
                // the requested amount, we divest from the Compound rewards
                if (expectedAmountToWithdraw > totalInvestedValue) {
                    uint256 expectedAmountLeftToWithdraw;
                    unchecked {
                        expectedAmountLeftToWithdraw = expectedAmountToWithdraw - totalInvestedValue;
                    }
                    uint256 rewardsUsdc = _accruedRewardValue();
                    if (expectedAmountLeftToWithdraw > rewardsUsdc) {
                        withdrawn = _divest(_totalInvestedBaseAsset(), totalAccruedReward, false);
                    } else {
                        unchecked {
                            expectedAmountLeftToWithdraw = rewardsUsdc - expectedAmountLeftToWithdraw;
                        }
                        withdrawn = _divest(_totalInvestedBaseAsset(), _convertUsdcTobaseAsset(expectedAmountLeftToWithdraw), true);
                    } 
                } else {
                    withdrawn = _divest(_convertUsdcTobaseAsset(expectedAmountToWithdraw), 0, true);
                }

                assembly ("memory-safe") {
                    if lt(underlyingBalance, minExpectedBalance) {
                        // throw the `MinExpectedBalanceNotReached` error
                        mstore(0x00, 0xbd277fff)
                        revert(0x1c, 0x04)
                    }

                    if lt(withdrawn, expectedAmountToWithdraw) { loss := sub(expectedAmountToWithdraw, withdrawn) }
                }

                // liquidatedAmount = amountNeeded - loss;
                assembly {
                    liquidatedAmount := sub(amountNeeded, loss)
                }
            }
    }

    /// @notice Liquidates everything and returns the amount that got freed.
    /// @dev This function is used during emergency exit instead of `_prepareReturn()` to
    /// liquidate all of the Strategy's positions back to the MaxApy Vault.
    function _liquidateAllPositions() internal override returns (uint256 amountFreed) {
        _divest(_totalInvestedValue(), true);
        amountFreed = _underlyingBalance();
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL VIEW FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////

    function _accruedRewardValue() public virtual view returns (uint256) {
    }

    function _totalInvestedBaseAsset() public override view returns (uint256 investedAmount) {
    }

    function _totalInvestedValue() public virtual view returns (uint256) {
    }

    /// @notice Returns the real time estimation of the value in assets held by the strategy
    /// @return the strategy's total assets(idle + investment positions)
    function _estimatedTotalAssets() internal view override returns (uint256) {
        return _underlyingBalance() + _accruedRewardValue() + _totalInvestedValue();
    }

    /// @notice returns the estimated result of a Uniswap V3 swap
    /// @dev use TWAP oracle for more safety
    function _estimateAmountOut(
        address tokenIn,
        address tokenOut,
        uint128 amountIn,
        address pool,
        uint32 secondsAgo
    )
        internal
        view
        returns (uint256 amountOut)
    {
        // Code copied from OracleLibrary.sol, consult()
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secondsAgo;
        secondsAgos[1] = 0;

        // int56 since tick * time = int24 * uint32
        // 56 = 24 + 32
        (int56[] memory tickCumulatives,) = IUniswapV3Pool(pool).observe(secondsAgos);

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        // int56 / uint32 = int24
        int24 tick = int24(int256(tickCumulativesDelta) / int256(int32(secondsAgo)));
        // Always round to negative infinity

        if (tickCumulativesDelta < 0 && (int256(tickCumulativesDelta) % int256(int32(secondsAgo)) != 0)) {
            tick--;
        }

        amountOut = OracleLibrary.getQuoteAtTick(tick, amountIn, tokenIn, tokenOut);
    }

    // @notice Converts USDC to base asset
    /// @param usdcAmount Amount of USDC
    /// @return Equivalent amount in base asset
    function _convertUsdcTobaseAsset(uint256 usdcAmount) internal view returns (uint256) {
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
        // uint256 sharesBalanceBefore = _shareBalance();
        uint256 sharesBalanceBefore = _totalInvestedValue() + accruedRewardsValue();
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
