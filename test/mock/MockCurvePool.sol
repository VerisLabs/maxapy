// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

contract MockCurvePool {
    function coins(uint256 index) external view returns (address) {
        index;
        return address(this);
    }
}
