// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { IYVaultV3 } from "src/interfaces/IYVaultV3.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { BaseYearnV3Strategy, IMaxApyVault, SafeTransferLib } from "src/strategies/base/BaseYearnV3Strategy.sol";
import { ICurveAtriCryptoZapper } from "src/interfaces/ICurve.sol";
import { DAI_POLYGON, CURVE_AAVE_ATRICRYPTO_ZAPPER_POLYGON } from "src/helpers/AddressBook.sol";

/// @title YearnDAIStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/strategies.sol
/// @notice `YearnDAIStrategy` supplies an underlying token into a generic Yearn Vault,
/// earning the Yearn Vault's yield
contract YearnDAIStrategy is BaseYearnV3Strategy {
    using SafeTransferLib for address;

    ICurveAtriCryptoZapper constant zapper = ICurveAtriCryptoZapper(CURVE_AAVE_ATRICRYPTO_ZAPPER_POLYGON);

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
        DAI_POLYGON.safeApprove(address(zapper), type(uint256).max);
        DAI_POLYGON.safeApprove(address(_yVault), type(uint256).max);
        underlyingAsset.safeApprove(address(zapper), type(uint256).max);

        minSingleTrade = 1 * 10 ** 6; // 1 USD
        maxSingleTrade = 100_000 * 10 ** 6; // 100,000 USD
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL CORE FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////

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

        // Check max deposit just in case
        uint256 maxDeposit = yVault.maxDeposit(address(this));
        amount = Math.min(Math.min(amount, maxDeposit), maxSingleTrade);

        uint256 balanceBefore = DAI_POLYGON.balanceOf(address(this));
        // Swap the USDCe to base asset
        zapper.exchange_underlying(1, 0, amount, 0, address(this));

        // Deposit into the underlying vault
        amount = DAI_POLYGON.balanceOf(address(this)) - balanceBefore;
        uint256 shares = yVault.deposit(amount, address(this));

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
        withdrawn = yVault.redeem(shares, address(this), address(this));
        uint256 balanceBefore = underlyingAsset.balanceOf(address(this));
        // Swap base asset to USDCe
        zapper.exchange_underlying(0, 1, withdrawn, 0, address(this));
        withdrawn = underlyingAsset.balanceOf(address(this)) - balanceBefore;
        emit Divested(address(this), shares, withdrawn);
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL VIEW FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////

    /// @notice Determines the current value of `shares`.
    /// @return _assets the estimated amount of underlying computed from shares `shares`
    function _shareValue(uint256 shares) internal view override returns (uint256 _assets) {
        _assets = super._shareValue(shares);
        return zapper.get_dy_underlying(0, 1, _assets);
    }

    /// @notice Determines how many shares depositor of `amount` of underlying would receive.
    /// @return _shares the estimated amount of shares computed in exchange for underlying `amount`
    function _sharesForAmount(uint256 amount) internal view override returns (uint256 _shares) {
        amount = zapper.get_dy_underlying(1, 0, amount);
        return super._sharesForAmount(amount);
    }
}
