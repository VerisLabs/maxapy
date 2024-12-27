// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {
    BeefyCrvUSDUSDCeStrategy, SafeTransferLib
} from "src/strategies/polygon/USDCe/beefy/BeefyCrvUSDUSDCeStrategy.sol";

contract BeefyCrvUSDUSDCeStrategyWrapper is BeefyCrvUSDUSDCeStrategy {
    using SafeTransferLib for address;

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

    function shareBalance() external view returns (uint256) {
        return _shareBalance();
    }

    function lpPrice() external view returns (uint256) {
        return _lpPrice();
    }
}
