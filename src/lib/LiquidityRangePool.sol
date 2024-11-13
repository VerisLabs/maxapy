// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { LiquidityTokenMath } from "./LiquidityTokenMath.sol";
import { OracleLibrary } from "./OracleLibrary.sol";

library LiquidityRangePool {
    function computeTokenAmountsForLiquidity(
        int24 bottomTick,
        int24 topTick,
        int128 liquidityDelta,
        int24 currentTick,
        uint160 currentPrice
    )
        public
        pure
        returns (int256 amount0, int256 amount1, int128 globalLiquidityDelta)
    {
        // If current tick is less than the provided bottom one then only the token0 has to be provided
        if (currentTick < bottomTick) {
            amount0 = LiquidityTokenMath.calculateToken0Delta(
                OracleLibrary.getSqrtRatioAtTick(bottomTick), OracleLibrary.getSqrtRatioAtTick(topTick), liquidityDelta
            );
        } else if (currentTick < topTick) {
            amount0 = LiquidityTokenMath.calculateToken0Delta(
                currentPrice, OracleLibrary.getSqrtRatioAtTick(topTick), liquidityDelta
            );

            amount1 = LiquidityTokenMath.calculateToken1Delta(
                OracleLibrary.getSqrtRatioAtTick(bottomTick), currentPrice, liquidityDelta
            );

            globalLiquidityDelta = liquidityDelta;
        }
        // If current tick is greater than the provided top one then only the token1 has to be provided
        else {
            amount1 = LiquidityTokenMath.calculateToken1Delta(
                OracleLibrary.getSqrtRatioAtTick(bottomTick), OracleLibrary.getSqrtRatioAtTick(topTick), liquidityDelta
            );
        }
    }
}
