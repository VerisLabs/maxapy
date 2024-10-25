// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {
    IERC20Metadata,
    IYVault,
    BaseYearnV2Strategy,
    IMaxApyVault,
    SafeTransferLib,
    Math
} from "src/strategies/base/BaseYearnV2Strategy.sol";
import { CURVE_3POOL_POOL_MAINNET, DAI_MAINNET } from "src/helpers/AddressBook.sol";
import { ICurveLpPool } from "src/interfaces/ICurve.sol";

/// @title YearnDAIStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/strategies.sol
/// @notice `YearnDAIStrategy` supplies an underlying token into a generic Yearn Vault,
/// earning the Yearn Vault's yield
contract YearnDAIStrategy is BaseYearnV2Strategy {
    using SafeTransferLib for address;

    ////////////////////////////////////////////////////////////////
    ///                        CONSTANTS                         ///
    ////////////////////////////////////////////////////////////////
    ICurveLpPool public constant triPool = ICurveLpPool(CURVE_3POOL_POOL_MAINNET);
    address constant dai = DAI_MAINNET;

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
        underlyingAsset.safeApprove(address(triPool), type(uint256).max);
        dai.safeApprove(address(triPool), type(uint256).max);

        /// Mininmum single trade is 0.01 token units
        minSingleTrade = 10 ** IERC20Metadata(underlyingAsset).decimals() / 100;

        /// Unlimited max single trade by default
        maxSingleTrade = 1_000_000 ether; // 1M DAI
    }

    /// @notice Invests `amount` of underlying, depositing it in the Yearn Vault
    /// @param amount The amount of underlying to be deposited in the vault
    /// @param minOutputAfterInvestment minimum expected output after `_invest()` (designated in Yearn receipt tokens)
    /// @return depositedAmount The amount of shares received, in terms of underlying
    function _invest(
        uint256 amount,
        uint256 minOutputAfterInvestment
    )
        internal
        override
        returns (uint256 depositedAmount)
    {
        // Don't do anything if amount to invest is 0
        if (amount == 0) return 0;

        uint256 underlyingBalance = _underlyingBalance();
        if (amount > underlyingBalance) revert NotEnoughFundsToInvest();

        uint256 adjustedMaxSingleTrade = maxSingleTrade / 1e12;

        uint256 balanceBefore = dai.balanceOf(address(this));

        amount = Math.min(maxSingleTrade, adjustedMaxSingleTrade);

        // Swap underlying to DAI
        triPool.exchange(1, 0, amount, 0);

        amount = dai.balanceOf(address(this)) - balanceBefore;

        uint256 shares = yVault.deposit(amount);

        assembly ("memory-safe") {
            // if (shares < minOutputAfterInvestment)
            if lt(shares, minOutputAfterInvestment) {
                // throw the `MinOutputAmountNotReached` error
                mstore(0x00, 0xf7c67a48)
                revert(0x1c, 0x04)
            }
        }

        depositedAmount = _shareValue(shares);

        assembly {
            // Emit the `Invested` event
            mstore(0x00, amount)
            log2(0x00, 0x20, _INVESTED_EVENT_SIGNATURE, address())
        }
    }

    /// @notice Divests amount `shares` from Yearn Vault
    /// Note that divesting from Yearn could potentially cause loss (set to 0.01% as default in
    /// the Vault implementation), so the divested amount might actually be different from
    /// the requested `shares` to divest
    /// @dev care should be taken, as the `shares` parameter is *not* in terms of underlying,
    /// but in terms of yvault shares
    /// @return withdrawn the total amount divested, in terms of underlying asset
    function _divest(uint256 shares) internal override returns (uint256 withdrawn) {
        // return uint256 withdrawn = yVault.withdraw(shares);
        assembly {
            // store selector and parameters in memory
            mstore(0x00, 0x2e1a7d4d)
            mstore(0x20, shares)
            // call yVault.withdraw(shares)
            if iszero(call(gas(), sload(yVault.slot), 0, 0x1c, 0x24, 0x00, 0x20)) { revert(0x00, 0x04) }
            withdrawn := mload(0x00)
        }
        uint256 balanceBefore = underlyingAsset.balanceOf(address(this));

        // Swap DAI to underlying
        triPool.exchange(0, 1, withdrawn, 0);

        withdrawn = underlyingAsset.balanceOf(address(this)) - balanceBefore;

        assembly {
            // Emit the `Divested` event
            mstore(0x00, shares)
            mstore(0x20, withdrawn)
            log2(0x00, 0x40, _DIVESTED_EVENT_SIGNATURE, address())
        }
    }
}
