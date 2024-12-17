// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {
    BaseYearnV3Strategy, IMaxApyVault, IYVaultV3, SafeTransferLib
} from "src/strategies/base/BaseYearnV3Strategy.sol";

contract BaseYearnV3StrategyWrapper is BaseYearnV3Strategy {
    using SafeTransferLib for address;

    function initialize(
        IMaxApyVault _vault,
        address[] calldata _keepers,
        bytes32 _strategyName,
        address _strategist,
        IYVaultV3 _yVault
    )
        public
        virtual
        override
        initializer
    {
        __BaseStrategy_init(_vault, _keepers, _strategyName, _strategist);
        underlyingVault = _yVault;

        underlyingAsset.safeApprove(address(underlyingVault), type(uint256).max);

        /// Unlimited max single trade by default
        maxSingleTrade = type(uint256).max;
    }

    function investYearn(uint256 amount) external returns (uint256) {
        return underlyingVault.deposit(amount, address(this));
    }

    function triggerLoss(uint256 amount) external {
        uint256 amountToWithdraw = _sub0(amount, underlyingAsset.balanceOf(address(this)));
        if (amountToWithdraw > 0) {
            uint256 shares = underlyingVault.previewRedeem(amountToWithdraw);
            underlyingVault.redeem(shares, address(this), address(this));
        }
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

    function shareBalance() external view returns (uint256) {
        return _shareBalance();
    }
}
