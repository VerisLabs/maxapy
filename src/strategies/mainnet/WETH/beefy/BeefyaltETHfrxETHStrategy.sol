// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";

import { FRXETH_MAINNET } from "src/helpers/AddressBook.sol";
import { IBeefyVault } from "src/interfaces/IBeefyVault.sol";
import { ICurveLpPool } from "src/interfaces/ICurve.sol";
import { IWETH } from "src/interfaces/IWETH.sol";
import { BaseBeefyCurveStrategy } from "src/strategies/base/BaseBeefyCurveStrategy.sol";
import { BaseBeefyStrategy, IMaxApyVault, SafeTransferLib } from "src/strategies/base/BaseBeefyStrategy.sol";

/// @title BeefyaltETHfrxETHStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/strategies.sol
/// @notice `BeefyaltETHfrxETHStrategy` supplies an underlying token into a generic Beefy Vault,
/// earning the Beefy Vault's yield
contract BeefyaltETHfrxETHStrategy is BaseBeefyCurveStrategy {
    using SafeTransferLib for address;

    ////////////////////////////////////////////////////////////////
    ///                        CONSTANTS                         ///
    ////////////////////////////////////////////////////////////////
    /// @notice Ethereum mainnet's frxETH Token
    address public constant frxETH = FRXETH_MAINNET;

    /*==================CURVE-RELATED STORAGE VARIABLES==================*/
    /// @notice Curve's ETH-frxETH pool
    ICurveLpPool public curveEthFrxEthPool;

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
        IBeefyVault _beefyVault,
        ICurveLpPool _curveEthFrxEthPool
    )
        public
        virtual
        initializer
    {
        super.initialize(_vault, _keepers, _strategyName, _strategist, _beefyVault);

        // Curve init
        curveLpPool = _curveLpPool;
        curveEthFrxEthPool = _curveEthFrxEthPool;
        //CURVE_ETH_FRXETH_POOL_MAINNET

        underlyingAsset.safeApprove(address(curveLpPool), type(uint256).max);
        address(curveLpPool).safeApprove(address(beefyVault), type(uint256).max);
        frxETH.safeApprove(address(curveLpPool), type(uint256).max);
        frxETH.safeApprove(address(curveEthFrxEthPool), type(uint256).max);

        /// min single trade by default
        // minSingleTrade = 10e6;
        /// Unlimited max single trade by default
        maxSingleTrade = 100e18;
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL CORE FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////
    /// @notice Invests `amount` of underlying into the Beefy vault
    /// @dev
    /// @param amount The amount of underlying to be deposited in the pool
    /// @param minOutputAfterInvestment minimum expected output after `_invest()` (designated in Curve LP tokens)
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

        assembly ("memory-safe") {
            if gt(amount, underlyingBalance) {
                // throw the `NotEnoughFundsToInvest` error
                mstore(0x00, 0xb2ff68ae)
                revert(0x1c, 0x04)
            }
        }

        // Invested amount will be a maximum of `maxSingleTrade`
        amount = Math.min(maxSingleTrade, amount);

        // Unwrap WETH to interact with Curve
        IWETH(address(underlyingAsset)).withdraw(amount);

        // Swap ETH for frxETH
        uint256 frxEthReceivedAmount = curveEthFrxEthPool.exchange{ value: amount }(0, 1, amount, 0);

        uint256 lpReceived;

        uint256[2] memory amounts;
        amounts[1] = frxEthReceivedAmount;
        // Add liquidity to the mai<>usdce pool in usdce [coin1 -> usdce]
        lpReceived = curveLpPool.add_liquidity(amounts, 0, address(this));

        assembly ("memory-safe") {
            // if (lpReceived < minOutputAfterInvestment)
            if lt(lpReceived, minOutputAfterInvestment) {
                // throw the `MinOutputAmountNotReached` error
                mstore(0x00, 0xf7c67a48)
                revert(0x1c, 0x04)
            }
        }

        // Deposit Curve LP tokens to Beefy vault
        beefyVault.deposit(lpReceived);

        emit Invested(address(this), amount);

        return _lpValue(lpReceived);
    }

    /// @dev care should be taken, as the `amount` parameter is not in terms of underlying,
    /// but in terms of Beefy's moo tokens
    /// Note that if minimum withdrawal amount is not reached, funds will not be divested, and this
    /// will be accounted as a loss later.
    /// @return amountDivested the total amount divested, in terms of underlying asset
    function _divest(uint256 amount) internal virtual override returns (uint256 amountDivested) {
        if (amount == 0) return 0;

        uint256 _before = beefyVault.want().balanceOf(address(this));

        // Withdraw from Beefy and unwrap directly to Curve LP tokens
        beefyVault.withdraw(amount);

        uint256 _after = beefyVault.want().balanceOf(address(this));

        uint256 lptokens = _after - _before;
        // Remove liquidity and obtain frxETH
        uint256 amountWithdrawn = curveLpPool.remove_liquidity_one_coin(
            lptokens,
            1, // FrxEth
            0, // AlEth
            address(this)
        );
        if (amountWithdrawn != 0) {
            // Swap frxETH for ETH
            uint256 ethReceived = curveEthFrxEthPool.exchange(1, 0, amountWithdrawn, 0);
            // Wrap ETH into WETH
            IWETH(address(underlyingAsset)).deposit{ value: ethReceived }();
            return ethReceived;
        }
    }

    /////////////////////////////////////////////////////////////////
    ///                    VIEW FUNCTIONS                        ///
    ////////////////////////////////////////////////////////////////

    function previewLiquidate(uint256 requestedAmount) public view override returns (uint256) {
        uint256 loss;
        uint256 underlyingBalance = _underlyingBalance();

        if (underlyingBalance < requestedAmount) {
            uint256 amountToWithdraw = requestedAmount - underlyingBalance;

            uint256 beefySharesNeeded = _sharesForAmount(amountToWithdraw);
            uint256 availableBeefyShares = beefyVault.balanceOf(address(this));

            uint256 beefyShares = Math.min(beefySharesNeeded, availableBeefyShares);

            uint256 expectedCurveLp = beefyShares * beefyVault.balance() / beefyVault.totalSupply();
            uint256 expectedFrxEth = curveLpPool.calc_withdraw_one_coin(expectedCurveLp, 1);
            uint256 expectedEth = curveEthFrxEthPool.get_dy(1, 0, expectedFrxEth);

            if (expectedEth < amountToWithdraw) {
                loss = amountToWithdraw - expectedEth;
            }
        }

        return requestedAmount - loss;
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
        return (previewLiquidate(liquidatedAmount) * 108) / 100; // UNIT working
            // return (previewLiquidate(liquidatedAmount) * 101) / 100;     // FUZZ working
    }

    /// @notice Returns the max amount of assets that the strategy can liquidate, before realizing losses
    function maxLiquidateExact() public view override returns (uint256) {
        // make sure it doesnt revert when increaseing it 1% in the withdraw
        return (previewLiquidate(estimatedTotalAssets()) * 93) / 100; // UNIT working
            // return (previewLiquidate(estimatedTotalAssets()) * 99) / 100;        // FUZZ working
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL VIEW FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////

    /// @notice Determines the current value of `shares`.
    /// @return _assets the estimated amount of underlying computed from shares `shares`
    function _shareValue(uint256 shares) internal view virtual override returns (uint256 _assets) {
        uint256 frxETHAmount = super._shareValue(shares);
        // get swap estimation underlying frxETH for ETH
        if (frxETHAmount != 0) {
            return curveEthFrxEthPool.get_dy(1, 0, frxETHAmount);
        }
    }

    /// @notice Determines how many shares depositor of `amount` of underlying would receive.
    /// @return shares the estimated amount of shares computed in exchange for underlying `amount`
    function _sharesForAmount(uint256 amount) internal view virtual override returns (uint256 shares) {
        // get swap estimation underlying ETH for frxETH
        if (amount != 0) {
            uint256 frxETHAmount = curveEthFrxEthPool.get_dy(0, 1, amount);

            uint256[2] memory amounts;
            amounts[1] = frxETHAmount;

            uint256 lpAmount = curveLpPool.calc_token_amount(amounts, true);

            shares = BaseBeefyStrategy._sharesForAmount(lpAmount);
        }
    }

    //solhint-disable no-empty-blocks
    receive() external payable { }
}
