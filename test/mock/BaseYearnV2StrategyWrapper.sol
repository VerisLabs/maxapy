// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import {
    BaseYearnV2Strategy,
    IERC20Metadata,
    IMaxApyVault,
    IYVault,
    SafeTransferLib
} from "src/strategies/base/BaseYearnV2Strategy.sol";

contract BaseYearnV2StrategyWrapper is BaseYearnV2Strategy {
    using SafeTransferLib for address;

    function initialize(
        IMaxApyVault _vault,
        address[] calldata _keepers,
        bytes32 _strategyName,
        address _strategist,
        IYVault _yVault
    )
        public
        virtual
        override
        initializer
    {
        __BaseStrategy_init(_vault, _keepers, _strategyName, _strategist);
        yVault = _yVault;

        underlyingAsset.safeApprove(address(yVault), type(uint256).max);

        /// Mininmum single trade is 0.01 token units
        minSingleTrade = 10 ** IERC20Metadata(underlyingAsset).decimals() / 100;

        /// Unlimited max single trade by default
        maxSingleTrade = type(uint256).max;
    }

    function investYearn(uint256 amount) external returns (uint256) {
        return yVault.deposit(amount);
    }

    function triggerLoss(uint256 amount) external {
        uint256 amountToWithdraw = _sub0(amount, underlyingAsset.balanceOf(address(this)));
        if (amountToWithdraw > 0) {
            uint256 shares = Math.min(yVault.balanceOf(address(this)), _sharesForAmount(amountToWithdraw));
            yVault.withdraw(shares);
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
