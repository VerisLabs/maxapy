// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

interface IStakingRewardsMulti {
    function stake(uint256 _amount) external;

    function withdraw(uint256 _amount) external;

    function getReward() external;

    function balanceOf(address) external view returns (uint256);

    function earned(address) external view returns (uint256);

    function earned(address _account, address _rewardsToken) external view returns (uint256 pending);
}
