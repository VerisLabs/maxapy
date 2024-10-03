// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { BaseBeefyStrategy, IMaxApyVault, SafeTransferLib } from "src/strategies/base/BaseBeefyStrategy.sol";
import { ICurveLpPool } from "src/interfaces/ICurve.sol";
import { IUniProxy } from "src/interfaces/IUniProxy.sol";
import { IHypervisor } from "src/interfaces/IHypervisor.sol";
import { IAlgebraPool } from "src/interfaces/IAlgebraPool.sol";
import { IBeefyVault } from "src/interfaces/IBeefyVault.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import  "src/helpers/AddressBook.sol";
import { ICurveAtriCryptoZapper } from "src/interfaces/ICurve.sol";
import { IUniswapV3Pool } from "src/interfaces/IUniswap.sol";
import { OracleLibrary } from "src/lib/OracleLibrary.sol";
import { LiquidityAmounts } from "src/lib/LiquidityAmounts.sol";

import { AlgebraPool } from "src/lib/AlgebraPool.sol";
import { SafeCast } from "src/lib/SafeCast.sol";



import {console2} from "forge-std/console2.sol";

/// @title BeefyUSDCeDAIStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/strategies.sol
/// @notice `BeefyUSDCeDAIStrategy` supplies an underlying token into a generic Beefy Vault,
/// earning the Beefy Vault's yield
contract BeefyUSDCeDAIStrategy is BaseBeefyStrategy {
    using SafeCast for uint128;

    using SafeTransferLib for address;

    ////////////////////////////////////////////////////////////////
    ///            STRATEGY GLOBAL STATE VARIABLES               ///
    ////////////////////////////////////////////////////////////////
    address public constant usdce = USDCE_POLYGON;
    address public constant dai = DAI_POLYGON;

    uint256 constant _1_USDCE = 1e6;
    uint256 constant _1_DAI = 1 ether;
    
    /// @notice Router to perform Stable swaps
    ICurveAtriCryptoZapper constant zapper = ICurveAtriCryptoZapper(CURVE_AAVE_ATRICRYPTO_ZAPPER_POLYGON);

    /*==================GAMMA-RELATED STORAGE VARIABLES==================*/
    IUniProxy public uniProxy;
    IHypervisor public hypervisor;

    ////////////////////////////////////////////////////////////////
    ///                     INITIALIZATION                       ///
    ////////////////////////////////////////////////////////////////
    constructor() initializer { }

    /// @notice Initialize the Strategy
    /// @param _vault The address of the MaxApy Vault associated to the strategy
    /// @param _keepers The addresses of the keepers to be added as valid keepers to the strategy
    /// @param _strategyName the name of the strategy
    /// @param _uniProxy The address of the strategy's main Curve pool, crvUsd<>usdt pool
    function initialize(
        IMaxApyVault _vault,
        address[] calldata _keepers,
        bytes32 _strategyName,
        address _strategist,
        IUniProxy _uniProxy,
        IHypervisor _hypervisor,
        IBeefyVault _beefyVault
    )
        public
        initializer
    {

        console2.log("in init strategy");
        
        __BaseStrategy_init(_vault, _keepers, _strategyName, _strategist);
        beefyVault = _beefyVault;

        // Gamma init
        uniProxy = _uniProxy;
        hypervisor = _hypervisor;

        /// Approve Vault to transfer USDCe
        underlyingAsset.safeApprove(address(_vault), type(uint256).max);

        underlyingAsset.safeApprove(address(zapper), type(uint256).max);
        dai.safeApprove(address(zapper), type(uint256).max);

        underlyingAsset.safeApprove(address(uniProxy), type(uint256).max);
        dai.safeApprove(address(uniProxy), type(uint256).max);

        underlyingAsset.safeApprove(address(hypervisor), type(uint256).max);
        dai.safeApprove(address(hypervisor), type(uint256).max);

        address(hypervisor).safeApprove(address(beefyVault), type(uint256).max);
    }


    // Function to calculate how much USDCe to swap
    function calculateUSDCeToSwap(uint256 totalUSDCe, uint256 ratio) public view returns (uint256 usdceToSwap) {
        
        uint256 rate = _convertUsdceToDai(1 * _1_USDCE);

        assembly {
            usdceToSwap := div(mul(ratio, totalUSDCe), add(rate,ratio))
        }

        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:89 ~ calculateUSDCeToSwap ~ usdceToSwap:", usdceToSwap);

        return usdceToSwap;

    }

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

        // step1 get the Gamma pool ratio
        // 1 usdce -> x dai
        (uint256 amountStart, uint256 amountEnd) = uniProxy.getDepositAmount(GAMMA_USDCE_DAI_HYPERVISOR_POLYGON, USDCE_POLYGON, 1 * _1_USDCE);
        console2.log("amountStart , amountEnd", amountStart, amountEnd);
        

        // Calculate how much USDCe should be swapped into DAI
        uint256 usdceToSwap = calculateUSDCeToSwap(amount, (amountStart+amountEnd)/2);
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:124 ~ _invest ~ usdceToSwap: , left usdce = ", usdceToSwap, amount - usdceToSwap);
        //  6967206660395375756
        
        // step2 swap a part of usdce into dai
        console2.log("IN STEP 2 SWAPPING");
        console2.log("dai.balanceOf(address(this)) = ", dai.balanceOf(address(this)));
        console2.log("underlyingAsset.balanceOf(address(this)) = ", underlyingAsset.balanceOf(address(this)));


        zapper.exchange_underlying(1, 0, usdceToSwap, 0, address(this));

        console2.log("dai.balanceOf(address(this)) = ", dai.balanceOf(address(this)));
        console2.log("underlyingAsset.balanceOf(address(this)) = ", underlyingAsset.balanceOf(address(this)));
        

        //step3 deposit usdce and dai into gamma vault
        console2.log();
        console2.log("IN STEP 3 deposit pairs");
        uint256[4] memory minOut = [uint256(0), uint256(0), uint256(0), uint256(0)];
        uint256 lpReceived;

        if (dai.balanceOf(address(this)) > 0 && underlyingAsset.balanceOf(address(this)) > 0) {

            console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:149 ~ _invest ~ hypervisor balance of:", hypervisor.balanceOf(address(this)));
            // uint256 LPs = uniProxy.deposit(underlyingAsset.balanceOf(address(this)), dai.balanceOf(address(this)), address(this), GAMMA_USDCE_DAI_HYPERVISOR_POLYGON, minOut);
            lpReceived = uniProxy.deposit(underlyingAsset.balanceOf(address(this)), dai.balanceOf(address(this)), address(this), GAMMA_USDCE_DAI_HYPERVISOR_POLYGON, minOut);
            console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:149 ~ _invest ~ LPs:", lpReceived);
            console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:149 ~ _invest ~ hypervisor balance of:", hypervisor.balanceOf(address(this)));

            console2.log("dai.balanceOf(address(this)) = ", dai.balanceOf(address(this)));
            console2.log("underlyingAsset.balanceOf(address(this)) = ", underlyingAsset.balanceOf(address(this)));


            console2.log("dai.balanceOf(address(this)) ////////// = ", dai.balanceOf(address(GAMMA_USDCE_DAI_HYPERVISOR_POLYGON)));
            console2.log("underlyingAsset.balanceOf(address(this)) //////////= ", underlyingAsset.balanceOf(address(GAMMA_USDCE_DAI_HYPERVISOR_POLYGON)));

        }

        //step4 deposit LP token into Beefy

        uint256 _before = beefyVault.balanceOf(address(this));

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

        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:191 ~ _invest ~ shares:", shares);

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
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:205 ~ _divest ~ _before:", _before);


        // Withdraw from Beefy and unwrap directly to Curve LP tokens
        beefyVault.withdraw(amount);

        uint256 _after = beefyVault.want().balanceOf(address(this));
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:212 ~ _divest ~ _after:", _after);


        uint256 lptokens = _after - _before;
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:216 ~ _divest ~ lptokens:", lptokens);


        // Remove liquidity and obtain usdce
        uint256[4] memory minOut = [uint256(0), uint256(0), uint256(0), uint256(0)];
        (uint256 amount0, uint256 amount1) = hypervisor.withdraw(lptokens, address(this), address(this), minOut);
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:222 ~ _divest ~ amount1:", amount1);

        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:222 ~ _divest ~ amount0:", amount0);


        // step2 swap a part of usdce into dai
        console2.log("IN STEP 2 SWAPPING");
        console2.log("dai.balanceOf(address(this)) = ", dai.balanceOf(address(this)));
        console2.log("underlyingAsset.balanceOf(address(this)) = ", underlyingAsset.balanceOf(address(this)));


        zapper.exchange_underlying(0, 1, dai.balanceOf(address(this)), 0, address(this));

        console2.log("dai.balanceOf(address(this)) = ", dai.balanceOf(address(this)));
        console2.log("underlyingAsset.balanceOf(address(this)) = ", underlyingAsset.balanceOf(address(this)));

        amountDivested = underlyingAsset.balanceOf(address(this));

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
            if (withdrawn < amountToWithdraw) loss = amountToWithdraw - withdrawn;
        }
        liquidatedAmount = requestedAmount - loss;
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL VIEW FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////

    /// @notice Determines the current value of `shares`.
    /// @return _assets the estimated amount of underlying computed from shares `shares`
    function _shareValue(uint256 shares) internal view override returns (uint256 _assets) {
        uint256 lpTokenAmount = super._shareValue(shares);
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:282 ~ _shareValue ~ lpTokenAmount:", lpTokenAmount);


        int24 baseLower = hypervisor.baseLower();
        int24 baseUpper = hypervisor.baseUpper();
        int24 limitLower = hypervisor.limitLower();
        int24 limitUpper = hypervisor.limitUpper();
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:289 ~ _shareValue ~ limitUpper:", limitUpper);


        uint128 L1 = _liquidityForShares(baseLower, baseUpper, lpTokenAmount);
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:289 ~ _shareValue ~ L1:", L1);

        uint128 L2 = _liquidityForShares(limitLower, limitUpper, lpTokenAmount);
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:292 ~ _shareValue ~ L2:", L2);

        (uint256 base0, uint256 base1) = _CalcBurnLiquidity(baseLower, baseUpper, L1);
        (uint256 limit0, uint256 limit1) = _CalcBurnLiquidity(limitLower, limitUpper, L2);

        // Push tokens proportional to unused balances
        uint256 unusedAmount0 = underlyingAsset.balanceOf(GAMMA_USDCE_DAI_HYPERVISOR_POLYGON) * lpTokenAmount / hypervisor.totalSupply();
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:314 ~ _shareValue ~ unusedAmount0:", unusedAmount0);

        uint256 unusedAmount1 = DAI_POLYGON.balanceOf(GAMMA_USDCE_DAI_HYPERVISOR_POLYGON) * lpTokenAmount / hypervisor.totalSupply();
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:317 ~ _shareValue ~ unusedAmount1:", unusedAmount1);


        uint256 amount0 = base0 + limit0 + unusedAmount0;
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:317 ~ _shareValue ~ amount0:", amount0);

        uint256 amount1 = base1 + limit1 + unusedAmount1;
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:320 ~ _shareValue ~ amount1:", amount1);


        
        // 3889238936027972681
        // 3889710311626499156

        // 6108792
        // 5934045

        
    }


    function _CalcBurnLiquidity (int24 tickLower, int24 tickUpper, uint128 liquidity) public view returns (uint256 amount0, uint256 amount1){
        
        // Pool.burn
        (uint160 sqrtRatioX96, int24 globalTick, , , , , ) = IAlgebraPool(ALGEBRA_POOL).globalState();
        (int256 amount0Int, int256 amount1Int, ) = AlgebraPool._getAmountsForLiquidity(tickLower, tickUpper, int128(liquidity), globalTick, sqrtRatioX96);
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:343 ~ _CalcBurnLiquidity ~ amount1Int:", amount1Int);

        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:343 ~ _CalcBurnLiquidity ~ amount0Int:", amount0Int);


        amount0 = uint256(amount0Int);
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:349 ~ _CalcBurnLiquidity ~ amount0:", amount0);

        amount1 = uint256(amount1Int);

        amount0 = _uint128Safe(amount0);
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:354 ~ _CalcBurnLiquidity ~ amount0:", amount0);

        amount1 = _uint128Safe(amount1);


        //Pool.collect
        (, uint128 positionFees0, uint128 positionFees1) = _position(tickLower, tickUpper);
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:364 ~ _CalcBurnLiquidity ~ positionFees1:", positionFees1);

        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:364 ~ _CalcBurnLiquidity ~ positionFees0:", positionFees0);


        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:359 ~ _CalcBurnLiquidity ~ amount0:", amount0);
        amount0 = amount0 > positionFees0 ? positionFees0 : amount0;
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:359 ~ _CalcBurnLiquidity ~ amount0:", amount0);

        amount1 = amount1 > positionFees1 ? positionFees1 : amount1;
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:362 ~ _CalcBurnLiquidity ~ amount1:", amount1);

    }

    /// @notice Determines how many shares depositor of `amount` of underlying would receive.
    /// @return shares the estimated amount of shares computed in exchange for underlying `amount`
    function _sharesForAmount(uint256 amount) internal view override returns (uint256 shares) {

        uint256 lpTokenAmount;
        (uint256 amountStart, uint256 amountEnd) = uniProxy.getDepositAmount(GAMMA_USDCE_DAI_HYPERVISOR_POLYGON, USDCE_POLYGON, 1 * _1_USDCE);
        console2.log("amountStart , amountEnd", amountStart, amountEnd);
        

        // Calculate how much USDCe should be swapped into DAI
        uint256 usdceToSwap = calculateUSDCeToSwap(amount, (amountStart+amountEnd)/2);
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:299 ~ _sharesForAmount ~ usdceToSwap:", usdceToSwap);

        uint256 daiTokenAmount = zapper.get_dy_underlying(1, 0, usdceToSwap);
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:302 ~ _sharesForAmount ~ daiTokenAmount:", daiTokenAmount);

        uint256 usdceTokenAmount = amount - usdceToSwap;
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:305 ~ _sharesForAmount ~ usdceTokenAmount:", usdceTokenAmount);

        
        uint256 price;
        uint256 PRECISION = 1e36;
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:310 ~ _sharesForAmount ~ PRECISION:", PRECISION);

        
        uint160 sqrtPrice = OracleLibrary.getSqrtRatioAtTick(hypervisor.currentTick());
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:313 ~ _sharesForAmount ~ sqrtPrice:", sqrtPrice);


        assembly {
            price := div(mul(mul(sqrtPrice, sqrtPrice), PRECISION), exp(2, 192))
        }

        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:318 ~ _sharesForAmount ~ price:", price);
        
        (uint256 pool0, uint256 pool1) = hypervisor.getTotalAmounts();
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:323 ~ _sharesForAmount ~ pool0, uint256 pool1:", pool0, pool1);


        assembly {
            lpTokenAmount := add(daiTokenAmount, div(mul(usdceTokenAmount, price), PRECISION))
        }

        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:328 ~ _sharesForAmount ~ lpTokenAmount:", lpTokenAmount);
        
        uint256 total = hypervisor.totalSupply();
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:333 ~ _sharesForAmount ~ total:", total);


        if (total != 0) {    
            assembly {
                let pool0PricedInToken1 := div(mul(pool0, price), PRECISION)
                lpTokenAmount := div(mul(lpTokenAmount, total), add(pool0PricedInToken1, pool1))
            }
        }
        
        shares = super._sharesForAmount(lpTokenAmount);
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:344 ~ _sharesForAmount ~ shares:", shares);

    }

    // @notice Converts USDT to USDCe
    /// @param usdceAmount Amount of USDT
    /// @return Equivalent amount in USDCe
    function _convertUsdceToDai(uint256 usdceAmount) internal view returns (uint256) {
        return zapper.get_dy_underlying(1, 0, usdceAmount);
    }

    /// @notice Converts USDCe to USDT
    /// @param daiAmount Amount of USDCe
    /// @return Equivalent amount in USDT
    function _convertDAIToUsdce(uint256 daiAmount) internal view returns (uint256) {
        return zapper.get_dy_underlying(0, 1, daiAmount);
    }


    
    
    // Gamma hypervisor internal functions

    /// @notice Get the liquidity amount for given liquidity tokens
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param shares Shares of position
    /// @return The amount of liquidity toekn for shares
    function _liquidityForShares(
        int24 tickLower,
        int24 tickUpper,
        uint256 shares
    ) internal view returns (uint128) {

        console2.log("IN _liquidityForShares");
        (uint128 position, , ) = _position(tickLower, tickUpper);
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:392 ~ )internalviewreturns ~ position:", position);

        uint128 tots = uint128(uint256(position) * shares / hypervisor.totalSupply());
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:395 ~ )internalviewreturns ~ tots:", tots);
        
        
        return uint128(uint256(position) * shares / hypervisor.totalSupply());
        }
        
        // @notice Get the info of the given position
        // @param tickLower The lower tick of the position
        // @param tickUpper The upper tick of the position
        // @return liquidity The amount of liquidity of the position
        // @return tokensOwed0 Amount of token0 owed
        // @return tokensOwed1 Amount of token1 owed
        function _position(int24 tickLower, int24 tickUpper)
        internal
        view
        returns (
            uint128 liquidity,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
      bytes32 positionKey;
      console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:427 ~ _position:");
      assembly {
        positionKey := or(shl(24, or(shl(24, GAMMA_USDCE_DAI_HYPERVISOR_POLYGON), and(tickLower, 0xFFFFFF))), and(tickUpper, 0xFFFFFF))
      }
    
        (liquidity, , , , tokensOwed0, tokensOwed1) = IAlgebraPool(ALGEBRA_POOL).positions(positionKey);
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:499 ~ tokensOwed1:", tokensOwed1);

        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:499 ~ tokensOwed0:", tokensOwed0);

        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:396 ~ liquidity:", liquidity);

    }

    function _uint128Safe(uint256 x) internal pure returns (uint128) {
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:497 ~ _uint128Safe ~ type(uint128).max:", type(uint128).max);

        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:497 ~ _uint128Safe ~ x:", x);
        assert(x <= type(uint128).max);
        return uint128(x);
    }

    /// @notice Get the amounts of the given numbers of liquidity tokens
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param liquidity The amount of liquidity tokens
    /// @return Amount of token0 and token1
    function _amountsForLiquidity(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) internal view returns (uint256, uint256) {
        (uint160 sqrtRatioX96, , , , , , ) = IAlgebraPool(ALGEBRA_POOL).globalState();
        console2.log("###   ~ file: BeefyUSDCeDAIStrategy.sol:446 ~ )internalviewreturns ~ sqrtRatioX96:", sqrtRatioX96);
        
        return
        LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                OracleLibrary.getSqrtRatioAtTick(tickLower),
                OracleLibrary.getSqrtRatioAtTick(tickUpper),
                liquidity
            );
    }

}
