// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

contract MaxApyVaultEvents {
    uint256 public constant MAXIMUM_STRATEGIES = 20;

    /// @notice Emitted when a strategy is newly added to the protocol
    event StrategyAdded(
        address indexed newStrategy,
        uint16 strategyDebtRatio,
        uint128 strategyMaxDebtPerHarvest,
        uint128 strategyMinDebtPerHarvest,
        uint16 strategyPerformanceFee
    );
    /// @notice Emitted when a vault's emergency shutdown state is switched
    event EmergencyShutdownUpdated(bool emergencyShutdown);

    /// @notice Emitted when a strategy is revoked from the vault
    event StrategyRevoked(address indexed strategy);

    /// @notice Emitted when a strategy parameters are updated
    event StrategyUpdated(
        address indexed strategy,
        uint16 newDebtRatio,
        uint128 newMaxDebtPerHarvest,
        uint128 newMinDebtPerHarvest,
        uint16 newPerformanceFee
    );

    /// @notice Emitted when the withdrawal queue is updated
    event WithdrawalQueueUpdated(address[MAXIMUM_STRATEGIES] withdrawalQueue);

    /// @notice Emitted when the vault's performance fee is updated
    event PerformanceFeeUpdated(uint16 newPerformanceFee);

    /// @notice Emitted when the vault's management fee is updated
    event ManagementFeeUpdated(uint256 newManagementFee);

    /// @notice Emitted the vault's locked profit degradation is updated
    event LockedProfitDegradationUpdated(uint256 newLockedProfitDegradation);

    /// @notice Emitted when the vault's deposit limit is updated
    event DepositLimitUpdated(uint256 newDepositLimit);

    /// @notice Emitted when the vault's treasury addresss is updated
    event TreasuryUpdated(address treasury);

    /// @notice Emitted on vault deposits
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    /// @notice Emitted on vault withdrawals
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    /// @notice Emitted on withdrawal strategy withdrawals
    event WithdrawFromStrategy(address indexed strategy, uint128 strategyTotalDebt, uint128 loss);
    /// @notice Emitted after assessing protocol fees
    event FeesReported(uint256 managementFee, uint16 performanceFee, uint256 strategistFee, uint256 duration);
    /// @notice Emitted after a strategy reports to the vault
    event StrategyReported(
        address indexed strategy,
        uint256 unrealizedGain,
        uint256 loss,
        uint256 debtPayment,
        uint128 strategyTotalRealizedGain,
        uint128 strategyTotalLoss,
        uint128 strategyTotalDebt,
        uint256 credit,
        uint16 strategyDebtRatio
    );

    /// @notice Emitted when a vault's autopilot mode is enabled or disabled
    event AutopilotEnabled(bool isEnabled);

    /// OWNERSHIP

    /// @notice The ownership is transferred from `oldOwner` to `newOwner`.
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    /// @notice An ownership handover to `pendingOwner` has been requested.
    event OwnershipHandoverRequested(address indexed pendingOwner);

    /// @dev The ownership handover to `pendingOwner` has been canceled.
    event OwnershipHandoverCanceled(address indexed pendingOwner);

    /// ROLES
    event RolesUpdated(address indexed user, uint256 indexed roles);
}
