// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {
    BaseConvexStrategy, BaseStrategy, IMaxApyVault, SafeTransferLib
} from "src/strategies/base/BaseConvexStrategy.sol";
import { IConvexBooster } from "src/interfaces/IConvexBooster.sol";
import { IConvexRewards } from "src/interfaces/IConvexRewards.sol";
import { IUniswapV3Router as IRouter } from "src/interfaces/IUniswap.sol";
import { ICurveLpPool, ICurveLendingPool } from "src/interfaces/ICurve.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import {
    WETH_MAINNET,
    CRV_MAINNET,
    CVX_MAINNET,
    CRVUSD_MAINNET,
    CONVEX_BOOSTER_MAINNET,
    UNISWAP_V3_ROUTER_MAINNET,
    CONVEX_CRVUSD_WETH_COLLATERAL_POOL_ID_MAINNET
} from "src/helpers/AddressBook.sol";

/// @title ConvexCrvUSDWethCollateralStrategy
/// @author MaxApy
/// @notice `ConvexCrvUSDWethCollateralStrategy` supplies CrvUSD into the CrvUSD(WETH Collateral) lending pool in Curve,
/// then
/// stakes the curve LP
/// in Convex in order to maximize yield.
contract ConvexCrvUSDWethCollateralStrategy is BaseConvexStrategy {
    using SafeTransferLib for address;

    ////////////////////////////////////////////////////////////////
    ///                        CONSTANTS                         ///
    ////////////////////////////////////////////////////////////////
    /// @notice Ethereum mainnet's WETH Token
    address public constant weth = WETH_MAINNET;
    /// @notice Ethereum mainnet's CRV Token
    address public constant crv = CRV_MAINNET;
    /// @notice Ethereum mainnet's CVX Token
    address public constant cvx = CVX_MAINNET;
    /// @notice Ethereum mainnet's crvUsd Token
    address public constant crvUsd = CRVUSD_MAINNET;
    /// @notice Main Convex's deposit contract for LP tokens
    IConvexBooster public constant convexBooster = IConvexBooster(CONVEX_BOOSTER_MAINNET);
    /// @notice Identifier for the crvUsd(WETH collateral) Convex lending pool
    uint256 public constant CRVUSD_WETH_COLLATERAL_POOL_ID = CONVEX_CRVUSD_WETH_COLLATERAL_POOL_ID_MAINNET;
    /// @notice Uniswap V3 router
    IRouter public constant router = IRouter(UNISWAP_V3_ROUTER_MAINNET);

    ////////////////////////////////////////////////////////////////
    ///            STRATEGY GLOBAL STATE VARIABLES               ///
    ////////////////////////////////////////////////////////////////

    /*==================CURVE-RELATED STORAGE VARIABLES==================*/
    /// @notice Main Curve pool for this Strategy
    ICurveLendingPool public curveLendingPool;

    /// @notice Curve's usdc-crvUsd pool
    ICurveLpPool public curveUsdcCrvUsdPool;

    ////////////////////////////////////////////////////////////////
    ///                     INITIALIZATION                       ///
    ////////////////////////////////////////////////////////////////
    constructor() initializer { }

    /// @notice Initialize the Strategy
    /// @param _vault The address of the MaxApy Vault associated to the strategy
    /// @param _keepers The addresses of the keepers to be added as valid keepers to the strategy
    /// @param _strategyName the name of the strategy
    /// @param _curveLendingPool The address of the strategy's main Curve pool, dETH-crvUsd pool
    /// @param _curveUsdcCrvUsdPool The address of Curve's ETH-crvUsd pool
    function initialize(
        IMaxApyVault _vault,
        address[] calldata _keepers,
        bytes32 _strategyName,
        address _strategist,
        ICurveLendingPool _curveLendingPool,
        ICurveLpPool _curveUsdcCrvUsdPool
    )
        public
        initializer
    {
        __BaseStrategy_init(_vault, _keepers, _strategyName, _strategist);

        // Fetch convex pool data
        (, address _token,, address _crvRewards,, bool _shutdown) =
            convexBooster.poolInfo(CRVUSD_WETH_COLLATERAL_POOL_ID);

        assembly {
            // Check if Convex pool is in shutdown mode
            if eq(_shutdown, 0x01) {
                // throw the `ConvexPoolShutdown` error
                mstore(0x00, 0xcff936d6)
                revert(0x1c, 0x04)
            }
        }

        convexRewardPool = IConvexRewards(_crvRewards);
        convexLpToken = _token;
        rewardToken = IConvexRewards(_crvRewards).rewardToken();

        // Curve init
        curveLendingPool = _curveLendingPool;
        curveUsdcCrvUsdPool = _curveUsdcCrvUsdPool;

        // Approve pools
        address(_curveLendingPool).safeApprove(address(convexBooster), type(uint256).max);

        crv.safeApprove(address(router), type(uint256).max);
        cvx.safeApprove(address(router), type(uint256).max);
        crvUsd.safeApprove(address(curveLendingPool), type(uint256).max);
        crvUsd.safeApprove(address(curveUsdcCrvUsdPool), type(uint256).max);
        underlyingAsset.safeApprove(address(curveUsdcCrvUsdPool), type(uint256).max);

        maxSingleTrade = 1000 * 1e6;

        minSwapCrv = 1e14;
        minSwapCvx = 1e14;
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

        // Invested amount will be a maximum of `maxSingleTrade`
        amount = Math.min(maxSingleTrade, amount);

        // Swap USDC for crvUsd
        uint256 crvUsdReceived = curveUsdcCrvUsdPool.exchange(0, 1, amount, 0);

        // Add liquidity to the lending pool
        uint256 lpReceived = curveLendingPool.deposit(crvUsdReceived, address(this));

        assembly ("memory-safe") {
            // if (lpReceived < minOutputAfterInvestment)
            if lt(lpReceived, minOutputAfterInvestment) {
                // throw the `MinOutputAmountNotReached` error
                mstore(0x00, 0xf7c67a48)
                revert(0x1c, 0x04)
            }
        }

        // Deposit Curve LP into Convex pool with id `CRVUSD_WETH_COLLATERAL_POOL_ID` and immediately stake convex LP
        // tokens
        // into the rewards contract
        convexBooster.deposit(CRVUSD_WETH_COLLATERAL_POOL_ID, lpReceived, true);

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
    /// @return the total amount divested, in terms of underlying asset
    function _divest(uint256 amount) internal override returns (uint256) {
        // Withdraw from Convex and unwrap directly to Curve LP tokens
        convexRewardPool.withdrawAndUnwrap(amount, false);

        // Remove liquidity and obtain crvUsd
        uint256 amountWithdrawn = curveLendingPool.redeem(amount, address(this), address(this));

        // Swap crvUsd for USDC
        uint256 usdcReceived = curveUsdcCrvUsdPool.exchange(1, 0, amountWithdrawn, 0);

        return usdcReceived;
    }

    /// @notice Claims rewards, converting them to `underlyingAsset`.
    /// @dev MinOutputAmounts are left as 0 and properly asserted globally on `harvest()`.
    function _unwindRewards(IConvexRewards rewardPool) internal override {
        // Claim CRV and CVX rewards
        rewardPool.getReward(address(this), true);

        // Exchange CVX <> CRV
        uint256 cvxBalance = _cvxBalance();
        if (cvxBalance > minSwapCvx) {
            router.exactInputSingle(
                IRouter.ExactInputSingleParams({
                    tokenIn: _cvx(),
                    tokenOut: _crv(),
                    fee: 10_000, // 1%
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: cvxBalance,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        }

        // Exchange CRV <> USDC
        uint256 crvBalance = _crvBalance();
        if (crvBalance > minSwapCrv) {
            bytes memory path = abi.encodePacked(
                _crv(),
                uint24(3000), // CRV <> WETH 0.3%
                weth,
                uint24(500), // WETH <> USDC 0.005%
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
            uint256 value = _lpForAmount(amountToWithdraw);
            uint256 withdrawn = _lpValue(value);

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
        if (lp == 0) return 0;
        return curveUsdcCrvUsdPool.get_dy(1, 0, curveLendingPool.previewRedeem(lp));
    }

    /// @notice Determines how many lp tokens depositor of `amount` of underlying would receive.
    /// @return returns the estimated amount of lp tokens computed in exchange for underlying `amount`
    function _lpForAmount(uint256 amount) internal view override returns (uint256) {
        if (amount == 0) return 0;
        return curveLendingPool.convertToShares(curveUsdcCrvUsdPool.get_dy(0, 1, amount));
    }

    /// @notice Returns the estimated price for the strategy's Convex's LP token
    /// @return returns the estimated lp token price
    function _lpPrice() internal view override returns (uint256) { }

    /// @dev returns the address of the CRV token for this context
    function _crv() internal pure override returns (address) {
        return crv;
    }

    /// @dev returns the address of the CVX token for this context
    function _cvx() internal pure override returns (address) {
        return cvx;
    }
}
