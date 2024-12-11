// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { IStrategy } from "../../src/interfaces/IStrategy.sol";

interface IStrategyWrapper is IStrategy {
    function prepareReturn(
        uint256 debtOutstanding,
        uint256 minExpectedBalance
    )
        external
        returns (uint256 unrealizedProfit, uint256 loss, uint256 debtPayment);

    function adjustPosition() external;

    function invest(uint256 amount, uint256 minOutput) external returns (uint256);

    function divest(uint256 shares) external returns (uint256);

    function liquidatePosition(uint256 amountNeeded) external returns (uint256, uint256);

    function liquidateAllPositions() external returns (uint256);

    function shareValue(uint256 shares) external view returns (uint256);

    function sharesForAmount(uint256 amount) external view returns (uint256);

    function freeFunds() external view returns (uint256);

    function calculateLockedProfit() external view returns (uint256);

    function shareBalance() external view returns (uint256);

    function mockReport(uint128 gain, uint128 loss, uint128 debtPayment, address treasury) external;

    function investYearn(uint256 amount) external returns (uint256);

    function investSommelier(uint256 amount) external;

    function triggerLoss(uint256 amount) external;

    function owner() external view returns (address);

    function router() external view returns (address);

    function convexRewardPool() external view returns (address);

    function convexLpToken() external view returns (address);

    function rewardToken() external view returns (address);

    function convexBooster() external view returns (address);

    function curveLpPool() external view returns (address);

    function curveTriPool() external view returns (address);

    function curveEthFrxEthPool() external view returns (address);

    function curveUsdcCrvUsdPool() external view returns (address);

    function curveLendingPool() external view returns (address);

    function cvxWethPool() external view returns (address);

    function cellar() external view returns (address);

    function minSwapCrv() external view returns (uint256);

    function minSwapCvx() external view returns (uint256);

    function setMinSwapCrv(uint256) external;

    function setMinSwapCvx(uint256) external;

    function setRouter(address) external;

    function lpForAmount(uint256) external view returns (uint256);

    function unwindRewards() external;

    function previewLiquidate(uint256) external view returns (uint256);

    function lastHarvest() external view returns (uint256);

    function estimatedTotalAssets() external view returns (uint256);

    function lastEstimatedTotalAssets() external view returns (uint256);

    function setAutopilot(bool) external;

    function unharvestedAmount() external view returns (int256);

    function uniProxy() external view returns (address);

    function hopPool() external view returns (address);
}
