// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import "../helpers/Constants.sol";
import "solady-0.0.201/utils/SafeCastLib.sol";
import "solady-0.0.201/utils/FixedPointMathLib.sol";

/// @title Functions based on Q64.96 sqrt price and liquidity
/// @notice Contains the math that uses square root of price as a Q64.96 and liquidity to compute deltas
library LiquidityTokenMath {
    using SafeCastLib for uint256;

    /// @notice Gets the token0 delta between two prices
    /// @dev Calculates liquidity / sqrt(lower) - liquidity / sqrt(upper)
    /// @param priceLower A Q64.96 sqrt price
    /// @param priceUpper Another Q64.96 sqrt price
    /// @param liquidity The amount of usable liquidity
    /// @param roundUp Whether to round the amount up or down
    /// @return token0Delta Amount of token0 required to cover a position of size liquidity between the two passed
    /// prices
    function calculateToken0Delta(
        uint160 priceLower,
        uint160 priceUpper,
        uint128 liquidity,
        bool roundUp
    )
        internal
        pure
        returns (uint256 token0Delta)
    {
        uint256 priceDelta = priceUpper - priceLower;

        require(priceDelta < priceUpper); // forbids underflow and 0 priceLower
        uint256 liquidityShifted = uint256(liquidity) << Constants.RESOLUTION;

        token0Delta = roundUp
            ? FixedPointMathLib.divUp(FixedPointMathLib.fullMulDivUp(priceDelta, liquidityShifted, priceUpper), priceLower)
            : FixedPointMathLib.mulDiv(priceDelta, liquidityShifted, priceUpper) / priceLower;
    }

    /// @notice Gets the token1 delta between two prices
    /// @dev Calculates liquidity * (sqrt(upper) - sqrt(lower))
    /// @param priceLower A Q64.96 sqrt price
    /// @param priceUpper Another Q64.96 sqrt price
    /// @param liquidity The amount of usable liquidity
    /// @param roundUp Whether to round the amount up, or down
    /// @return token1Delta Amount of token1 required to cover a position of size liquidity between the two passed
    /// prices
    function calculateToken1Delta(
        uint160 priceLower,
        uint160 priceUpper,
        uint128 liquidity,
        bool roundUp
    )
        internal
        pure
        returns (uint256 token1Delta)
    {
        require(priceUpper >= priceLower);
        uint256 priceDelta = priceUpper - priceLower;
        token1Delta = roundUp
            ? FixedPointMathLib.fullMulDivUp(priceDelta, liquidity, Constants.Q96)
            : FixedPointMathLib.mulDiv(priceDelta, liquidity, Constants.Q96);
    }

    /// @notice Helper that gets signed token0 delta
    /// @param priceLower A Q64.96 sqrt price
    /// @param priceUpper Another Q64.96 sqrt price
    /// @param liquidity The change in liquidity for which to compute the token0 delta
    /// @return token0Delta Amount of token0 corresponding to the passed liquidityDelta between the two prices
    function calculateToken0Delta(
        uint160 priceLower,
        uint160 priceUpper,
        int128 liquidity
    )
        internal
        pure
        returns (int256 token0Delta)
    {
        token0Delta = liquidity >= 0
            ? calculateToken0Delta(priceLower, priceUpper, uint128(liquidity), true).toInt256()
            : -calculateToken0Delta(priceLower, priceUpper, uint128(-liquidity), false).toInt256();
    }

    /// @notice Helper that gets signed token1 delta
    /// @param priceLower A Q64.96 sqrt price
    /// @param priceUpper Another Q64.96 sqrt price
    /// @param liquidity The change in liquidity for which to compute the token1 delta
    /// @return token1Delta Amount of token1 corresponding to the passed liquidityDelta between the two prices
    function calculateToken1Delta(
        uint160 priceLower,
        uint160 priceUpper,
        int128 liquidity
    )
        internal
        pure
        returns (int256 token1Delta)
    {
        token1Delta = liquidity >= 0
            ? calculateToken1Delta(priceLower, priceUpper, uint128(liquidity), true).toInt256()
            : -calculateToken1Delta(priceLower, priceUpper, uint128(-liquidity), false).toInt256();
    }
}
