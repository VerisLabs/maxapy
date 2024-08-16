// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

contract MockConvexBooster {
    function poolInfo(uint256 pid)
        external
        pure
        returns (address _lptoken, address _token, address _gauge, address _crvRewards, address _stash, bool _shutdown)
    {
        pid;
        _lptoken;
        _token;
        _gauge;
        _crvRewards;
        _stash;
        _shutdown = true;
    }
}
