// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {CommonSwapLib} from "./CommonSwapLib.sol";
import {IUniswapV3Router, IUniswapV3Factory} from "../interfaces/IUniswap.sol";
import {UNISWAP_V3_ROUTER_MAINNET, UNISWAP_V3_FACTORY_MAINNET} from "../../helpers/AddressBook.sol";

library UniswapV3SwapLib {

    using CommonSwapLib for CommonSwapLib.SwapParams;
    

    function executeSwap(CommonSwapLib.SwapParams memory params) internal returns (uint256 amountOut) {

        params.validateSwapParams();
        CommonSwapLib.safeApprove(params.fromToken, UNISWAP_V3_ROUTER_MAINNET, params.amountIn);

        uint24 poolFee = getBestFeeTier(params.fromToken, params.toToken);

        IUniswapV3Router.ExactInputSingleParams memory _params =
            IUniswapV3Router.ExactInputSingleParams({
                tokenIn: params.fromToken,
                tokenOut: params.toToken,
                fee: poolFee,
                recipient: params.recipient,
                deadline: block.timestamp,
                amountIn: params.amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        
        amountOut = IUniswapV3Router(UNISWAP_V3_ROUTER_MAINNET).exactInputSingle(_params);
        
    }

    function getBestFeeTier(
        address tokenA,
        address tokenB
    ) internal view returns (uint24 bestFeeTier) {
        uint24[4] memory fees = [uint24(100), 500, 3000, 10000];
        address bestPool;
        for (uint256 i = 0; i < fees.length; i++) {
            address pool = IUniswapV3Factory(UNISWAP_V3_FACTORY_MAINNET).getPool(tokenA, tokenB, fees[i]);
            if (pool != address(0)) {
                bestFeeTier = fees[i];
                bestPool = pool;
                break; // Select the first matching fee tier
            }
        }
        require(bestPool != address(0), "No pool available for token pair");
    }
}