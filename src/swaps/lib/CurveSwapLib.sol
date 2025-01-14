// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {CommonSwapLib} from "./CommonSwapLib.sol";
import {CURVE_META_REGISTRY} from "../../helpers/AddressBook.sol";
import {ICurveRegistry, ICurveLpPool} from "../interfaces/ICurve.sol";
import {console2} from "forge-std/console2.sol";

library CurveSwapLib {

    using CommonSwapLib for CommonSwapLib.SwapParams;

    function getPool(address tokenA, address tokenB) internal view returns (address pool) {
        pool = ICurveRegistry(CURVE_META_REGISTRY).find_pool_for_coins(tokenA,tokenB);
        console2.log("###   ~ file: CurveSwapLib.sol:15 ~ getPool ~ pool:", pool);
        return pool;
    }

    function executeSwap(CommonSwapLib.SwapParams memory params) internal returns (uint256 amountOut) {
        params.validateSwapParams();

        address pool = getPool(params.fromToken,params.toToken);
        ICurveLpPool curvePool = ICurveLpPool(pool);

        CommonSwapLib.safeApprove(params.fromToken, pool, params.amountIn);

        if(params.fromToken == curvePool.coins(0)) {
           amountOut = curvePool.exchange(0, 1, params.amountIn, params.minAmountOut);
        } else {
            amountOut = curvePool.exchange(1, 0, params.amountIn, params.minAmountOut);
        }

    }
}