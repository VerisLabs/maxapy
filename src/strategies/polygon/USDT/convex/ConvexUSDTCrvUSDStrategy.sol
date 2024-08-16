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
import { IUniswapV3Router as IRouter } from "src/interfaces/IUniswap.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import {
    CRV_USD_POLYGON,
    WMATIC_POLYGON,
    CRV_POLYGON,
    CONVEX_BOOSTER_POLYGON,
    CRVUSD_USDT_CONVEX_POOL_ID_POLYGON,
    CURVE_CRVUSD_USDT_POOL_POLYGON
} from "src/helpers/AddressBook.sol";

/// @title ConvexUSDTCrvUSDStrategy
/// @author MaxApy
/// @notice `ConvexUSDTCrvUSDStrategy` supplies USDT into the crvUsd<>usdt pool in Curve, then stakes the curve LP
/// in Convex in order to maximize yield.
contract ConvexUSDTCrvUSDStrategy is BaseConvexStrategyPolygon {
    using SafeTransferLib for address;

    ////////////////////////////////////////////////////////////////
    ///                        CONSTANTS                         ///
    ////////////////////////////////////////////////////////////////
    /// @notice Polygon's WETH Token
    address public constant crvUsd = CRV_USD_POLYGON;
    /// @notice Polygon's WETH Token
    address public constant wmatic = WMATIC_POLYGON;
    /// @notice Polygon's CRV Token
    address public constant crv = CRV_POLYGON;
    /// @notice Main Convex's deposit contract for LP tokens
    IConvexBoosterPolygon public constant convexBooster = IConvexBoosterPolygon(CONVEX_BOOSTER_POLYGON);
    /// @notice Router to perform CRV-WETH swaps
    IRouter public router;
    /// @notice Identifier for the dETH<>usdt Convex pool
    uint256 public constant CRVUSD_USDT_CONVEX_POOL_ID = CRVUSD_USDT_CONVEX_POOL_ID_POLYGON;

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
    /// @param _curveLpPool The address of the strategy's main Curve pool, crvUsd<>usdt pool
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
        (address _token,, address _crvRewards, bool _shutdown,) = convexBooster.poolInfo(CRVUSD_USDT_CONVEX_POOL_ID);

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
        crv.safeApprove(address(_router), type(uint256).max);
        crvUsd.safeApprove(address(curveLpPool), type(uint256).max);
        underlyingAsset.safeApprove(address(curveLpPool), type(uint256).max);

        minSwapCrv = 1e17;
    }

    /// @notice Sets the new router
    /// @dev Approval for CRV will be granted to the new router if it was not already granted
    /// @param _newRouter The new router address
    function setRouter(address _newRouter) external checkRoles(ADMIN_ROLE) {
        // Remove previous router allowance
        crv.safeApprove(address(router), 0);
        // Set new router allowance
        crv.safeApprove(_newRouter, type(uint256).max);

        // Remove previous router allowance
        crv.safeApprove(address(router), 0);
        // Set new router allowance
        crv.safeApprove(_newRouter, type(uint256).max);

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
    /// Note that because of Curve's bonus/penalty approach, we check if it is best to
    /// add liquidity with native ETH or with pegged ETH. It is then expected to always receive
    /// at least `amount` if we perform an exchange from ETH to pegged ETH.
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

        uint256 lpReceived;

        if (amount > 0) {
            uint256 price = curveLpPool.get_virtual_price();
            uint256[] memory amounts = new uint256[](2);
            amounts[1] = amount;
            // Add liquidity to the crvUsd<>usdt pool in usdt [coin1 -> usdt]
            lpReceived = curveLpPool.add_liquidity(amounts, 0, address(this));

            assembly ("memory-safe") {
                // if (lpReceived < minOutputAfterInvestment)
                if lt(lpReceived, minOutputAfterInvestment) {
                    // throw the `MinOutputAmountNotReached` error
                    mstore(0x00, 0xf7c67a48)
                    revert(0x1c, 0x04)
                }
            }

            // Deposit Curve LP into Convex pool with id `CRVUSD_USDT_CONVEX_POOL_ID` and immediately stake convex LP
            // tokens
            // into the rewards contract
            convexBooster.deposit(CRVUSD_USDT_CONVEX_POOL_ID, lpReceived);
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

        // Remove liquidity and obtain usdt
        return curveLpPool.remove_liquidity_one_coin(
            amount,
            1,
            //usdt
            0,
            address(this)
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

        // Exchange CRV <> USDT
        uint256 crvBalance = _crvBalance();

        if (crvBalance > minSwapCrv) {
            bytes memory path = abi.encodePacked(
                _crv(),
                uint24(3000), // CRV <> WMATIC 0.3%
                wmatic,
                uint24(500), // WMATIC <> USDT 0.005%
                underlyingAsset
            );
            router.exactInput(
                IRouter.ExactInputParams({
                    path: path,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: crvBalance,
                    amountOutMinimum: 0
                })
            );
        }

        // Exchange crvUSD <> USDT
        uint256 crvUsdBalance = _crvUsdBalance();
        if (crvUsdBalance > minSwapCrv) {
            curveLpPool.exchange(1, 0, crvUsdBalance, 0);
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
    /// @notice Returns the estimated price for the strategy's Convex's LP token
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
}
