// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {
    CompoundV3USDTStrategy, SafeTransferLib
} from "src/strategies/mainnet/USDC/compoundV3/CompoundV3USDTStrategy.sol";

contract CompoundV3USDTStrategyWrapper is CompoundV3USDTStrategy {
    using SafeTransferLib for address;

    function triggerLoss(uint256 amount) external {
        underlyingAsset.safeTransfer(address(underlyingAsset), amount);
    }

    function mockReport(uint128 gain, uint128 loss, uint128 debtPayment, address treasury) external {
        vault.report(gain, loss, debtPayment, treasury);
    }

    function prepareReturn(
        uint256 debtOutstanding,
        uint256 minExpectedBalance
    )
        external
        returns (uint256 unrealizedProfit, uint256 loss, uint256 debtPayment)
    {
        (unrealizedProfit, loss, debtPayment) = _prepareReturn(debtOutstanding, minExpectedBalance);
    }

    function adjustPosition() external {
        _adjustPosition(0, 0);
    }

    function invest(uint256 amount, uint256 minOutputAfterInvestment) external returns (uint256) {
        return _invest(amount, minOutputAfterInvestment);
    }

    function divest(
        uint256 amount,
        uint256 rewardstoWithdraw,
        bool reinvestRemainigRewards
    )
        external
        returns (uint256)
    {
        return _divest(amount, rewardstoWithdraw, reinvestRemainigRewards);
    }

    function liquidatePosition(uint256 amountNeeded) external returns (uint256, uint256) {
        return _liquidatePosition(amountNeeded);
    }

    function liquidateAllPositions() external returns (uint256) {
        return _liquidateAllPositions();
    }

    function unwindRewards(
        uint256 rewardstoWithdraw,
        bool reinvestRemainigRewards
    )
        internal
        virtual
        returns (uint256 withdrawn)
    {
        return _unwindRewards(rewardstoWithdraw, reinvestRemainigRewards);
    }

    function totalInvestedValue() public view virtual returns (uint256) {
        return _totalInvestedValue();
    }

    function accruedRewardValue() public view virtual returns (uint256) {
        return _accruedRewardValue();
    }

    function totalInvestedBaseAsset() public view virtual returns (uint256 investedAmount) {
        return _totalInvestedBaseAsset();
    }

    function convertUsdcToBaseAsset(uint256 usdcAmount) public view virtual returns (uint256) {
        return _convertUsdcToBaseAsset(usdcAmount);
    }

    function estimateAmountOut(
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
        _estimateAmountOut(tokenIn, tokenOut, amountIn, pool, secondsAgo);
    }
}
