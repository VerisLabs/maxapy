// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import {
    CONVEX_BOOSTER_MAINNET,
    CONVEX_ZUNETH_PXETH_CONVEX_POOL_ID_MAINNET,
    CRV_MAINNET,
    CURVE_CVX_WETH_POOL_MAINNET,
    CVX_MAINNET,
    PXETH_MAINNET,
    WETH_MAINNET,
    PANCAKESWAP_V3_ROUTER_MAINNET,
    PANCAKESWAP_V3_WETH_PXETH_POOL_MAINNET
} from "src/helpers/AddressBook.sol";
import { IConvexBooster } from "src/interfaces/IConvexBooster.sol";
import { IConvexRewards } from "src/interfaces/IConvexRewards.sol";
import { ICurveLpPool } from "src/interfaces/ICurve.sol";
import { IUniswapV3Pool, IUniswapV3Router as IRouterV3, IUniswapV2Router02 as IRouter } from "src/interfaces/IUniswap.sol";
import { IWETH } from "src/interfaces/IWETH.sol";
import {
    BaseConvexStrategy, BaseStrategy, IMaxApyVault, SafeTransferLib
} from "src/strategies/base/BaseConvexStrategy.sol";
import { OracleLibrary } from "src/lib/OracleLibrary.sol";
import { ERC20 } from "solady/tokens/ERC20.sol";
import { SafeCastLib } from "solady/utils/SafeCastLib.sol";

import {console2} from "forge-std/console2.sol";
/// @title ConvexzunETHpxETHStrategy
/// @author MaxApy
/// @notice `ConvexzunETHpxETHStrategy` supplies ETH into the zunETH-pxETH pool in Curve, then stakes the curve LP
/// in Convex in order to maximize yield.
contract ConvexzunETHpxETHStrategy is BaseConvexStrategy {
    using SafeTransferLib for address;
    using SafeCastLib for uint256;

    ////////////////////////////////////////////////////////////////
    ///                        CONSTANTS                         ///
    ////////////////////////////////////////////////////////////////

    /// @notice Ethereum mainnet's CRV Token
    address public constant crv = CRV_MAINNET;
    /// @notice Ethereum mainnet's CVX Token
    address public constant cvx = CVX_MAINNET;
    /// @notice Ethereum mainnet's frxETH Token
    address public constant pxETH = PXETH_MAINNET;
    /// @notice Main Convex's deposit contract for LP tokens
    IConvexBooster public constant convexBooster = IConvexBooster(CONVEX_BOOSTER_MAINNET);
    /// @notice Router to perform CRV-WETH swaps
    IRouter public router;
    /// @notice CVX-WETH pool in Curve
    ICurveLpPool public constant cvxWethPool = ICurveLpPool(CURVE_CVX_WETH_POOL_MAINNET);
    /// @notice Identifier for the zunETH<>pxETH Convex pool
    uint256 public constant ZUNETH_PXETH_CONVEX_POOL_ID = CONVEX_ZUNETH_PXETH_CONVEX_POOL_ID_MAINNET;

    ////////////////////////////////////////////////////////////////
    ///            STRATEGY GLOBAL STATE VARIABLES               ///
    ////////////////////////////////////////////////////////////////

    /*==================CURVE-RELATED STORAGE VARIABLES==================*/
    /// @notice Main Curve pool for this Strategy
    ICurveLpPool public curveLpPool;

    /*==================CURVE-RELATED STORAGE VARIABLES==================*/
    /// @notice pancakeswap WETH-pxETH router
    IRouterV3 public constant pancakeswapRouter = IRouterV3(PANCAKESWAP_V3_ROUTER_MAINNET);
    address public constant wETHpxETHPool = PANCAKESWAP_V3_WETH_PXETH_POOL_MAINNET;

    ////////////////////////////////////////////////////////////////
    ///                     INITIALIZATION                       ///
    ////////////////////////////////////////////////////////////////
    constructor() initializer { }

    /// @notice Initialize the Strategy
    /// @param _vault The address of the MaxApy Vault associated to the strategy
    /// @param _keepers The addresses of the keepers to be added as valid keepers to the strategy
    /// @param _strategyName the name of the strategy
    /// @param _curveLpPool The address of the strategy's main Curve pool, zunETH-pxETH pool
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
        (, address _token,, address _crvRewards,, bool _shutdown) = convexBooster.poolInfo(ZUNETH_PXETH_CONVEX_POOL_ID);
        
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
        curveLpPool = _curveLpPool;
        


        // Approve pools
        address(_curveLpPool).safeApprove(address(convexBooster), type(uint256).max);

        // Set router
        router = _router;
        

        WETH_MAINNET.safeApprove(address(pancakeswapRouter), type(uint256).max);
        PXETH_MAINNET.safeApprove(address(pancakeswapRouter), type(uint256).max);


        crv.safeApprove(address(_router), type(uint256).max);
        cvx.safeApprove(address(cvxWethPool), type(uint256).max);
        pxETH.safeApprove(address(curveLpPool), type(uint256).max);
        // pxETH.safeApprove(address(curveWETHpxETHPool), type(uint256).max);

        maxSingleTrade = 250 * 1e18;
        

        


        minSwapCrv = 1e17;
        minSwapCvx = 1e18;
    }
        
    /// @notice Sets the new router
    /// @dev Approval for CRV will be granted to the new router if it was not already granted
    /// @param _newRouter The new router address
    function setRouter(address _newRouter) external checkRoles(ADMIN_ROLE) {
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

        // Invested amount will be a maximum of `maxSingleTrade`
        amount = Math.min(maxSingleTrade, amount);
        
        // Swap WETH for pxETH
        pancakeswapRouter.exactInputSingle(
            IRouterV3.ExactInputSingleParams({
                    tokenIn: WETH_MAINNET,
                    tokenOut: PXETH_MAINNET,
                    fee: 100, // 0.01%
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: amount,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
        );
        uint256 pxEthReceivedAmount = ERC20(PXETH_MAINNET).balanceOf(address(this));
        
        // curveWETHpxETHPool.exchange{ value: amount }(0, 1, amount, 0);
        


        uint256[] memory amounts = new uint256[](2);
        amounts[1] = pxEthReceivedAmount;

        // Add liquidity to the zunETH-pxETH pool in pxETH [coin1 -> pxETH]
        uint256 lpReceived = curveLpPool.add_liquidity(amounts, 0, address(this));
        


        assembly ("memory-safe") {
            // if (lpReceived < minOutputAfterInvestment)
            if lt(lpReceived, minOutputAfterInvestment) {
                // throw the `MinOutputAmountNotReached` error
                mstore(0x00, 0xf7c67a48)
                revert(0x1c, 0x04)
            }
        }

        // Deposit Curve LP into Convex pool with id `ZUNETH_PXETH_CONVEX_POOL_ID` and immediately stake convex LP tokens
        // into the rewards contract
        convexBooster.deposit(ZUNETH_PXETH_CONVEX_POOL_ID, lpReceived, true);

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
        // Withdraw from Convex and unwrap directly to Curve LP tokens
        convexRewardPool.withdrawAndUnwrap(amount, false);

        // Remove liquidity and obtain pxETH
        uint256 amountWithdrawn = curveLpPool.remove_liquidity_one_coin(
            amount,
            1,
            //pxETH
            0
        );

        if (amountWithdrawn != 0) {
            // Swap pxETH for WETH
            // Swap WETH for pxETH
        pancakeswapRouter.exactInputSingle(
            IRouterV3.ExactInputSingleParams({
                    tokenIn: PXETH_MAINNET,
                    tokenOut: WETH_MAINNET,
                    fee: 100, // 0.01%
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: amountWithdrawn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
        );

            uint256 wethReceived = ERC20(WETH_MAINNET).balanceOf(address(this));
            

            // curveWETHpxETHPool.exchange(1, 0, amountWithdrawn, 0);
            // Wrap ETH into WETH
            // IWETH(address(underlyingAsset)).deposit{ value: wethReceived }();
            return wethReceived;
        }
    }

    /// @notice Claims rewards, converting them to `underlyingAsset`.
    /// @dev MinOutputAmounts are left as 0 and properly asserted globally on `harvest()`.
    function _unwindRewards(IConvexRewards rewardPool) internal override {
        // Claim CRV and CVX rewards
        rewardPool.getReward(address(this), true);

        // Exchange CRV <> WETH
        uint256 crvBalance = _crvBalance();
        if (crvBalance > minSwapCrv) {
            address[] memory path = new address[](2);
            path[0] = crv;
            path[1] = underlyingAsset;
            router.swapExactTokensForTokens(crvBalance, 0, path, address(this), block.timestamp);
        }

        // Exchange CVX <> WETH
        uint256 cvxBalance = _cvxBalance();
        if (cvxBalance > minSwapCvx) {
            cvxWethPool.exchange(1, 0, cvxBalance, 0, false);
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

            amountToWithdraw = _estimateAmountOut(WETH_MAINNET, PXETH_MAINNET, amountToWithdraw.toUint128(), wETHpxETHPool, 1800);
            console2.log("###   ~ file: ConvexzunETHpxETHStrategy.sol:323 ~ amountToWithdraw:", amountToWithdraw);

            uint256 lp = _lpForAmount(amountToWithdraw);
            console2.log("###   ~ file: ConvexzunETHpxETHStrategy.sol:331 ~ lp:", lp);

            uint256 staked = _stakedBalance(convexRewardPool);
            console2.log("###   ~ file: ConvexzunETHpxETHStrategy.sol:334 ~ staked:", staked);


            assembly {
                // Adjust computed lp amount by current lp balance
                if gt(lp, staked) { lp := staked }
            }

            uint256 withdrawn = curveLpPool.calc_withdraw_one_coin(lp, 1);
            console2.log("###   ~ file: ConvexzunETHpxETHStrategy.sol:342 ~ withdrawn:", withdrawn);

            if (withdrawn != 0) {
                withdrawn = _estimateAmountOut(PXETH_MAINNET, WETH_MAINNET, withdrawn.toUint128(), wETHpxETHPool, 1800);
                console2.log("###   ~ file: ConvexzunETHpxETHStrategy.sol:349 ~ withdrawn:", withdrawn);

            }
            if (withdrawn < amountToWithdraw) loss = amountToWithdraw - withdrawn;
        }
        liquidatedAmount = requestedAmount - loss;
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL VIEW FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////

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
        console2.log("###   ~ file: ConvexzunETHpxETHStrategy.sol:375 ~ secondsAgos[1]:", secondsAgos[1]);


        // int56 since tick * time = int24 * uint32
        // 56 = 24 + 32
        (int56[] memory tickCumulatives,) = IUniswapV3Pool(pool).observe(secondsAgos);

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
        console2.log("###   ~ file: ConvexzunETHpxETHStrategy.sol:381 ~ tickCumulativesDelta:", tickCumulativesDelta);


        // int56 / uint32 = int24
        int24 tick = int24(int256(tickCumulativesDelta) / int256(int32(secondsAgo)));
        console2.log("###   ~ file: ConvexzunETHpxETHStrategy.sol:388 ~ tick:", tick);

        // Always round to negative infinity

        if (tickCumulativesDelta < 0 && (int256(tickCumulativesDelta) % int256(int32(secondsAgo)) != 0)) {
            tick--;
        }

        

        console2.log("###   ~ file: ConvexzunETHpxETHStrategy.sol:397 ~ amountOut:", amountIn);

        amountOut = OracleLibrary.getQuoteAtTick(tick, amountIn, tokenIn, tokenOut);
        console2.log("###   ~ file: ConvexzunETHpxETHStrategy.sol:401 ~ amountIn:", amountIn);


    }


    /// @notice Returns the estimated price for the strategy's Convex's LP token
    /// @return returns the estimated lp token price
    function _lpPrice() internal view override returns (uint256) {
        return (
            (
                curveLpPool.get_virtual_price()
                    * Math.min(curveLpPool.get_dy(1, 0, 1 ether), curveLpPool.get_dy(0, 1, 1 ether))
            ) / 1 ether
        );
    }

    /// @dev returns the address of the CRV token for this context
    function _crv() internal pure override returns (address) {
        return crv;
    }

    /// @dev returns the address of the CVX token for this context
    function _cvx() internal pure override returns (address) {
        return cvx;
    }

    //solhint-disable no-empty-blocks
    receive() external payable { }

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
        address managementFeeReceiver;

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

        uint256 sharesBalanceBefore = curveLpPool.balanceOf(address(this));
        // Check if vault transferred underlying and re-invest it
        _adjustPosition(debtOutstanding, 0);
        outputAfterInvestment = curveLpPool.balanceOf(address(this)) - sharesBalanceBefore;
        actualInvest = _lpValue(outputAfterInvestment);
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
