// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { IYVaultV3, BaseYearnV3Strategy, IMaxApyVault, SafeTransferLib } from "src/strategies/base/BaseYearnV3Strategy.sol";
import { ICurveAtriCryptoZapper } from "src/interfaces/ICurve.sol";
import { DAI_POLYGON, CURVE_AAVE_ATRICRYPTO_ZAPPER_POLYGON } from "src/helpers/AddressBook.sol";

/// @title YearnDAIStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/strategies.sol
/// @notice `YearnDAIStrategy` supplies an underlying token into a generic Yearn Vault,
/// earning the Yearn Vault's yield
contract YearnDAIStrategy is BaseYearnV3Strategy {
    using SafeTransferLib for address;
    using Math for uint256;

    ////////////////////////////////////////////////////////////////
    ///                        CONSTANTS                         ///
    ////////////////////////////////////////////////////////////////
    /// @notice Curve AtriCrypto(DAI,USDCe,USDT,wBTC,WETH) pool zapper in polygon
    ICurveAtriCryptoZapper constant zapper = ICurveAtriCryptoZapper(CURVE_AAVE_ATRICRYPTO_ZAPPER_POLYGON);
    /// @notice DAI in polygon
    address public constant dai = DAI_POLYGON;

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
        dai.safeApprove(address(zapper), type(uint256).max);
        dai.safeApprove(address(_yVault), type(uint256).max);
        underlyingAsset.safeApprove(address(zapper), type(uint256).max);

        minSingleTrade = 1 * 10 ** 6; // 1 USD
        maxSingleTrade = 100_000 * 10 ** 6; // 100,000 USD
    }

    ////////////////////////////////////////////////////////////////
    ///                STRATEGY CORE LOGIC                       ///
    ////////////////////////////////////////////////////////////////
    /// @notice Withdraws exactly `amountNeeded` to `vault`.
    /// @dev This may only be called by the respective Vault.
    /// @param amountNeeded How much `underlyingAsset` to withdraw.
    /// @return loss Any realized losses
    /// NOTE : while in the {withdraw} function the vault gets `amountNeeded` - `loss`
    /// in {liquidate} the vault always gets `amountNeeded` and `loss` is the amount
    /// that had to be lost in order to withdraw exactly `amountNeeded`
    function liquidateExact(uint256 amountNeeded) external override checkRoles(VAULT_ROLE) returns (uint256 loss) {
        uint256 amountRequested = previewLiquidateExact(amountNeeded);
        uint256 amountFreed;
        // liquidate `amountRequested` in order to get exactly or more than `amountNeeded`
        (amountFreed, loss) = _liquidatePosition(amountRequested);
        // Send it directly back to vault
        if (amountFreed >= amountNeeded) underlyingAsset.safeTransfer(address(vault), amountNeeded);
        // something didn't work as expected
        // this should NEVER happen in normal conditions
        else revert();
        // Note: Reinvest anything leftover on next `harvest`
        _snapshotEstimatedTotalAssets();
    }

    /////////////////////////////////////////////////////////////////
    ///                    VIEW FUNCTIONS                        ///
    ////////////////////////////////////////////////////////////////

    /// @notice This function is meant to be called from the vault
    /// @dev calculates the estimated real output of a withdrawal(including losses) for a @param requestedAmount
    /// for the vault to be able to provide an accurate amount when calling `previewRedeem`
    /// @return liquidatedAmount output in assets
    function previewLiquidate(uint256 requestedAmount) public view override returns (uint256 liquidatedAmount) {
        uint256 loss;
        uint256 underlyingBalance = _underlyingBalance();
        // If underlying balance currently held by strategy is not enough to cover
        // the requested amount, we divest from the Cellar Vault
        if (underlyingBalance < requestedAmount) {
            uint256 amountToWithdraw;
            unchecked {
                amountToWithdraw = requestedAmount - underlyingBalance;
            }
            uint256 shares = _sharesForAmount(amountToWithdraw);
            if (shares == 0) return 0;
            uint256 withdrawn = yVault.previewRedeem(shares);
            withdrawn = zapper.get_dy_underlying(0, 1, withdrawn) * 9995 / 10_000;
            if (withdrawn < amountToWithdraw) loss = amountToWithdraw - withdrawn;
        }
        // liquidatedAmount = amountNeeded - loss;
        assembly {
            liquidatedAmount := sub(requestedAmount, loss)
        }
    }

    /// @notice This function is meant to be called from the vault
    /// @dev calculates the estimated @param requestedAmount the vault has to request to this strategy
    /// in order to actually get @param liquidatedAmount assets when calling `previewWithdraw`
    /// @return requestedAmount
    function previewLiquidateExact(uint256 liquidatedAmount) public view override returns (uint256 requestedAmount) {
        // increase 1% to be pessimistic
        return previewLiquidate(liquidatedAmount) * 101 / 100;
    }

    /// @notice Returns the max amount of assets that the strategy can withdraw after losses
    function maxLiquidate() public view override returns (uint256) {
        return _estimatedTotalAssets();
    }

    /// @notice Returns the max amount of assets that the strategy can liquidate, before realizing losses
    function maxLiquidateExact() public view override returns (uint256) {
        return previewLiquidate(estimatedTotalAssets()) * 99 / 100;
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
        
        uint256 maxDeposit = yVault.maxDeposit(address(this));

        // Scale up to 18 decimals

        uint256 scaledAmount = amount.mulWad(1e12); 

        uint256 scaledMaxSingleTrade = maxSingleTrade.mulWad(1e12); 

        uint256 minAmount = Math.min(Math.min(scaledAmount, maxDeposit), scaledMaxSingleTrade);

        // Scale back down to 6 decimals

        amount = minAmount.divWad(1e12);

        uint256 balanceBefore = dai.balanceOf(address(this));
        // Swap the USDCe to base asset
        uint256 initialAmount = amount;
        console2.log("depositedAssets: ", amount);
        zapper.exchange_underlying(1, 0, amount, 0, address(this));

        // Deposit into the underlying vault
        amount = dai.balanceOf(address(this)) - balanceBefore;

        uint256 shares = yVault.deposit(amount, address(this));
        console2.log("finalAssets: ", _shareValue(shares));
        console2.log("fulfilled percentage: ", 10_000*_shareValue(shares)/ initialAmount);

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
            mstore(0x00, depositedAmount)
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
        return super._sharesForAmount(_spotPriceDy(1, amount));
    }

    /// @notice Returns the price of token USDC<>DAI or DAI<>USDC withouth considering any slippage or fees
    /// @return _spotDy spot price times amount
    function _spotPriceDy(uint256 i, uint256 amount) internal view returns (uint256 _spotDy) {
        if (i == 0) {
            uint256 spotPrice = zapper.get_dy_underlying(0, 1, 1 ether);
            return spotPrice * amount / 1 ether;
        }

        if (i == 1) {
            uint256 spotPrice = zapper.get_dy_underlying(1, 0, 1e6);
            return spotPrice * amount / 1e6;
        }
    }
}
