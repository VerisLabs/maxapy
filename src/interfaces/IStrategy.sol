// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { StrategyData } from "../helpers/VaultTypes.sol";

interface IStrategy {
    function ADMIN_ROLE() external view returns (uint256);

    function EMERGENCY_ADMIN_ROLE() external view returns (uint256);

    function VAULT_ROLE() external view returns (uint256);

    function KEEPER_ROLE() external view returns (uint256);

    /// Roles
    function grantRoles(address user, uint256 roles) external payable;

    function revokeRoles(address user, uint256 roles) external payable;

    function renounceRoles(uint256 roles) external payable;

    function harvest(
        uint256 minExpectedBalance,
        uint256 minOutputAfterInvestment,
        address harvester,
        uint256 deadline
    )
        external;

    function setEmergencyExit(uint256 _emergencyExit) external;

    function setStrategist(address _newStrategist) external;

    function vault() external returns (address);

    function underlyingAsset() external returns (address);

    function emergencyExit() external returns (uint256);

    function liquidate(uint256 amountNeeded) external returns (uint256);

    function liquidateExact(uint256 amountNeeded) external returns (uint256);

    function delegatedAssets() external view returns (uint256);

    function estimatedTotalAssets() external view returns (uint256);

    function lastEstimatedTotalAssets() external view returns (uint256);

    function strategist() external view returns (address);

    function strategyName() external view returns (bytes32);

    function isActive() external view returns (bool);

    /// View roles
    function hasAnyRole(address user, uint256 roles) external view returns (bool result);

    function hasAllRoles(address user, uint256 roles) external view returns (bool result);

    function rolesOf(address user) external view returns (uint256 roles);

    function rolesFromOrdinals(uint8[] memory ordinals) external pure returns (uint256 roles);

    function ordinalsFromRoles(uint256 roles) external pure returns (uint8[] memory ordinals);

    function previewLiquidate(uint256) external view returns (uint256);

    function previewLiquidateExact(uint256) external view returns (uint256);

    function maxLiquidate() external view returns (uint256);

    function maxLiquidateExact() external view returns (uint256);

    function maxSingleTrade() external view returns (uint256);

    function minSingleTrade() external view returns (uint256);

    function yVault() external view returns (address);

    function setMaxSingleTrade(uint256) external;

    function setMinSingleTrade(uint256) external;
}
