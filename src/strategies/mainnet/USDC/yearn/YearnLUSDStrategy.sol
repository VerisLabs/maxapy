// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {
    BaseYearnV2Strategy,
    IMaxApyVault,
    SafeTransferLib,
    IYVault,
    Math
} from "src/strategies/base/BaseYearnV2Strategy.sol";
import { IUniswapV3Router as IRouter, IUniswapV3Pool } from "src/interfaces/IUniswap.sol";
import { OracleLibrary } from "src/lib/OracleLibrary.sol";
import { LUSD_MAINNET, UNISWAP_V3_USDC_LUSD_POOL_MAINNET, UNISWAP_V3_ROUTER_MAINNET } from "src/helpers/AddressBook.sol";

/// @title YearnLUSDStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/strategies.sol
/// @notice `YearnLUSDStrategy` supplies an underlying token into a generic Yearn Vault,
/// earning the Yearn Vault's yield
contract YearnLUSDStrategy is BaseYearnV2Strategy {
    using SafeTransferLib for address;
    ////////////////////////////////////////////////////////////////
    ///                        CONSTANTS                         ///
    ////////////////////////////////////////////////////////////////
    /// @notice LUSD token address in mainnet

    address public constant lusd = LUSD_MAINNET;
    /// @notice Router to perform USDC-LUSD swaps
    IRouter public constant router = IRouter(UNISWAP_V3_ROUTER_MAINNET);
    /// @notice Address of Uniswap V3 USDC-LUSD pool
    address public constant pool = UNISWAP_V3_USDC_LUSD_POOL_MAINNET;

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
        override
        initializer
    {
        __BaseStrategy_init(_vault, _keepers, _strategyName, _strategist);
        yVault = _yVault;

        /// Approve Yearn Vault to transfer LUSD
        lusd.safeApprove(address(_yVault), type(uint256).max);

        /// Approve Uniswap router to transfer both tokens
        underlyingAsset.safeApprove(address(router), type(uint256).max);
        lusd.safeApprove(address(router), type(uint256).max);

        /// Mininmum single trade is 0.01 token units
        minSingleTrade = 1e6 / 100;

        /// Max single trade
        maxSingleTrade = 10_000 * 1e6;
    }

    ////////////////////////////////////////////////////////////////
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
        // account pessimistically, we want the expected to always be lesser than the actual
        return super.previewLiquidate(requestedAmount) * 99 / 100;
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
        return super.previewLiquidate(liquidatedAmount) * 101 / 100;
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

        // swap the USDC to LUSD
        router.exactInputSingle(
            IRouter.ExactInputSingleParams({
                tokenIn: underlyingAsset,
                tokenOut: lusd,
                fee: 500,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: underlyingBalance,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        uint256 lusdBalance = _lusdBalance();

        uint256 shares = yVault.deposit(lusdBalance);

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
        // check that shares is not greater than actual shares balance
        uint256 sharesBalance = yVault.balanceOf(address(this));
        if (shares > sharesBalance) shares = sharesBalance;
        // return uint256 withdrawn = yVault.withdraw(shares);
        assembly {
            // store selector and parameters in memory
            mstore(0x00, 0x2e1a7d4d)
            mstore(0x20, shares)
            // call yVault.withdraw(shares)
            if iszero(call(gas(), sload(yVault.slot), 0, 0x1c, 0x24, 0x00, 0x20)) { revert(0x00, 0x04) }
            withdrawn := mload(0x00)
        }

        // swap the LUSD to USDC
        router.exactInputSingle(
            IRouter.ExactInputSingleParams({
                tokenIn: lusd,
                tokenOut: underlyingAsset,
                fee: 500,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: withdrawn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        withdrawn = _underlyingBalance();

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
    /// @dev if sqrt(yVault.totalAssets()) >>> 1e39, this could potentially revert
    /// @return returns the estimated amount of underlying computed from shares `shares`
    function _shareValue(uint256 shares) internal view override returns (uint256) {
        return _estimateAmountOut(lusd, underlyingAsset, uint128(super._shareValue(shares)), 1800); // use a 30 min TWAP
            // interval
    }

    /// @notice Determines how many shares depositor of `amount` of underlying would receive.
    /// @return shares returns the estimated amount of shares computed in exchange for underlying `amount`
    function _sharesForAmount(uint256 amount) internal view override returns (uint256 shares) {
        // estimate the LUSD value of the underlying amount
        amount = _estimateAmountOut(underlyingAsset, lusd, uint128(amount), 1800); // use a 30 min TWAP interval
        uint256 freeFunds = _freeFunds();
        assembly {
            // if freeFunds != 0 return amount
            if gt(freeFunds, 0) {
                // get yVault.totalSupply()
                mstore(0x00, 0x18160ddd)
                if iszero(staticcall(gas(), sload(yVault.slot), 0x1c, 0x04, 0x00, 0x20)) { revert(0x00, 0x04) }
                let totalSupply := mload(0x00)

                // Overflow check equivalent to require(totalSupply == 0 || amount <= type(uint256).max / totalSupply)
                if iszero(iszero(mul(totalSupply, gt(amount, div(not(0), totalSupply))))) { revert(0, 0) }

                shares := div(mul(amount, totalSupply), freeFunds)
            }
        }
    }

    /// @notice Returns the LUSD token balane of the strategy
    /// @return The amount of LUSD tokens held by the current contract
    function _lusdBalance() internal view returns (uint256) {
        return lusd.balanceOf(address(this));
    }

    /// @notice returns the estimated result of a Uniswap V3 swap
    /// @dev use TWAP oracle for more safety
    function _estimateAmountOut(
        address tokenIn,
        address tokenOut,
        uint128 amountIn,
        uint32 secondsAgo
    )
        internal
        view
        returns (uint256 amountOut)
    {
        // Code copied from OracleLibrary.sol, consult()
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secondsAgo;
        secondsAgos[1] = 0;

        // int56 since tick * time = int24 * uint32
        // 56 = 24 + 32
        (int56[] memory tickCumulatives,) = IUniswapV3Pool(pool).observe(secondsAgos);

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        // int56 / uint32 = int24
        int24 tick = int24(int256(tickCumulativesDelta) / int256(int32(secondsAgo)));
        // Always round to negative infinity

        if (tickCumulativesDelta < 0 && (int256(tickCumulativesDelta) % int256(int32(secondsAgo)) != 0)) {
            tick--;
        }

        amountOut = OracleLibrary.getQuoteAtTick(tick, amountIn, tokenIn, tokenOut);
    }
}
