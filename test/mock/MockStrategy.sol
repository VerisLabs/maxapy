// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

contract MockStrategy {
    address public immutable vault;
    address public immutable underlyingAsset;

    uint256 public emergencyExit;

    address public strategist;

    constructor(address _vault, address _underlyingAsset) {
        vault = _vault;
        underlyingAsset = _underlyingAsset;
        strategist = msg.sender;
    }

    function setEmergencyExit(uint256 _emergencyExit) external {
        emergencyExit = _emergencyExit;
    }

    function setStrategist(address _newStrategist) external {
        strategist = _newStrategist;
    }
}
