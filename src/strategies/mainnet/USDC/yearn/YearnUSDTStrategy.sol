// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { CURVE_3POOL_POOL_MAINNET, USDT_MAINNET } from "src/helpers/AddressBook.sol";
import { ICurveTriPool } from "src/interfaces/ICurve.sol";
import {
    BaseYearnV2Strategy,
    IERC20Metadata,
    IMaxApyVault,
    IYVault,
    Math,
    SafeTransferLib
} from "src/strategies/base/BaseYearnV2Strategy.sol";

/// @title YearnUSDTStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/strategies.sol
/// @notice `YearnUSDTStrategy` supplies an underlying token into a generic Yearn Vault,
/// earning the Yearn Vault's yield
contract YearnUSDTStrategy is BaseYearnV2Strategy {
    using SafeTransferLib for address;

    ////////////////////////////////////////////////////////////////
    ///                        CONSTANTS                         ///
    ////////////////////////////////////////////////////////////////
    ICurveTriPool public constant triPool = ICurveTriPool(CURVE_3POOL_POOL_MAINNET);
    address constant usdt = USDT_MAINNET;

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
        underlyingVault = _yVault;

        /// Approve Yearn Vault to transfer underlying
        usdt.safeApprove(address(_yVault), type(uint256).max);
        underlyingAsset.safeApprove(address(triPool), type(uint256).max);
        usdt.safeApprove(address(triPool), type(uint256).max);

        /// Mininmum single trade is 0.01 token units
        minSingleTrade = 10 ** IERC20Metadata(underlyingAsset).decimals() / 100;

        /// Max single trade is 1M USD
        maxSingleTrade = 1_000_000 * 10 ** 6;
    }

    ////////////////////////////////////////////////////////////////
    ///                    VIEW FUNCTIONS                        ///
    ////////////////////////////////////////////////////////////////

    /// @notice This function is meant to be called from the vault
    /// @dev calculates the estimated real output of a withdrawal(including losses) for a @param requestedAmount
    /// for the vault to be able to provide an accurate amount when calling `previewRedeem`
    /// @return liquidatedAmount output in assets
    function previewLiquidate(uint256 requestedAmount) public view override returns (uint256 liquidatedAmount) {
        return super.previewLiquidate(requestedAmount) * 99 / 100;
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

        uint256 balanceBefore = usdt.balanceOf(address(this));

        amount = Math.min(amount, maxSingleTrade);

        assembly {
            // Emit the `Invested` event
            mstore(0x00, amount)
            log2(0x00, 0x20, _INVESTED_EVENT_SIGNATURE, address())
        }

        // Swap underlying to USDT
        triPool.exchange(1, 2, amount, 1);

        amount = usdt.balanceOf(address(this)) - balanceBefore;

        uint256 shares = underlyingVault.deposit(amount);

        assembly ("memory-safe") {
            // if (shares < minOutputAfterInvestment)
            if lt(shares, minOutputAfterInvestment) {
                // throw the `MinOutputAmountNotReached` error
                mstore(0x00, 0xf7c67a48)
                revert(0x1c, 0x04)
            }
        }

        depositedAmount = _shareValue(shares);
    }

    /// @notice Divests amount `shares` from Yearn Vault
    /// Note that divesting from Yearn could potentially cause loss (set to 0.01% as default in
    /// the Vault implementation), so the divested amount might actually be different from
    /// the requested `shares` to divest
    /// @dev care should be taken, as the `shares` parameter is *not* in terms of underlying,
    /// but in terms of underlyingVault shares
    /// @return withdrawn the total amount divested, in terms of underlying asset
    function _divest(uint256 shares) internal override returns (uint256 withdrawn) {
        // return uint256 withdrawn = underlyingVault.withdraw(shares);
        assembly {
            // store selector and parameters in memory
            mstore(0x00, 0x2e1a7d4d)
            mstore(0x20, shares)
            // call underlyingVault.withdraw(shares)
            if iszero(call(gas(), sload(underlyingVault.slot), 0, 0x1c, 0x24, 0x00, 0x20)) { revert(0x00, 0x04) }
            withdrawn := mload(0x00)
        }
        uint256 balanceBefore = underlyingAsset.balanceOf(address(this));

        // Swap USDT to underlying
        triPool.exchange(2, 1, withdrawn, 0);

        withdrawn = underlyingAsset.balanceOf(address(this)) - balanceBefore;

        assembly {
            // Emit the `Divested` event
            mstore(0x00, shares)
            mstore(0x20, withdrawn)
            log2(0x00, 0x40, _DIVESTED_EVENT_SIGNATURE, address())
        }
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL VIEW FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////

    /// @notice Determines the current value of `shares`.
    /// @dev if sqrt(underlyingVault.totalAssets()) >>> 1e39, this could potentially revert
    /// @return returns the estimated amount of underlying computed from shares `shares`
    function _shareValue(uint256 shares) internal view override returns (uint256) {
        uint256 sharesValue = super._shareValue(shares);
        if (sharesValue > 0) {
            return triPool.get_dy(2, 1, sharesValue);
        }
    }

    /// @notice Determines how many shares depositor of `amount` of underlying would receive.
    /// @return shares returns the estimated amount of shares computed in exchange for the underlying `amount`
    function _sharesForAmount(uint256 amount) internal view override returns (uint256 shares) {
        if (amount > 0) {
            amount = triPool.get_dy(1, 2, amount);
        }
        return super._sharesForAmount(amount);
    }

    /// @notice This function is meant to be called from the vault
    /// @dev calculates the estimated @param requestedAmount the vault has to request to this strategy
    /// in order to actually get @param liquidatedAmount assets when calling `previewWithdraw`
    /// @return requestedAmount
    function previewLiquidateExact(uint256 liquidatedAmount)
        public
        view
        virtual
        override
        returns (uint256 requestedAmount)
    {
        // we cannot predict losses so return as if there were not
        // increase 1% to be pessimistic
        return previewLiquidate(liquidatedAmount) * 102 / 100;
    }
}
