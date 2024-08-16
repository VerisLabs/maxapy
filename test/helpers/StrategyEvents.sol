// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { BaseStrategyEvents } from "./BaseStrategyEvents.sol";

contract StrategyEvents is BaseStrategyEvents {
    /// @notice Emitted when underlying asset is deposited into the Yearn Vault
    event Invested(address indexed strategy, uint256 amountInvested);

    /// @notice Emitted when the `requestedShares` are divested from the Yearn Vault
    event Divested(address indexed strategy, uint256 requestedShares, uint256 amountDivested);

    /// @notice Emitted when the strategy's max single trade value is updated
    event MaxSingleTradeUpdated(uint256 maxSingleTrade);

    /// @notice Emitted when the strategy's min single trade value is updated
    event MinSingleTradeUpdated(uint256 minSingleTrade);

    /// @notice Emitted after a strategy reports to the vault
    event StrategyReported(
        address indexed strategy,
        uint256 unrealizGain,
        uint256 loss,
        uint256 debtPayment,
        uint128 strategyTotalRealizedGain,
        uint128 strategyTotalLoss,
        uint128 strategyTotalDebt,
        uint256 credit,
        uint16 strategyDebtRatio
    );

    /// @notice Emitted when a strategy is exited
    event StrategyExited(address indexed strategy, uint256 withdrawn);

    /// @notice Emitted when the strategy is harvested
    event Harvested(uint256 profit, uint256 loss, uint256 debtPayment, uint256 debtOutstanding);

    /// @notice Emitted after a forced harvest fails unexpectedly
    event ForceHarvestFailed(address indexed strategy, bytes reason);
}
