// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { SafeTransferLib, YearnWETHStrategy } from "src/strategies/mainnet/WETH/yearn/YearnWETHStrategy.sol";

contract YearnWETHStrategyWrapper is YearnWETHStrategy {
    using SafeTransferLib for address;

    function investYearn(uint256 amount) external returns (uint256) {
        return yVault.deposit(amount);
    }

    function triggerLoss(uint256 amount) external {
        underlyingAsset.safeTransfer(address(underlyingAsset), amount);
    }

    function mockReport(uint128 gain, uint128 loss, uint128 debtPayment, address treasury) external {
        vault.report(gain, loss, debtPayment, treasury);
    }

    function prepareReturn(
        uint256 debtOutstanding,
        uint256 minExpectedBalance
    )
        external
        returns (uint256 unrealizedProfit, uint256 loss, uint256 debtPayment)
    {
        (unrealizedProfit, loss, debtPayment) = _prepareReturn(debtOutstanding, minExpectedBalance);
    }

    function adjustPosition() external {
        _adjustPosition(0, 0);
        ///silence warning
    }

    function invest(uint256 amount, uint256 minOutputAfterInvestment) external returns (uint256) {
        return _invest(amount, minOutputAfterInvestment);
    }

    function divest(uint256 shares) external returns (uint256) {
        return _divest(shares);
    }

    function liquidatePosition(uint256 amountNeeded) external returns (uint256, uint256) {
        return _liquidatePosition(amountNeeded);
    }

    function liquidateAllPositions() external returns (uint256) {
        return _liquidateAllPositions();
    }

    function shareValue(uint256 shares) external view returns (uint256) {
        return _shareValue(shares);
    }

    function sharesForAmount(uint256 amount) external view returns (uint256) {
        return _sharesForAmount(amount);
    }

    function freeFunds() external view returns (uint256) {
        return _freeFunds();
    }

    function calculateLockedProfit() external view returns (uint256) {
        return _calculateLockedProfit();
    }

    function shareBalance() external view returns (uint256) {
        return _shareBalance();
    }
}
