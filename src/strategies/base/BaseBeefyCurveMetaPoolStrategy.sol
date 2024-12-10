// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { IBeefyVault } from "src/interfaces/IBeefyVault.sol";
import { ICurveLpPool, ICurveTriPool } from "src/interfaces/ICurve.sol";
import { BaseBeefyStrategy, IMaxApyVault, SafeTransferLib } from "src/strategies/base/BaseBeefyStrategy.sol";
import { CRV3POOL_MAINNET } from "src/helpers/AddressBook.sol";
import {ERC20} from  "solady/tokens/ERC20.sol";

import {console2} from "forge-std/console2.sol";

/// @title BaseBeefyCurveMetaPoolStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/strategies.sol
/// @notice `BaseBeefyCurveMetaPoolStrategy` supplies an underlying token into a generic Beefy Vault,
/// earning the Beefy Vault's yield
contract BaseBeefyCurveMetaPoolStrategy is BaseBeefyStrategy {
    using SafeTransferLib for address;

    ////////////////////////////////////////////////////////////////
    ///            STRATEGY GLOBAL STATE VARIABLES               ///
    ////////////////////////////////////////////////////////////////

    /*==================CURVE-RELATED STORAGE VARIABLES==================*/
    /// @notice Curve Meta pool for this Strategy
    ICurveLpPool public curveLpPool;
    /// @notice Curve 3pool for this Strategy - DAI/USDC/USDT Pool
    ICurveTriPool public curveTriPool;

    address public crvTriPoolToken;

    ////////////////////////////////////////////////////////////////
    ///                     INITIALIZATION                       ///
    ////////////////////////////////////////////////////////////////
    constructor() initializer { }

    /// @notice Initialize the Strategy
    /// @param _vault The address of the MaxApy Vault associated to the strategy
    /// @param _keepers The addresses of the keepers to be added as valid keepers to the strategy
    /// @param _strategyName the name of the strategy
    /// @param _curveLpPool The address of the strategy's main Curve pool
    /// @param _beefyVault The address of the strategy's Beefy vault
    /// @param _curveTriPool The address of the strategy's Curve Tripool
    /// @param _crvTriPoolToken The address of the Curve Tripool's token
    function initialize(
        IMaxApyVault _vault,
        address[] calldata _keepers,
        bytes32 _strategyName,
        address _strategist,
        ICurveLpPool _curveLpPool,
        IBeefyVault _beefyVault,
        ICurveTriPool _curveTriPool,
        address _crvTriPoolToken
    )
        public
        virtual
        initializer
    {
        super.initialize(_vault, _keepers, _strategyName, _strategist, _beefyVault);

        // Curve init
        curveLpPool = _curveLpPool;
        console2.log("###   ~ file: BaseBeefyCurveMetaPoolStrategy.sol:60 ~ _curveLpPool:");

        curveTriPool = _curveTriPool;
        crvTriPoolToken = _crvTriPoolToken;

        console2.log("### 2");

        underlyingAsset.safeApprove(address(curveTriPool), type(uint256).max);
        console2.log("### 3");
        crvTriPoolToken.safeApprove(address(curveLpPool), type(uint256).max);
        console2.log("###   ~ file: BaseBeefyCurveMetaPoolStrategy.sol:85 ~ address(crvTriPoolToken):", crvTriPoolToken);
        console2.log("### 4");
        address(curveLpPool).safeApprove(address(beefyVault), type(uint256).max);
        console2.log("### 5");
        /// min single trade by default
        minSingleTrade = 10e6;
        console2.log("###   ~ file: BaseBeefyCurveMetaPoolStrategy.sol:74 ~ minSingleTrade:", minSingleTrade);

        /// Unlimited max single trade by default
        maxSingleTrade = 100_000e6;
        console2.log("###   ~ file: BaseBeefyCurveMetaPoolStrategy.sol:78 ~ maxSingleTrade:", maxSingleTrade);

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
        
        uint256[3] memory amountsUsdc;
        amountsUsdc[1] = amount;

        uint256 _before = ERC20(crvTriPoolToken).balanceOf(address(this));
        // uint256 _before = ERC20(_3crvToken).balanceOf(address(this));
        console2.log("###   ~ file: BaseBeefyCurveMetaPoolStrategy.sol:111 ~ _invest ~ _before:", _before);

        // Add liquidity to the curveTriPool in underlying token [coin1 -> usdc]
        curveTriPool.add_liquidity(amountsUsdc, 0);
        uint256 _after = ERC20(crvTriPoolToken).balanceOf(address(this));
        // uint256 _after = ERC20(_3crvToken).balanceOf(address(this));
        console2.log("###   ~ file: BaseBeefyCurveMetaPoolStrategy.sol:116 ~ _invest ~ _after:", _after);


        uint256 _3crvTokenReceived;
        assembly ("memory-safe") {
            _3crvTokenReceived := sub(_after, _before)
        }

        uint256[2] memory amounts;
        amounts[1] = _3crvTokenReceived;
        // Add liquidity to the curve Metapool in 3crv token [coin1 -> 3crv]
        uint256 lpReceived = curveLpPool.add_liquidity(amounts, 0, address(this));
        console2.log("###   ~ file: BaseBeefyCurveMetaPoolStrategy.sol:137 ~ _invest ~ lpReceived:", lpReceived);


        _before = beefyVault.balanceOf(address(this));

        // Deposit Curve LP tokens to Beefy vault
        beefyVault.deposit(lpReceived);

        _after = beefyVault.balanceOf(address(this));
        uint256 shares;

        assembly ("memory-safe") {
            shares := sub(_after, _before)
            if lt(shares, minOutputAfterInvestment) {
                // throw the `MinOutputAmountNotReached` error
                mstore(0x00, 0xf7c67a48)
                revert(0x1c, 0x04)
            }
        }

        console2.log("###   ~ file: BaseBeefyCurveMetaPoolStrategy.sol:161 ~ _invest ~ shares:", shares);

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

        // Withdraw from Beefy and unwrap directly to Curve LP tokens
        beefyVault.withdraw(amount);

        uint256 _after = beefyVault.want().balanceOf(address(this));

        uint256 lptokens = _after - _before;

        // Remove liquidity and obtain usdce
        uint256 _3crvTokenReceived =  curveLpPool.remove_liquidity_one_coin(
            lptokens,
            1,
            //usdce
            0,
            address(this)
        );
        console2.log("###   ~ file: BaseBeefyCurveMetaPoolStrategy.sol:185 ~ _divest ~ _3crvTokenReceived:", _3crvTokenReceived);


        _before = underlyingAsset.balanceOf(address(this));

        curveTriPool.remove_liquidity_one_coin(
            _3crvTokenReceived,
            1,
            //usdce
            0
        );

        amountDivested = underlyingAsset.balanceOf(address(this)) - _before;
        console2.log("###   ~ file: BaseBeefyCurveMetaPoolStrategy.sol:198 ~ _divest ~ amountDivested:", amountDivested);

    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL VIEW FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////

    /// @notice Determines the current value of `shares`.
    /// @return _assets the estimated amount of underlying computed from shares `shares`
    function _shareValue(uint256 shares) internal view virtual override returns (uint256 _assets) {
        console2.log("###   ~ file: BaseBeefyCurveMetaPoolStrategy.sol:218 ~ _shareValue ~ shares:", shares);

        uint256 expectedCurveLp = shares * beefyVault.balance() / beefyVault.totalSupply();
        console2.log("###   ~ file: BaseBeefyCurveMetaPoolStrategy.sol:219 ~ _shareValue ~ expectedCurveLp:", expectedCurveLp);

        if (expectedCurveLp > 0) {
            uint256 expected3Crv = curveLpPool.calc_withdraw_one_coin(expectedCurveLp, 1);
            console2.log("###   ~ file: BaseBeefyCurveMetaPoolStrategy.sol:222 ~ _shareValue ~ expected3Crv:", expected3Crv);
            if (expected3Crv > 0) {
                _assets = curveTriPool.calc_withdraw_one_coin(expected3Crv, 1);
            }
        }
        
        console2.log("###   ~ file: BaseBeefyCurveMetaPoolStrategy.sol:227 ~ _shareValue ~ _assets:", _assets);

        // uint256 lpTokenAmount = super._shareValue(shares);
        // console2.log("###   ~ file: BaseBeefyCurveMetaPoolStrategy.sol:216 ~ _shareValue ~ lpTokenAmount:", lpTokenAmount);

        // uint256 lpPrice = _lpPrice();
        // console2.log("###   ~ file: BaseBeefyCurveMetaPoolStrategy.sol:219 ~ _shareValue ~ lpPrice:", lpPrice);


        // uint256 lpTriPoolPrice =_lpTriPoolPrice();
        // console2.log("###   ~ file: BaseBeefyCurveMetaPoolStrategy.sol:223 ~ _shareValue ~ lpTriPoolPrice:", lpTriPoolPrice);


        // // lp price add get function _lpPrice()
        // assembly {
        //     let scale := 0xde0b6b3a7640000 // This is 1e18 in hexadecimal
        //     _assets := div(mul(lpTokenAmount, lpPrice), scale)
        //     _assets := div(mul(_assets, lpTriPoolPrice), scale)
            
        // }
    }

    /// @notice Determines how many shares depositor of `amount` of underlying would receive.
    /// @return shares the estimated amount of shares computed in exchange for underlying `amount`
    function _sharesForAmount(uint256 amount) internal view virtual override returns (uint256 shares) {

        uint256[3] memory amounts;
        amounts[1] = amount;

        
        uint256 lpTokenAmount = curveTriPool.calc_token_amount(amounts, true);  
        console2.log("###   ~ file: BaseBeefyCurveMetaPoolStrategy.sol:228 ~ _sharesForAmount ~ lpTokenAmount:", lpTokenAmount);


        uint256[2] memory _amounts;
        _amounts[1] = lpTokenAmount;  

        lpTokenAmount = curveLpPool.calc_token_amount(_amounts, true);
        console2.log("###   ~ file: BaseBeefyCurveMetaPoolStrategy.sol:235 ~ _sharesForAmount ~ lpTokenAmount:", lpTokenAmount);

        shares = super._sharesForAmount(lpTokenAmount);
        console2.log("###   ~ file: BaseBeefyCurveMetaPoolStrategy.sol:245 ~ _sharesForAmount ~ shares:", shares);

    }

    /// @notice Returns the estimated price for the strategy's curve's LP token
    /// @return returns the estimated lp token price
    function _lpPrice() internal view returns (uint256) {
        return ((curveLpPool.get_virtual_price() * curveLpPool.get_dy(0, 1, 1 ether)) / 1 ether);
    }

    /// @notice Returns the estimated price for the strategy's curve's Tri pool LP token
    /// @return returns the estimated lp token price
    function _lpTriPoolPrice() internal view returns (uint256) {
        return ((curveTriPool.get_virtual_price() 
                   * Math.min(curveTriPool.get_dy(0, 1, 1 ether), curveTriPool.get_dy(1,0,1e6))) / 1 ether);
    }
}
