// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { IBeefyVault } from "src/interfaces/IBeefyVault.sol";
import { ICurveLpPool } from "src/interfaces/ICurve.sol";
import { BaseBeefyStrategy, IMaxApyVault, SafeTransferLib } from "src/strategies/base/BaseBeefyStrategy.sol";

/// @title BaseBeefyCurveStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/strategies.sol
/// @notice `BaseBeefyCurveStrategy` supplies an underlying token into a generic Beefy Vault,
/// earning the Beefy Vault's yield
contract BaseBeefyCurveStrategy is BaseBeefyStrategy {
    using SafeTransferLib for address;

    ////////////////////////////////////////////////////////////////
    ///            STRATEGY GLOBAL STATE VARIABLES               ///
    ////////////////////////////////////////////////////////////////

    /*==================CURVE-RELATED STORAGE VARIABLES==================*/
    /// @notice Main Curve pool for this Strategy
    ICurveLpPool public curveLpPool;

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
        virtual
        initializer
    {
        super.initialize(_vault, _keepers, _strategyName, _strategist, _beefyVault);

        // Curve init
        curveLpPool = _curveLpPool;

        underlyingAsset.safeApprove(address(curveLpPool), type(uint256).max);
        address(curveLpPool).safeApprove(address(beefyVault), type(uint256).max);

        /// min single trade by default
        minSingleTrade = 10e6;
        /// Unlimited max single trade by default
        maxSingleTrade = 100_000e6;
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

        amount = Math.min(maxSingleTrade, amount);

        uint256 lpReceived;
        uint256[] memory amounts = new uint256[](2);
        amounts[1] = amount;

        lpReceived = curveLpPool.add_liquidity(amounts, 0, address(this));

        uint256 _before = beefyVault.balanceOf(address(this));

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
    function _divest(uint256 amount) internal virtual override returns (uint256 amountDivested) {
        if (amount == 0) return 0;

        uint256 _before = beefyVault.want().balanceOf(address(this));

        beefyVault.withdraw(amount);

        uint256 _after = beefyVault.want().balanceOf(address(this));

        uint256 lptokens = _after - _before;

        return curveLpPool.remove_liquidity_one_coin(
            lptokens,
            1,
            //usdce
            0,
            address(this)
        );
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL VIEW FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////

    /// @notice Determines the current value of `shares`.
    /// @return _assets the estimated amount of underlying computed from shares `shares`
    function _shareValue(uint256 shares) internal view virtual override returns (uint256 _assets) {
        uint256 lpTokenAmount = super._shareValue(shares);
        uint256 lpPrice = _lpPrice();

        // lp price add get function _lpPrice()
        assembly {
            let scale := 0xde0b6b3a7640000 // This is 1e18 in hexadecimal
            _assets := div(mul(lpTokenAmount, lpPrice), scale)
        }
    }

    /// @notice Determines how many shares depositor of `amount` of underlying would receive.
    /// @return shares the estimated amount of shares computed in exchange for underlying `amount`
    function _sharesForAmount(uint256 amount) internal view virtual override returns (uint256 shares) {
        uint256 lpTokenAmount;
        uint256 lpPrice = _lpPrice();
        assembly {
            let scale := 0xde0b6b3a7640000 // This is 1e18 in hexadecimal
            lpTokenAmount := div(mul(amount, scale), lpPrice)
        }
        shares = super._sharesForAmount(lpTokenAmount);
    }

    /// @notice Returns the estimated price for the strategy's curve's LP token
    /// @return returns the estimated lp token price
    function _lpPrice() internal view returns (uint256) {
        uint256 virtualPrice = curveLpPool.get_virtual_price();
        uint256 exchangePrice = Math.min(
            curveLpPool.get_dy(1, 0, 1 ether), // WETH -> other token
            curveLpPool.get_dy(0, 1, 1 ether) // other token -> WETH
        );
        return (virtualPrice * exchangePrice) / 1 ether;
    }

    function _lpForAmount(uint256 amount) internal view virtual returns (uint256) {
        return (amount * 1e18) / _lpPrice();
    }

    function _lpValue(uint256 lp) internal view virtual returns (uint256) {
        return (lp * _lpPrice()) / 1e18;
    }
}
