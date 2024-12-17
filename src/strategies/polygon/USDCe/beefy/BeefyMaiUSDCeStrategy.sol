// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { IBeefyVault } from "src/interfaces/IBeefyVault.sol";
import { ICurveLpPool } from "src/interfaces/ICurve.sol";
import { BaseBeefyCurveStrategy } from "src/strategies/base/BaseBeefyCurveStrategy.sol";
import { BaseBeefyStrategy, IMaxApyVault, SafeTransferLib } from "src/strategies/base/BaseBeefyStrategy.sol";

/// @title BeefyMaiUSDCeStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/strategies.sol
/// @notice `BeefyMaiUSDCeStrategy` supplies an underlying token into a generic Beefy Vault,
/// earning the Beefy Vault's yield
contract BeefyMaiUSDCeStrategy is BaseBeefyCurveStrategy {
    using SafeTransferLib for address;

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL CORE FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////
    /// @notice Invests `amount` of underlying into the Beefy vault
    /// @dev
    /// @param amount The amount of underlying to be deposited in the pool
    /// @param minOutputAfterInvestment minimum expected output after `_invest()` (designated in Curve LP tokens)
    /// @return The amount of tokens received, in terms of underlying
    function _invest(uint256 amount, uint256 minOutputAfterInvestment) internal override returns (uint256) {
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

        uint256[2] memory amounts;
        amounts[1] = amount;
        // Add liquidity to the mai<>usdce pool in usdce [coin1 -> usdce]
        lpReceived = curveLpPool.add_liquidity(amounts, 0, address(this));

        uint256 _before = underlyingVault.balanceOf(address(this));

        // Deposit Curve LP tokens to Beefy vault
        underlyingVault.deposit(lpReceived);

        uint256 _after = underlyingVault.balanceOf(address(this));
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
}
