// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {
    IYVaultV3, BaseYearnV3Strategy, IMaxApyVault, SafeTransferLib
} from "src/strategies/base/BaseYearnV3Strategy.sol";

/// @title YearnV3WETHStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/strategies.sol
/// @notice `YearnV3WETHStrategy` supplies an underlying token into a generic Yearn Vault,
/// earning the Yearn Vault's yield
contract YearnV3WETHStrategy is BaseYearnV3Strategy {
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
        IYVaultV3 _yVault
    )
        public
        virtual
        override
        initializer
    {
        __BaseStrategy_init(_vault, _keepers, _strategyName, _strategist);
        yVault = _yVault;

        /// Perform needed approvals
        underlyingAsset.safeApprove(address(_yVault), type(uint256).max);

        /// Unlimited max single trade by default
        maxSingleTrade = type(uint256).max;
    }
}
