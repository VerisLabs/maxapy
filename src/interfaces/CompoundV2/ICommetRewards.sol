// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

struct RewardOwed {
    address token;
    uint256 owed;
}

interface ICommetRewards {
    function getRewardOwed(address comet, address account) external returns (RewardOwed memory);
    function claim(address comet, address src, bool shouldAccrue) external;
}
