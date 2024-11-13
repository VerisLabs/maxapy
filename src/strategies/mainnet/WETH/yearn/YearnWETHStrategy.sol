// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {
    BaseYearnV2Strategy,
    IERC20Metadata,
    IMaxApyVault,
    IYVault,
    SafeTransferLib
} from "src/strategies/base/BaseYearnV2Strategy.sol";

/// @title YearnWETHStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/strategies.sol
/// @notice `YearnWETHStrategy` supplies an underlying token into a generic Yearn Vault,
/// earning the Yearn Vault's yield
contract YearnWETHStrategy is BaseYearnV2Strategy {
    using SafeTransferLib for address;

    /// @notice Initialize the Strategy
    /// @param _vault The address of the MaxApy Vault associated to the strategy
    /// @param _keepers The addresses of the keepers to be added as valid keepers to the strategy
    /// @param _strategyName the name of the strategy
    /// @param _yVault The Yearn Finance vault this strategy will interact with
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

        /// Approve Yearn Vault to transfer underlying
        underlyingAsset.safeApprove(address(_yVault), type(uint256).max);

        /// Mininmum single trade is 0.01 token units
        minSingleTrade = 10 ** IERC20Metadata(underlyingAsset).decimals() / 100;

        /// Unlimited max single trade by default
        maxSingleTrade = type(uint256).max;
    }
}
