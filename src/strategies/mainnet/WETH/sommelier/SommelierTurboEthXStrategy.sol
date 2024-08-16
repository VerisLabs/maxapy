// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {
    BaseSommelierStrategy,
    SafeTransferLib,
    IMaxApyVault,
    ICellar
} from "src/strategies/base/BaseSommelierStrategy.sol";
import { IUniswapV3Router } from "src/interfaces/IUniswap.sol";
import { ETHX_MAINNET, UNISWAP_V3_ROUTER_MAINNET } from "src/helpers/AddressBook.sol";

/// @title SommelierTurboEthXStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/strategies.sol
/// @notice `SommelierTurboEthXStrategy` supplies an underlying token into a generic Sommelier Vault,
/// earning the Sommelier Vault's yield
contract SommelierTurboEthXStrategy is BaseSommelierStrategy {
    using SafeTransferLib for address;

    ////////////////////////////////////////////////////////////////
    ///                         CONSTANTS                        ///
    ////////////////////////////////////////////////////////////////
    address constant ethX = ETHX_MAINNET;
    IUniswapV3Router constant router = IUniswapV3Router(UNISWAP_V3_ROUTER_MAINNET);

    /// @dev the initialization function must be defined in each strategy
    /// @notice Initialize the Strategy
    /// @param _vault The address of the MaxApy Vault associated to the strategy
    /// @param _keepers The addresses of the keepers to be added as valid keepers to the strategy
    /// @param _strategyName the name of the strategy
    /// @param _cellar The address of the Sommelier Turbo-stETH cellar
    function initialize(
        IMaxApyVault _vault,
        address[] calldata _keepers,
        bytes32 _strategyName,
        address _strategist,
        ICellar _cellar
    )
        public
        override
        initializer
    {
        __BaseStrategy_init(_vault, _keepers, _strategyName, _strategist);
        cellar = _cellar;
        /// Approve Cellar Vault to transfer underlying
        underlyingAsset.safeApprove(address(_cellar), type(uint256).max);
        // Set max and min single trade
        minSingleTrade = 0.001 ether;
        maxSingleTrade = 10 ether;

        // Approve ETHX to router
        ethX.safeApprove(address(router), type(uint256).max);
    }

    /////////////////////////////////////////////////////////////////
    ///                    CORE LOGIC                             ///
    /////////////////////////////////////////////////////////////////
    /// @notice Withdraws exactly `amountNeeded` to `vault`.
    /// @dev This may only be called by the respective Vault.
    /// @param amountNeeded How much `underlyingAsset` to withdraw.
    /// @return loss Any realized losses
    function liquidateExact(uint256 amountNeeded)
        external
        virtual
        override
        checkRoles(VAULT_ROLE)
        returns (uint256 loss)
    {
        uint256 underlyingBalance = _underlyingBalance();
        if (underlyingBalance < amountNeeded) {
            uint256 amountToWithdraw;
            unchecked {
                amountToWithdraw = amountNeeded - underlyingBalance;
            }
            uint256 burntShares = cellar.withdraw(amountToWithdraw, address(this), address(this));
            // use sub zero because shares could be fewer than expected and underflow
            loss = _sub0(_shareValue(burntShares), amountToWithdraw);
        }

        uint256 ethXBalance = _ethXBalance();
        // If the vault sent any ETHX swap it to underlying WETH
        if (ethXBalance > 0) _swapEthX(ethXBalance);
        underlyingAsset.safeTransfer(address(vault), amountNeeded);
        // Note: Reinvest anything leftover on next `harvest`
        _snapshotEstimatedTotalAssets();
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL CORE FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////

    /// @notice Divests amount `shares` from Cellar Vault
    /// Note that divesting from Cellar could potentially cause loss (set to 0.01% as default in
    /// the Vault implementation), so the divested amount might actually be different from
    /// the requested `shares` to divest
    /// @dev care should be taken, as the `shares` parameter is *not* in terms of underlying,
    /// but in terms of cellar shares
    /// @return withdrawn the total amount divested, in terms of underlying asset
    function _divest(uint256 shares) internal override returns (uint256 withdrawn) {
        // if cellar is paused dont liquidate, skips revert
        if (cellar.isPaused()) return 0;
        uint256 balanceBefore = _underlyingBalance();
        cellar.redeem(shares, address(this), address(this));
        uint256 ethXBalance = _ethXBalance();
        // If the vault sent any ethX swap it to underlying WETH
        if (ethXBalance > 0) withdrawn += _swapEthX(ethXBalance);
        withdrawn = _underlyingBalance() - balanceBefore;
        emit Divested(address(this), shares, withdrawn);
    }

    /// @notice helper function to swap the ETHX in balance to underlying WETH
    function _swapEthX(uint256 amountIn) internal returns (uint256) {
        if (amountIn < minSingleTrade) return 0;
        return router.exactInputSingle(
            IUniswapV3Router.ExactInputSingleParams({
                tokenIn: ethX,
                tokenOut: underlyingAsset,
                fee: 500,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL VIEW FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////
    /// @notice returns ETHX balance
    function _ethXBalance() internal view returns (uint256) {
        return ethX.balanceOf(address(this));
    }
}
