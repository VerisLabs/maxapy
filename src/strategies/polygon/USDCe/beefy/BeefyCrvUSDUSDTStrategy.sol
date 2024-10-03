pragma solidity ^0.8.19;

import { BaseBeefyCurveStrategy } from "src/strategies/base/BaseBeefyCurveStrategy.sol";

import { IMaxApyVault, SafeTransferLib } from "src/strategies/base/BaseBeefyStrategy.sol";
import { ICurveLpPool } from "src/interfaces/ICurve.sol";
import { IBeefyVault } from "src/interfaces/IBeefyVault.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";

import { ICurveAtriCryptoZapper } from "src/interfaces/ICurve.sol";
import { USDT_POLYGON, CURVE_AAVE_ATRICRYPTO_ZAPPER_POLYGON } from "src/helpers/AddressBook.sol";


/// @title BeefyCrvUSDUSDTStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/strategies.sol
/// @notice `BeefyCrvUSDUSDTStrategy` supplies an underlying token into a generic Beefy Vault,
/// earning the Beefy Vault's yield
contract BeefyCrvUSDUSDTStrategy is BaseBeefyCurveStrategy {
    using SafeTransferLib for address;

    ////////////////////////////////////////////////////////////////
    ///                        CONSTANTS                         ///
    ////////////////////////////////////////////////////////////////
    /// @notice Curve AtriCrypto(DAI,USDCe,USDT,wBTC,WETH) pool zapper in polygon
    ICurveAtriCryptoZapper constant zapper = ICurveAtriCryptoZapper(CURVE_AAVE_ATRICRYPTO_ZAPPER_POLYGON);
    /// @notice USDT token in polygon
    address public constant usdt = USDT_POLYGON;

    ////////////////////////////////////////////////////////////////
    ///                     INITIALIZATION                       ///
    ////////////////////////////////////////////////////////////////
    constructor() initializer { }

    /// @notice Initialize the Strategy
    /// @param _vault The address of the MaxApy Vault associated to the strategy
    /// @param _keepers The addresses of the keepers to be added as valid keepers to the strategy
    /// @param _strategyName the name of the strategy
    /// @param _curveLpPool The address of the strategy's main Curve pool, crvUsd<>usdt pool
    function initialize(
        IMaxApyVault _vault,
        address[] calldata _keepers,
        bytes32 _strategyName,
        address _strategist,
        ICurveLpPool _curveLpPool,
        IBeefyVault _beefyVault
    )
        public
        override
        initializer
    {
        super.initialize(_vault, _keepers, _strategyName, _strategist, _curveLpPool, _beefyVault);
        usdt.safeApprove(address(_curveLpPool), type(uint256).max);
        usdt.safeApprove(address(zapper), type(uint256).max);
        usdt.safeApprove(address(_vault), type(uint256).max);
        underlyingAsset.safeApprove(address(zapper), type(uint256).max);
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL CORE FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////
    /// @notice Invests `amount` of underlying into the Beefy vault
    /// @dev
    /// @param amount The amount of underlying to be deposited in the pool
    /// @param minOutputAfterInvestment minimum expected output after `_invest()` (designated in Curve LP tokens)
    /// @return The amount of tokens received, in terms of underlying
    function _invest(uint256 amount, uint256 minOutputAfterInvestment) internal virtual override returns (uint256) {
        // Don't do anything if amount to invest is 0
        if (amount == 0) return 0;

        uint256 underlyingBalance = _underlyingBalance();

        assembly ("memory-safe") {
            if gt(amount, underlyingBalance) {
                // throw the `NotEnoughFundsToInvest` error
                mstore(0x00, 0xb2ff68ae)
                revert(0x1c, 0x04)
            }
        }

        amount = Math.min(amount, maxSingleTrade);

        uint256 balanceBefore = usdt.balanceOf(address(this));

        // Swap the USDCe to USDT
        zapper.exchange_underlying(1, 2, amount, 0, address(this));
        // Get the amount of USDT received
        uint256 amountUSDT = usdt.balanceOf(address(this)) - balanceBefore;

        uint256 lpReceived;

        if (amountUSDT > 0) {
            uint256[] memory amounts = new uint256[](2);
            amounts[1] = amountUSDT;

            // Add liquidity to the curve pool in underlying token [coin1 -> usdce]
            lpReceived = curveLpPool.add_liquidity(amounts, 0, address(this));
        }

        uint256 _before = beefyVault.balanceOf(address(this));

        address want = address(beefyVault.want());

        // Deposit Curve LP tokens to Beefy vault
        beefyVault.deposit(lpReceived);

        uint256 _after = beefyVault.balanceOf(address(this));

        uint256 shares;

        assembly ("memory-safe") {
            shares := sub(_after, _before)
            if lt(shares, minOutputAfterInvestment) {
                // throw the `MinOutputAmountNotReached` error
                mstore(0x00, 0xf7c67a48)
                revert(0x1c, 0x04)
            }
        }

        emit Invested(address(this), amount);

        return shares;
    }

    /// @dev care should be taken, as the `amount` parameter is not in terms of underlying,
    /// but in terms of Beefy's moo tokens
    /// Note that if minimum withdrawal amount is not reached, funds will not be divested, and this
    /// will be accounted as a loss later.
    /// @return amountDivested the total amount divested, in terms of underlying asset
    function _divest(uint256 amount) internal override returns (uint256 amountDivested) {
        if (amount == 0) return 0;

        uint256 _before = beefyVault.want().balanceOf(address(this));

        // Withdraw from Beefy and unwrap directly to Curve LP tokens
        beefyVault.withdraw(amount);

        uint256 _after = beefyVault.want().balanceOf(address(this));

        uint256 lptokens = _after - _before;

        // Remove liquidity and obtain usdct
        amountDivested = curveLpPool.remove_liquidity_one_coin(
            lptokens,
            1,
            //usdct
            0,
            address(this)
        );

        uint256 balanceBefore = underlyingAsset.balanceOf(address(this));
        // Swap base asset to USDCe
        zapper.exchange_underlying(2, 1, amountDivested, 0, address(this));
        amountDivested = underlyingAsset.balanceOf(address(this)) - balanceBefore;
    }

    /////////////////////////////////////////////////////////////////
    ///                    VIEW FUNCTIONS                        ///
    ////////////////////////////////////////////////////////////////

    /// @notice This function is meant to be called from the vault
    /// @dev calculates the estimated real output of a withdrawal(including losses) for a @param requestedAmount
    /// for the vault to be able to provide an accurate amount when calling `previewRedeem`
    /// @return liquidatedAmount output in assets
    function previewLiquidate(uint256 requestedAmount)
        public
        view
        virtual
        override
        returns (uint256 liquidatedAmount)
    {
        uint256 loss;
        uint256 underlyingBalance = _underlyingBalance();
        // If underlying balance currently held by strategy is not enough to cover
        // the requested amount, we divest from the beefy Vault
        if (underlyingBalance < requestedAmount) {
            uint256 amountToWithdraw;
            unchecked {
                amountToWithdraw = requestedAmount - underlyingBalance;
            }
            uint256 shares = _sharesForAmount(amountToWithdraw);
            uint256 withdrawn = _shareValue(shares);
            // withdrawn = zapper.get_dy_underlying(2, 1, withdrawn) * 9995 / 10_000;
            if (withdrawn < amountToWithdraw) loss = amountToWithdraw - withdrawn;
        }

        assembly {
            liquidatedAmount := sub(requestedAmount, loss)
        }
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL VIEW FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////

    /// @notice Determines the current value of `shares`.
    /// @return _assets the estimated amount of underlying computed from shares `shares`
    function _shareValue(uint256 shares) internal view override returns (uint256 _assets) {
        _assets = super._shareValue(shares);
        _assets = _convertUsdtToUsdce(_assets);

        return _convertUsdtToUsdce(_assets);
    }

    /// @notice Determines how many shares depositor of `amount` of underlying would receive.
    /// @return shares the estimated amount of shares computed in exchange for underlying `amount`
    function _sharesForAmount(uint256 amount) internal view override returns (uint256 shares) {
        shares = super._sharesForAmount(_convertUsdceToUsdt(amount));

        return super._sharesForAmount(_convertUsdceToUsdt(amount));
    }

    // @notice Converts USDT to USDCe
    /// @param usdtAmount Amount of USDT
    /// @return Equivalent amount in USDCe
    function _convertUsdtToUsdce(uint256 usdtAmount) internal view returns (uint256) {
        return zapper.get_dy_underlying(2, 1, usdtAmount);
    }

    /// @notice Converts USDCe to USDT
    /// @param usdceAmount Amount of USDCe
    /// @return Equivalent amount in USDT
    function _convertUsdceToUsdt(uint256 usdceAmount) internal view returns (uint256) {
        return zapper.get_dy_underlying(1, 2, usdceAmount);
    }
}
