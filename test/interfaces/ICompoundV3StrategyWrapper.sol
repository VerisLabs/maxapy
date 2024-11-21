// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { IStrategy } from "../../src/interfaces/IStrategy.sol";

interface ICompoundV3StrategyWrapper is IStrategy {
    function prepareReturn(
        uint256 debtOutstanding,
        uint256 minExpectedBalance
    )
        external
        returns (uint256 unrealizedProfit, uint256 loss, uint256 debtPayment);

    function adjustPosition() external;

    function invest(uint256 amount, uint256 minOutput) external returns (uint256);

    function divest(
        uint256 amount,
        uint256 rewardstoWithdraw,
        bool reinvestRemainingRewards
    )
        external
        returns (uint256);

    function liquidatePosition(uint256 amountNeeded) external returns (uint256, uint256);

    function liquidateAllPositions() external returns (uint256);

    function calculateLockedProfit() external view returns (uint256);

    function shareBalance() external view returns (uint256);

    function mockReport(uint128 gain, uint128 loss, uint128 debtPayment, address treasury) external;

    function triggerLoss(uint256 amount) external;

    function owner() external view returns (address);

    function router() external view returns (address);

    function setMinSwapCrv(uint256) external;

    function setMinSwapCvx(uint256) external;

    function setRouter(address) external;

    function unwindRewards() external;

    function previewLiquidate(uint256) external view returns (uint256);

    function lastHarvest() external view returns (uint256);

    function estimatedTotalAssets() external view returns (uint256);

    function lastEstimatedTotalAssets() external view returns (uint256);

    function setAutopilot(bool) external;

    function unharvestedAmount() external view returns (int256);

    function cometRewards() external view returns (address);

    function convertUsdcToBaseAsset(uint256) external view returns (uint256);

    function accruedRewardValue() external view returns (uint256);
}
