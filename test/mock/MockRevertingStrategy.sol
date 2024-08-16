// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";

contract MockRevertingStrategy {
    error HarvestFailed();

    IMaxApyVault public immutable vault;
    address public immutable underlyingAsset;

    uint256 public emergencyExit;

    address public strategist;

    constructor(address _vault, address _underlyingAsset) {
        vault = IMaxApyVault(_vault);
        underlyingAsset = _underlyingAsset;
        strategist = msg.sender;
    }

    function setEmergencyExit(uint256 _emergencyExit) external {
        emergencyExit = _emergencyExit;
    }

    function setStrategist(address _newStrategist) external {
        strategist = _newStrategist;
    }

    function harvest(
        uint256 minExpectedBalance,
        uint256 minOutputAfterInvestment,
        address harvester,
        uint256 deadline
    )
        external
        pure
    {
        minExpectedBalance;
        minOutputAfterInvestment;
        harvester;
        deadline;
        revert HarvestFailed();
    }

    function setAutopilot(bool _autoPilot) external {
        IMaxApyVault(vault).setAutoPilot(_autoPilot);
    }

    function estimatedTotalAssets() external view returns (uint256) {
        return 0;
    }
}
