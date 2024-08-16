// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { BaseStrategyEvents } from "./BaseStrategyEvents.sol";

contract ConvexdETHFrxETHStrategyEvents is BaseStrategyEvents {
    /// @notice Emitted when underlying asset is deposited into Convex
    event Invested(address indexed strategy, uint256 amountInvested);

    /// @notice Emitted when the `requestedShares` are divested from Convex
    event Divested(address indexed strategy, uint256 amountDivested);

    /// @notice Emitted when the strategy's max single trade value is updated
    event MaxSingleTradeUpdated(uint256 maxSingleTrade);

    /// @notice Emitted when the strategy's min single trade value is updated
    event MinSingleTradeUpdated(uint256 minSingleTrade);

    /// @notice Emitted when the router's address is updated
    event RouterUpdated(address router);

    /// @notice Emitted after a strategy reports to the vault
    event StrategyReported(
        address indexed strategy,
        uint256 unrealizedGain,
        uint256 loss,
        uint256 debtPayment,
        uint128 strategyTotalGain,
        uint128 strategyTotalLoss,
        uint128 strategyTotalDebt,
        uint256 credit,
        uint16 strategyDebtRatio
    );

    /// @notice Emitted when the strategy is harvested
    event Harvested(uint256 profit, uint256 loss, uint256 debtPayment, uint256 debtOutstanding);

    /// @notice Emitted when the min swap for crv token is updated
    event MinSwapCrvUpdated(uint256 newMinSwapCrv);

    /// @notice Emitted when the min swap for cvx token is updated
    event MinSwapCvxUpdated(uint256 newMinSwapCvx);
}
