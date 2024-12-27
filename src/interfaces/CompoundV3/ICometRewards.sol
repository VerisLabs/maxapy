// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

struct RewardOwed {
    address token;
    uint256 owed;
}

struct RewardConfig {
    address token;
    uint64 rescaleFactor;
    bool shouldUpscale;
}

interface ICometRewards {
    function getRewardOwed(address comet, address account) external returns (RewardOwed memory);

    function claim(address comet, address src, bool shouldAccrue) external;

    function rewardConfig(address comet)
        external
        view
        returns (address token, uint64 rescaleFactor, bool shouldUpscale);

    function rewardsClaimed(address comet, address account) external view returns (uint256);
}
