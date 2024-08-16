// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import "openzeppelin/interfaces/IERC4626.sol";

interface ICellar is IERC4626 {
    function totalAssetsWithdrawable() external view returns (uint256 assets);

    function userShareLockStartTime(address) external view returns (uint256);

    function shareLockPeriod() external view returns (uint256);

    function isShutdown() external view returns (bool);

    function isPaused() external view returns (bool);
}
