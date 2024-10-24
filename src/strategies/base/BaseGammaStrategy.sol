// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { IBeefyVault } from "src/interfaces/IBeefyVault.sol";

import { IUniProxy } from "src/interfaces/IUniProxy.sol";
import { OracleLibrary } from "src/lib/OracleLibrary.sol";
import { IHypervisor } from "src/interfaces/IHypervisor.sol";
import { IAlgebraPool } from "src/interfaces/IAlgebraPool.sol";

import { IUniswapV3Pool } from "src/interfaces/IUniswap.sol";
import { ISwapRouter as IRouter } from "src/interfaces/ISwapRouter.sol";
import { LiquidityRangePool } from "src/lib/LiquidityRangePool.sol";

import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { BaseStrategy, IERC20Metadata, IMaxApyVault, SafeTransferLib } from "src/strategies/base/BaseStrategy.sol";
import { OracleLibrary } from "src/lib/OracleLibrary.sol";

import { console2 } from "forge-std/console2.sol";

/// @title BaseGammaStrategy
/// @author MaxApy
/// @notice `BaseGammaStrategy` sets the base functionality to be implemented by MaxApy Beefy strategies.
/// @dev Some functions can be overriden if needed
contract BaseGammaStrategy is BaseStrategy {
    using SafeTransferLib for address;

    ////////////////////////////////////////////////////////////////
    ///                         ERRORS                           ///
    ////////////////////////////////////////////////////////////////
    error NotEnoughFundsToInvest();
    error InvalidZeroAddress();

    ////////////////////////////////////////////////////////////////
    ///                         EVENTS                           ///
    ////////////////////////////////////////////////////////////////

    /// @notice Emitted when underlying asset is deposited into the Beefy Vault
    event Invested(address indexed strategy, uint256 amountInvested);

    /// @notice Emitted when the `requestedShares` are divested from the Beefy Vault
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
    
    address public token0;
    IHypervisor public hypervisor;
    IUniProxy public uniProxy;
    IAlgebraPool public algebraPool;
    IRouter public router;

    uint256 constant _1_WETH = 1 ether; // underlyingAsset

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
    /// @param _uniProxy The address of the gamma's main proxy contract used for depositing tokens
    /// @param _hypervisor The address of gamma's hypervisor contract  used for withdrawing
    /// @param _router The address of the quickswap's router inspired by uniswap
    /// @param _algebraPool The address of the gamma's algebra pool contract used to get global state and positions
    function initialize(
        IMaxApyVault _vault,
        address[] calldata _keepers,
        bytes32 _strategyName,
        address _strategist,
        IUniProxy _uniProxy,
        IHypervisor _hypervisor,
        IRouter _router,
        IAlgebraPool _algebraPool
        
    )
        public
        virtual
        initializer
    {
        __BaseStrategy_init(_vault, _keepers, _strategyName, _strategist);

        // Gamma init
        uniProxy = _uniProxy;
        hypervisor = _hypervisor;
        algebraPool = _algebraPool;
        token0 = algebraPool.token0();

        router = _router;

        /// Approve Vault to transfer USDCe
        underlyingAsset.safeApprove(address(_vault), type(uint256).max);

        underlyingAsset.safeApprove(address(router), type(uint256).max);
        token0.safeApprove(address(router), type(uint256).max);

        underlyingAsset.safeApprove(address(uniProxy), type(uint256).max);

        underlyingAsset.safeApprove(address(hypervisor), type(uint256).max);
        token0.safeApprove(address(hypervisor), type(uint256).max);

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

    /////////////////////////////////////////////////////////////////
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
        // the requested amount, we divest from the beefy Vault
        if (underlyingBalance < requestedAmount) {
            uint256 amountToWithdraw;
            unchecked {
                amountToWithdraw = requestedAmount - underlyingBalance;
            }
            uint256 shares = _sharesForAmount(amountToWithdraw);
            uint256 withdrawn = _shareValue(shares);
            if (withdrawn < amountToWithdraw) loss = amountToWithdraw - withdrawn;
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
        if (toInvest > minSingleTrade) {
            _invest(toInvest, minOutputAfterInvestment);
        }
    }

    // Function to calculate how much USDCe to swap
    function calculateWETHToSwap(uint256 totalweth, uint256 ratio) public view returns (uint256 wethToSwap) {

        uint256 rate = _estimateAmountOut(address(underlyingAsset), address(token0), _uint128Safe(1 * _1_WETH), 30);
        console2.log("###   ~ file: BaseGammaStrategy.sol:385 ~ calculateWETHToSwap ~ rateV3:", rate);

        assembly {
            wethToSwap := div(mul(ratio, totalweth), add(rate, ratio))
        }
        
        console2.log("###   ~ file: BaseGammaStrategy.sol:385 ~ calculateWETHToSwap ~ wethToSwap:", wethToSwap);


        return wethToSwap;
    }
        

    /// @notice Invests `amount` of underlying into the Beefy vault
    /// @dev
    /// @param amount The amount of underlying to be deposited in the pool
    /// @param minOutputAfterInvestment minimum expected output after `_invest()`
    /// @return The amount of tokens received, in terms of underlying
    function _invest(uint256 amount, uint256 minOutputAfterInvestment) internal virtual returns (uint256) {
        // Don't do anything if amount to invest is 0
        if (amount == 0) return 0;

        uint256 underlyingBalance = _underlyingBalance();
        console2.log("###   ~ file: BaseGammaStrategy.sol:390 ~ _invest ~ underlyingBalance:", underlyingBalance);


        assembly ("memory-safe") {
            if gt(amount, underlyingBalance) {
                // throw the `NotEnoughFundsToInvest` error
                mstore(0x00, 0xb2ff68ae)
                revert(0x1c, 0x04)
            }
        }

        // step1 get the Gamma pool ratio
        // 1 usdce -> x dai
        (uint256 amountStart, uint256 amountEnd) = uniProxy.getDepositAmount(address(hypervisor), address(underlyingAsset), 1 * _1_WETH);

        uint256 percentA = amountStart * 10000 / (amountStart + 1 * _1_WETH);
        console2.log("###   ~ file: BaseGammaStrategy.sol:409 ~ _invest ~ percentA:", percentA);

        
        
        console2.log("###   ~ file: BaseGammaStrategy.sol:404 ~ _invest ~ amountEnd:", amountEnd);

        console2.log("###   ~ file: BaseGammaStrategy.sol:404 ~ _invest ~ amountStart:", amountStart);

            
        uint256 amountToConsider = amount - amount * 1 / 100;
        // Calculate how much USDCe should be swapped into DAI
        uint256 wethToSwap = calculateWETHToSwap(amountToConsider, (amountStart + amountEnd) / 2);
        console2.log("###   ~ file: BaseGammaStrategy.sol:423 ~ _invest ~ wethToSwap:", wethToSwap);

        console2.log("###   ~ file: BaseGammaStrategy.sol:434 ~ _invest ~ xyz:", underlyingAsset.balanceOf(address(this)), token0.balanceOf(address(this)));

        // swap the LUSD to USDC
        router.exactInputSingle(
            IRouter.ExactInputSingleParams({
                tokenIn: address(underlyingAsset),
                tokenOut: address(token0),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: wethToSwap + amount * 1 / 100,
                amountOutMinimum: 0,
                limitSqrtPrice: 0
            })
        );

        console2.log("###   ~ file: BaseGammaStrategy.sol:434 ~ _invest ~ xyz:", underlyingAsset.balanceOf(address(this)), token0.balanceOf(address(this)));

        // (uint256 amountStart1,  uint256 amountEnd2) = uniProxy.getDepositAmount(address(hypervisor), address(underlyingAsset), uint256(underlyingAsset.balanceOf(address(this))));
        // console2.log("###   ~ file: BaseGammaStrategy.sol:436 ~ _invest ~ amountStart:", amountStart1);

        // console2.log("###   ~ file: BaseGammaStrategy.sol:436 ~ _invest ~ amountEnd:", amountEnd2);

        uint256 token0ToDeposit = ((amountStart + amountEnd) / 2 * underlyingAsset.balanceOf(address(this))) / 1 ether ;
        console2.log("###   ~ file: BaseGammaStrategy.sol:441 ~ _invest ~ token0ToDeposit:", token0ToDeposit);


        //step3 deposit usdce and dai into gamma vault
        uint256[4] memory minOut = [uint256(0), uint256(0), uint256(0), uint256(0)];
        uint256 shares;

        console2.log("###   ~ file: BaseGammaStrategy.sol:461 ~ _invest ~ shares:", shares);

        if (token0.balanceOf(address(this)) > 0 && underlyingAsset.balanceOf(address(this)) > 0) {
            shares = uniProxy.deposit(
                token0ToDeposit,
                underlyingAsset.balanceOf(address(this)),
                address(this),
                address(hypervisor),
                minOut
            );
        }

        console2.log("###   ~ file: BaseGammaStrategy.sol:461 ~ _invest ~ shares:", shares);

        assembly ("memory-safe") {
            if lt(shares, minOutputAfterInvestment) {
                // throw the `MinOutputAmountNotReached` error
                mstore(0x00, 0xf7c67a48)
                revert(0x1c, 0x04)
            }
        }

        emit Invested(address(this), amount);

        return shares;
    }


    /// @notice Divests amount `shares` from Beefy Vault
    /// Note that divesting from Beefy could potentially cause loss (set to 0.01% as default in
    /// the Vault implementation), so the divested amount might actually be different from
    /// the requested `shares` to divest
    /// @dev care should be taken, as the `shares` parameter is *not* in terms of underlying,
    /// but in terms of "yvault" shares ...........########## TODO
    /// @return withdrawn the total amount divested, in terms of underlying asset
    function _divest(uint256 shares) internal virtual returns (uint256 withdrawn) {

        // Remove liquidity and obtain usdce
        uint256[4] memory minOut = [uint256(0), uint256(0), uint256(0), uint256(0)];

        (uint256 amount0, uint256 amount1) = hypervisor.withdraw(shares, address(this), address(this), minOut);

        // step2 swap a part of usdce into dai
        uint256 WETHAmountBefore = underlyingAsset.balanceOf(address(this));
        // swap the LUSD to USDC

        router.exactInputSingle(
            IRouter.ExactInputSingleParams({
                tokenIn: address(token0),
                tokenOut: address(underlyingAsset),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amount0,
                amountOutMinimum: 0,
                limitSqrtPrice: 0
            })
        );

        uint256 WETHAmountAfter = underlyingAsset.balanceOf(address(this));

        withdrawn = WETHAmountAfter - WETHAmountBefore + amount1;

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
        // the requested amount, we divest from the Beefy Vault
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
    function _liquidateAllPositions() internal override returns (uint256 amountFreed) {
        _divest(_shareBalance());
        amountFreed = _underlyingBalance();
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL VIEW FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////

    /// @notice Determines the current value of `shares`.
    /// @return _assets the estimated amount of underlying computed from shares `shares`
    function _shareValue(uint256 shares) internal view virtual returns (uint256 _assets) {

        int24 baseLower = hypervisor.baseLower();
        int24 baseUpper = hypervisor.baseUpper();
        int24 limitLower = hypervisor.limitLower();
        int24 limitUpper = hypervisor.limitUpper();

        // uint128 L1 = computeLiquidityFromShares(baseLower, baseUpper, shares);

        // uint128 L2 = computeLiquidityFromShares(limitLower, limitUpper, shares);

        (uint256 base0, uint256 base1) = _CalcBurnLiquidity(baseLower, baseUpper, computeLiquidityFromShares(baseLower, baseUpper, shares));
        (uint256 limit0, uint256 limit1) = _CalcBurnLiquidity(limitLower, limitUpper, computeLiquidityFromShares(limitLower, limitUpper, shares));

        // Push tokens proportional to unused balances
        uint256 unusedAmount0 =
            underlyingAsset.balanceOf(address(hypervisor)) * shares / hypervisor.totalSupply();

        uint256 unusedAmount1 =
            token0.balanceOf(address(hypervisor)) * shares / hypervisor.totalSupply();

        uint256 amount0 = base0 + limit0 + unusedAmount0;

        uint256 amount1 = base1 + limit1 + unusedAmount1;

        _assets = _estimateAmountOut(address(underlyingAsset), address(token0), _uint128Safe(amount0), 30) + amount1;

    }

    function _CalcBurnLiquidity(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    )
        public
        view
        returns (uint256 amount0, uint256 amount1)
    {
        // Pool.burn
        (uint160 sqrtRatioX96, int24 globalTick,,,,,) = algebraPool.globalState();
        (int256 amount0Int, int256 amount1Int,) = LiquidityRangePool.computeTokenAmountsForLiquidity(
            tickLower, tickUpper, int128(liquidity), globalTick, sqrtRatioX96
        );

        amount0 = uint256(amount0Int);

        amount1 = uint256(amount1Int);

        amount0 = _uint128Safe(amount0);

        amount1 = _uint128Safe(amount1);

        //Pool.collect
        (, uint128 positionFees0, uint128 positionFees1) = getPositionInfo(tickLower, tickUpper);

        if (positionFees0 > 0 && amount0 > positionFees0) {
            amount0 = positionFees0;
        }

        if (positionFees1 > 0 && amount1 > positionFees1) {
            amount1 = positionFees1;
        }
    }

    /// @notice Determines how many shares depositor of `amount` of underlying would receive.
    /// @return shares the estimated amount of shares computed in exchange for underlying `amount`
    function _sharesForAmount(uint256 amount) internal view virtual returns (uint256 shares) {
        (uint256 amountStart, uint256 amountEnd) =
            uniProxy.getDepositAmount(address(hypervisor), address(underlyingAsset), 1 * _1_WETH);

        // Calculate how much USDCe should be swapped into DAI
        uint256 wethToSwap = calculateWETHToSwap(amount, (amountStart + amountEnd) / 2);

        uint256 token0Amount = _estimateAmountOut(address(underlyingAsset), address(token0), _uint128Safe(wethToSwap), 30);

        // uint256 wethTokenAmount = amount - wethToSwap;

        uint256 price;
        uint256 PRECISION = 1e36;

        uint160 sqrtPrice = OracleLibrary.getSqrtRatioAtTick(hypervisor.currentTick());

        assembly {
            price := div(mul(mul(sqrtPrice, sqrtPrice), PRECISION), exp(2, 192))
        }

        (uint256 pool0, uint256 pool1) = hypervisor.getTotalAmounts();

        assembly {
            // shares := add(token0Amount, div(mul(wethTokenAmount, price), PRECISION))
            shares := add(token0Amount, div(mul(sub(amount,wethToSwap), price), PRECISION))
        }

        uint256 total = hypervisor.totalSupply();

        if (total != 0) {
            assembly {
                let pool0PricedInweth := div(mul(pool0, price), PRECISION)
                shares := div(mul(shares, total), add(pool0PricedInweth, pool1))
            }
        }

    }


    /// @notice returns the estimated result of a Uniswap V3 swap
    /// @dev use TWAP oracle for more safety
    function _estimateAmountOut(
        address tokenIn,
        address tokenOut,
        uint128 amountIn,
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
        (int56[] memory tickCumulatives,,,) = algebraPool.getTimepoints(secondsAgos);
        // (int56[] memory tickCumulatives,) = IUniswapV3Pool(pool).observe(secondsAgos);

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        // int56 / uint32 = int24
        int24 tick = int24(int256(tickCumulativesDelta) / int256(int32(secondsAgo)));
        // Always round to negative infinity

        if (tickCumulativesDelta < 0 && (int256(tickCumulativesDelta) % int256(int32(secondsAgo)) != 0)) {
            tick--;
        }

        amountOut = OracleLibrary.getQuoteAtTick(tick, amountIn, tokenIn, tokenOut);
        console2.log("###   ~ file: BaseGammaStrategy.sol:708 ~ amountOut:", amountOut);

    }

    // Gamma hypervisor internal functions

    /// @notice Get the liquidity amount for given liquidity tokens
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param shares Shares of position
    /// @return The amount of liquidity toekn for shares
    function computeLiquidityFromShares(
        int24 tickLower,
        int24 tickUpper,
        uint256 shares
    )
        internal
        view
        returns (uint128)
    {
        (uint128 position,,) = getPositionInfo(tickLower, tickUpper);

        return uint128(uint256(position) * shares / hypervisor.totalSupply());
    }

    // @notice Get the info of the given position
    // @param tickLower The lower tick of the position
    // @param tickUpper The upper tick of the position
    // @return liquidity The amount of liquidity of the position
    // @return tokensOwed0 Amount of token0 owed
    // @return tokensOwed1 Amount of weth owed
    function getPositionInfo(
        int24 tickLower,
        int24 tickUpper
    )
        internal
        view
        returns (uint128 liquidity, uint128 tokensOwed0, uint128 tokensOwed1)
    {
        bytes32 positionKey;
        address hypervisorAddr = address(hypervisor);

        assembly {
            positionKey :=
                or(
                    shl(24, or(shl(24, hypervisorAddr), and(tickLower, 0xFFFFFF))),
                    and(tickUpper, 0xFFFFFF)
                )
        }

        (liquidity,,,, tokensOwed0, tokensOwed1) = algebraPool.positions(positionKey);
    }

    function _uint128Safe(uint256 x) internal pure returns (uint128) {
        assert(x <= type(uint128).max);
        return uint128(x);
    }

    /// @notice Returns the current strategy's amount of Beefy vault shares
    /// @return _balance balance the strategy's balance of Beefy vault shares
    function _shareBalance() internal view returns (uint256 _balance) {
        assembly {
            // return beefyVault.balanceOf(address(this));
            mstore(0x00, 0x70a08231)
            mstore(0x20, address())
            if iszero(staticcall(gas(), sload(hypervisor.slot), 0x1c, 0x24, 0x00, 0x20)) { revert(0x00, 0x04) }
            _balance := mload(0x00)
        }
    }

    /// @notice Returns the real time estimation of the value in assets held by the strategy
    /// @return the strategy's total assets(idle + investment positions)
    function _estimatedTotalAssets() internal view override returns (uint256) {
        return _underlyingBalance() + _shareValue(_shareBalance());
    }
}
