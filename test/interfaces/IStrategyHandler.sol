// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

interface IStrategyHandler {
    function harvest() external;

    function gain(uint256 amount) external;

    function triggerLoss(uint256 amount, bool useLiquidateExact) external;

    function getEntryPoints() external view returns (bytes4[] memory);

    function expectedEstimatedTotalAssets() external view returns (uint256);

    function actualEstimatedTotalAssets() external view returns (uint256);

    function callSummary() external view;

    function INVARIANT_A_ESTIMATED_TOTAL_ASSETS() external;
}
