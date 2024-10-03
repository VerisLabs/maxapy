// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8;

import { TokenDeltaMath } from "./TokenDeltaMath.sol";
import { OracleLibrary } from "./OracleLibrary.sol";

import {console2} from "forge-std/console2.sol";

library AlgebraPool {

    function _getAmountsForLiquidity(
    int24 bottomTick,
    int24 topTick,
    int128 liquidityDelta,
    int24 currentTick,
    uint160 currentPrice
  )
    public
    pure
    returns (
      int256 amount0,
      int256 amount1,
      int128 globalLiquidityDelta
    )
  {
    console2.log("###   ~ file: AlgebraPool.sol:28 ~ bottomTick:", bottomTick);

      console2.log("###   ~ file: AlgebraPool.sol:28 ~ currentTick:", currentTick);
      
    // If current tick is less than the provided bottom one then only the token0 has to be provided
    if (currentTick < bottomTick) {
      

      amount0 = TokenDeltaMath.getToken0Delta(OracleLibrary.getSqrtRatioAtTick(bottomTick), OracleLibrary.getSqrtRatioAtTick(topTick), liquidityDelta);
    } else if (currentTick < topTick) {
      amount0 = TokenDeltaMath.getToken0Delta(currentPrice, OracleLibrary.getSqrtRatioAtTick(topTick), liquidityDelta);
      

      amount1 = TokenDeltaMath.getToken1Delta(OracleLibrary.getSqrtRatioAtTick(bottomTick), currentPrice, liquidityDelta);

      globalLiquidityDelta = liquidityDelta;
    }
    // If current tick is greater than the provided top one then only the token1 has to be provided
    else {
      amount1 = TokenDeltaMath.getToken1Delta(OracleLibrary.getSqrtRatioAtTick(bottomTick), OracleLibrary.getSqrtRatioAtTick(topTick), liquidityDelta);
    }

    console2.log("###   ~ file: AlgebraPool.sol:31 ~ amount0:", amount0);

    console2.log("###   ~ file: AlgebraPool.sol:40 ~ amount1:", amount1);
  }
}