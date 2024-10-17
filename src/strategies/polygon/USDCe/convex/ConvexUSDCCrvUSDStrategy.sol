// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {
    BaseConvexStrategyPolygon,
    BaseStrategy,
    IMaxApyVault,
    SafeTransferLib
} from "src/strategies/base/BaseConvexStrategyPolygon.sol";
import { IConvexBoosterPolygon } from "src/interfaces/IConvexBooster.sol";
import { IConvexRewardsPolygon } from "src/interfaces/IConvexRewards.sol";
import { ICurveLpPool } from "src/interfaces/ICurve.sol";
import { IUniswapV3Router as IRouter, IUniswapV3Pool } from "src/interfaces/IUniswap.sol";
import { OracleLibrary } from "src/lib/OracleLibrary.sol";
import { ICurveAtriCryptoZapper } from "src/interfaces/ICurve.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import {
    CRV_USD_POLYGON,
    USDC_POLYGON,
    WPOL_POLYGON,
    CRV_POLYGON,
    CONVEX_BOOSTER_POLYGON,
    CRVUSD_USDC_CONVEX_POOL_ID_POLYGON,
    CURVE_CRVUSD_USDC_POOL_POLYGON,
    CURVE_CRV_ATRICRYPTO_ZAPPER_POLYGON,
    UNISWAP_V3_USDC_USDCE_POOL_POLYGON,
    TRI_CRYPTO_POOL_POLYGON
} from "src/helpers/AddressBook.sol";

/// @title
/// @author MaxApy
/// @notice `ConvexUSDCCrvUSDStrategy` supplies USDC into the crvUsd<>usdc pool in Curve, then stakes the curve LP
/// in Convex in order to maximize yield.
contract ConvexUSDCCrvUSDStrategy is BaseConvexStrategyPolygon {
    using SafeTransferLib for address;

    ////////////////////////////////////////////////////////////////
    ///                        CONSTANTS                         ///
    ////////////////////////////////////////////////////////////////
    /// @notice Polygon's CRVUSD Token
    address public constant crvUsd = CRV_USD_POLYGON;
    /// @notice Polygon's WETH Token
    address public constant wpol = WPOL_POLYGON;
    /// @notice Polygon's CRV Token
    address public constant crv = CRV_POLYGON;
    /// @notice Main Convex's deposit contract for LP tokens
    IConvexBoosterPolygon public constant convexBooster = IConvexBoosterPolygon(CONVEX_BOOSTER_POLYGON);
    /// @notice Router to perform CRV-WETH swaps
    IRouter public router;
    /// @notice Identifier for the crvUsd<>usdc Convex pool
    uint256 public constant CRVUSD_USDC_CONVEX_POOL_ID = CRVUSD_USDC_CONVEX_POOL_ID_POLYGON;
    /// @notice Address of Uniswap V3 USDC-LUSD pool
    address public constant pool = UNISWAP_V3_USDC_USDCE_POOL_POLYGON;
    /// @notice USDC token for polygon
    address public constant usdc = USDC_POLYGON;
    /// @notice Curve CrvTricrypto zapper in polygon
    ICurveAtriCryptoZapper public constant zapper = ICurveAtriCryptoZapper(CURVE_CRV_ATRICRYPTO_ZAPPER_POLYGON);
    /// @notice CrvTricrypto pool address in polygon
    address public constant triCryptoPool = TRI_CRYPTO_POOL_POLYGON;

    ////////////////////////////////////////////////////////////////
    ///            STRATEGY GLOBAL STATE VARIABLES               ///
    ////////////////////////////////////////////////////////////////

    /*==================CURVE-RELATED STORAGE VARIABLES==================*/
    /// @notice Main Curve pool for this Strategy
    ICurveLpPool public curveLpPool;

    ////////////////////////////////////////////////////////////////
    ///                     INITIALIZATION                       ///
    ////////////////////////////////////////////////////////////////
    constructor() initializer { }

    /// @notice Initialize the Strategy
    /// @param _vault The address of the MaxApy Vault associated to the strategy
    /// @param _keepers The addresses of the keepers to be added as valid keepers to the strategy
    /// @param _strategyName the name of the strategy
    /// @param _curveLpPool The address of the strategy's main Curve pool, crvUsd<>usdc pool
    /// @param _router The router address to perform swaps
    function initialize(
        IMaxApyVault _vault,
        address[] calldata _keepers,
        bytes32 _strategyName,
        address _strategist,
        ICurveLpPool _curveLpPool,
        IRouter _router
    )
        public
        initializer
    {
        __BaseStrategy_init(_vault, _keepers, _strategyName, _strategist);

        // Fetch convex pool data
        (address _token,, address _crvRewards, bool _shutdown,) = convexBooster.poolInfo(CRVUSD_USDC_CONVEX_POOL_ID);

        assembly {
            // Check if Convex pool is in shutdown mode
            if eq(_shutdown, 0x01) {
                // throw the `ConvexPoolShutdown` error
                mstore(0x00, 0xcff936d6)
                revert(0x1c, 0x04)
            }
        }

        convexRewardPool = IConvexRewardsPolygon(_crvRewards);
        convexLpToken = _token;

        // Curve init
        curveLpPool = _curveLpPool;

        // Approve pools
        address(convexLpToken).safeApprove(address(convexBooster), type(uint256).max);

        // Set router
        router = _router;

        // Approve tokens
        usdc.safeApprove(address(_router), type(uint256).max);
        underlyingAsset.safeApprove(address(_router), type(uint256).max);
        crv.safeApprove(address(zapper), type(uint256).max);
        crvUsd.safeApprove(address(_router), type(uint256).max);
        usdc.safeApprove(address(curveLpPool), type(uint256).max);

        minSwapCrv = 1e17;
        maxSingleTrade = 100_000e6;
    }

    /// @notice Sets the new router
    /// @dev Approval for CRV will be granted to the new router if it was not already granted
    /// @param _newRouter The new router address
    function setRouter(address _newRouter) external checkRoles(ADMIN_ROLE) {
        // Remove previous router allowance
        usdc.safeApprove(address(router), 0);
        underlyingAsset.safeApprove(address(router), 0);
        crvUsd.safeApprove(address(router), 0);

        // Set new router allowance
        usdc.safeApprove(address(_newRouter), type(uint256).max);
        underlyingAsset.safeApprove(address(_newRouter), type(uint256).max);
        crvUsd.safeApprove(address(_newRouter), type(uint256).max);

        assembly ("memory-safe") {
            sstore(router.slot, _newRouter) // set the new router in storage

            // Emit the `RouterUpdated` event
            mstore(0x00, _newRouter)
            log1(0x00, 0x20, _ROUTER_UPDATED_EVENT_SIGNATURE)
        }
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL CORE FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////
    /// @notice Invests `amount` of underlying into the Convex pool
    /// @dev We don't perform any reward claim. All assets must have been
    /// previously converted to `underlyingAsset`.
    /// @param amount The amount of underlying to be deposited in the pool
    /// @param minOutputAfterInvestment minimum expected output after `_invest()` (designated in Curve LP tokens)
    /// @return The amount of tokens received, in terms of underlying
    function _invest(uint256 amount, uint256 minOutputAfterInvestment) internal override returns (uint256) {
        // Don't do anything if amount to invest is 0
        if (amount == 0) return 0;

        uint256 underlyingBalance = _underlyingBalance();

        assembly ("memory-safe") {
            if gt(amount, underlyingBalance) {
                // throw the `NotEnoughFundsToInvest` error
                mstore(0x00, 0xb2ff68ae)
                revert(0x1c, 0x04)
            }
        }

        // Invested amount will be a maximum of `maxSingleTrade`
        amount = Math.min(maxSingleTrade, amount);

        uint256 lpReceived;

        if (amount > 0) {
            // Swap the base asset to USDC
            uint256 usdcAmount = router.exactInputSingle(
                IRouter.ExactInputSingleParams({
                    tokenIn: underlyingAsset,
                    tokenOut: usdc,
                    fee: 100, // 0.01% fee
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: amount,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
            uint256[] memory amounts = new uint256[](2);
            amounts[1] = usdcAmount;
            // Add liquidity to the crvUsd<>usdc pool in usdc [coin1 -> usdc]
            lpReceived = curveLpPool.add_liquidity(amounts, 0, address(this));

            assembly ("memory-safe") {
                // if (lpReceived < minOutputAfterInvestment)
                if lt(lpReceived, minOutputAfterInvestment) {
                    // throw the `MinOutputAmountNotReached` error
                    mstore(0x00, 0xf7c67a48)
                    revert(0x1c, 0x04)
                }
            }

            // Deposit Curve LP into Convex pool with id `CRVUSD_USDC_CONVEX_POOL_ID` and immediately stake convex LP
            // tokens
            // into the rewards contract
            convexBooster.deposit(CRVUSD_USDC_CONVEX_POOL_ID, lpReceived);
        }

        emit Invested(address(this), amount);

        return _lpValue(lpReceived);
    }

    /// @notice Divests amount `amount` from the Convex pool
    /// Note that divesting from the pool could potentially cause loss, so the divested amount might actually be
    /// different from
    /// the requested `amount` to divest
    /// @dev care should be taken, as the `amount` parameter is not in terms of underlying,
    /// but in terms of Curve's LP tokens
    /// Note that if minimum withdrawal amount is not reached, funds will not be divested, and this
    /// will be accounted as a loss later.
    /// @return amountDivested the total amount divested, in terms of underlying asset
    function _divest(uint256 amount) internal override returns (uint256 amountDivested) {
        if (amount == 0) return 0;

        // Withdraw from Convex and unwrap directly to Curve LP tokens
        convexRewardPool.withdraw(amount, false);

        // Remove liquidity and obtain usdc
        uint256 amountIn = curveLpPool.remove_liquidity_one_coin(
            amount,
            1,
            //usdc
            0,
            address(this)
        );

        // Swap USDC to base asset
        return router.exactInputSingle(
            IRouter.ExactInputSingleParams({
                tokenIn: usdc,
                tokenOut: underlyingAsset,
                fee: 100, // 0.01% fee
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }

    /// @notice Claims rewards, converting them to `underlyingAsset`.
    /// @dev MinOutputAmounts are left as 0 and properly asserted globally on `harvest()`.
    function _unwindRewards(IConvexRewardsPolygon rewardPool) internal override {
        uint256 earned = rewardPool.earned(address(this));

        if (earned > 0) {
            // Claim CRV and CVX rewards
            rewardPool.getReward(address(this), address(this));
        }

        uint256 crvBalance = _crvBalance();

        if (crvBalance > minSwapCrv) {
            zapper.exchange(triCryptoPool, 0, 2, crvBalance, 0);
        }

        // Exchange crvUSD <> USDCe
        uint256 crvUsdBalance = _crvUsdBalance();

        if (crvUsdBalance > 0) {
            bytes memory path = abi.encodePacked(
                crvUsd,
                uint24(3000), // crvUsd <> WMATIC 0.3%
                wpol,
                uint24(500), // WMATIC <> USDCe 0.05%
                underlyingAsset
            );
            router.exactInput(
                IRouter.ExactInputParams({
                    path: path,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: crvUsdBalance,
                    amountOutMinimum: 0
                })
            );
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
        // the requested amount, we divest from the Curve liquidity pool
        if (underlyingBalance < requestedAmount) {
            uint256 amountToWithdraw;
            unchecked {
                amountToWithdraw = requestedAmount - underlyingBalance;
            }
            uint256 lp = _lpForAmount(amountToWithdraw);
            uint256 staked = _stakedBalance(convexRewardPool);

            assembly {
                // Adjust computed lp amount by current lp balance
                if gt(lp, staked) { lp := staked }
            }

            uint256 withdrawn = curveLpPool.calc_withdraw_one_coin(lp, 1);

            if (withdrawn < amountToWithdraw) loss = amountToWithdraw - withdrawn;
        }
        liquidatedAmount = requestedAmount - loss;
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL VIEW FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////
    /// @notice Determines how many lp tokens depositor of `amount` of underlying would receive.
    /// @dev Some loss of precision is occured, but it is not critical as this is only an underestimation of
    /// the actual assets, and profit will be later accounted for.
    /// @return returns the estimated amount of lp tokens computed in exchange for underlying `amount`
    function _lpValue(uint256 lp) internal view override returns (uint256) {
        return _estimateAmountOut(USDC_POLYGON, underlyingAsset, uint128(super._lpValue(lp)), 1800); // use a 30 min
    }

    /// @notice Determines how many lp tokens depositor of `amount` of underlying would receive.
    /// @return returns the estimated amount of lp tokens computed in exchange for underlying `amount`
    function _lpForAmount(uint256 amount) internal view override returns (uint256) {
        return _estimateAmountOut(underlyingAsset, USDC_POLYGON, uint128(amount), 1800) * 1e18 / _lpPrice();
    }

    /// @notice Returns the estimated price for the strategy's Curve's LP token
    /// @return returns the estimated lp token price
    function _lpPrice() internal view override returns (uint256) {
        return (
            (
                curveLpPool.get_virtual_price()
                    * Math.min(curveLpPool.get_dy(1, 0, 1e6), curveLpPool.get_dy(0, 1, 1 ether))
            ) / 1 ether
        );
    }

    /// @dev returns the address of the CRV token for this context
    function _crv() internal pure override returns (address) {
        return crv;
    }

    /// @dev returns the crvUsd balance
    function _crvUsdBalance() internal view returns (uint256) {
        return crvUsd.balanceOf(address(this));
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

    ////////////////////////////////////////////////////////////////
    ///                      SIMULATION                          ///
    ////////////////////////////////////////////////////////////////

    function _simulateHarvest() public override {
        address harvester = address(0);
        uint256 minOutputAfterInvestment = 0;
        uint256 minExpectedBalance = 0;

        uint256 expectedBalance;
        uint256 outputAfterInvestment;

        // normally the treasury would get the management fee
        address managementFeeReceiver;
        // if the harvest was done from the vault means it the
        // harvest was triggered on a deposit
        if (msg.sender == address(vault)) {
            // the depositing user will get the management fees as a reward
            // for paying gas costs of harvest
            managementFeeReceiver = harvester;
        }

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
            (unrealizedProfit, loss, debtPayment) = _prepareReturn(debtOutstanding, minExpectedBalance);

            expectedBalance = _underlyingBalance();
        }

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

        uint256 sharesBalanceBefore = curveLpPool.balances(address(this));
        // Check if vault transferred underlying and re-invest it
        _adjustPosition(debtOutstanding, minOutputAfterInvestment);
        outputAfterInvestment = curveLpPool.balances(address(this)) - sharesBalanceBefore;
        _snapshotEstimatedTotalAssets();

        // revert with data we need
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, expectedBalance)
            mstore(add(ptr, 32), outputAfterInvestment)
            revert(ptr, 64)
        }
    }
}
