// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { BaseSommelierStrategy, IMaxApyVault, SafeTransferLib } from "src/strategies/base/BaseSommelierStrategy.sol";
import { IWETH } from "src/interfaces/IWETH.sol";
import { ICellar } from "src/interfaces/ICellar.sol";

import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import {
    IBalancerVault,
    IBalancerStablePool,
    FundManagement,
    SingleSwap,
    JoinPoolRequest,
    ExitPoolRequest,
    SwapKind,
    JoinKind,
    ExitKind,
    IAsset
} from "src/interfaces/IBalancer.sol";

import { RETH_MAINNET, BALANCER_VAULT_MAINNET } from "src/helpers/AddressBook.sol";

/// @title SommelierTurboDivEthStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-rEth-acc/blob/master/contracts/strategies.sol
/// @notice `SommelierTurboDivEthStrategy` supplies an underlying token into a generic Sommelier Vault,
/// earning the Sommelier Vault's yield
contract SommelierTurboDivEthStrategy is BaseSommelierStrategy {
    using SafeTransferLib for address;

    ////////////////////////////////////////////////////////////////
    ///                         CONSTANTS                        ///
    ////////////////////////////////////////////////////////////////

    /// @notice Ethereum mainnet's rEth Token
    address public constant rEth = RETH_MAINNET;

    /// @notice Ethereum mainnet's Balancer rEth-WETH pool
    address public constant balancerLpPool = 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276;

    /// @notice Balancer pool id
    bytes32 public constant balancerPoolId = 0x1e19cf2d73a72ef1332c882f20534b6519be0276000200000000000000000112;

    /// @notice Univarsal Balancer Vault
    IBalancerVault public constant balancerVault = IBalancerVault(BALANCER_VAULT_MAINNET);

    ////////////////////////////////////////////////////////////////
    ///                     INITIALIZATION                       ///
    ////////////////////////////////////////////////////////////////
    constructor() initializer { }

    /// @notice The Balancer pool id for the underlying LP token
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

        /// Approve pool to perform swaps
        underlyingAsset.safeApprove(address(balancerVault), type(uint256).max);
        rEth.safeApprove(address(balancerVault), type(uint256).max);
        /// Approve Cellar Vault to transfer underlying
        balancerLpPool.safeApprove(address(_cellar), type(uint256).max);
        minSingleTrade = 1e4;
        maxSingleTrade = 10_000 * 1e18;
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
        uint256 underlyingBalance = _underlyingBalance();
        if (underlyingBalance < amountNeeded) {
            // calculate the amount of LP tokens to withdraw
            uint256 lpToWithdraw = ((amountNeeded - underlyingBalance) * 1e18 / _lpPrice()) * 101 / 100; // account
                // pessimistically
            uint256 burntShares = cellar.withdraw(lpToWithdraw, address(this), address(this));
            _exitPool(lpToWithdraw);
            // use sub zero because shares could be fewer than expected and underflow
            uint256 lpTokens = cellar.convertToAssets(burntShares);
            loss = _sub0(amountNeeded - underlyingBalance, _lpValue(lpTokens));
        }
        underlyingAsset.safeTransfer(address(vault), amountNeeded);
        // Note: Reinvest anything leftover on next `harvest`
        _snapshotEstimatedTotalAssets();
    }

    /////////////////////////////////////////////////////////////////
    ///                    VIEW FUNCTIONS                        ///
    ////////////////////////////////////////////////////////////////
    /// @notice This function is meant to be called from the vault
    /// @dev calculates the estimated @param requestedAmount the vault has to request to this strategy
    /// in order to actually get @param liquidatedAmount assets when calling `previewWithdraw`
    /// @return requestedAmount
    function previewLiquidateExact(uint256 liquidatedAmount) public view override returns (uint256 requestedAmount) {
        uint256 underlyingBalance = _underlyingBalance();
        uint256 loss;
        if (underlyingBalance < liquidatedAmount) {
            // calculate the amount of LP tokens to withdraw
            uint256 lpToWithdraw = ((liquidatedAmount - underlyingBalance) * 1e18 / _lpPrice()) * 101 / 100; // account
                // pessimistically
            uint256 burntShares = cellar.previewWithdraw(lpToWithdraw);
            // use sub zero because shares could be fewer than expected and underflow
            uint256 lpTokens = cellar.convertToAssets(burntShares);
            loss = _sub0(liquidatedAmount - underlyingBalance, _lpValue(lpTokens));
        }
        requestedAmount = liquidatedAmount + loss;
    }

    /// @notice Returns the max amount of assets that the strategy can withdraw after losses
    function maxLiquidate() public view override returns (uint256) {
        return _estimatedTotalAssets();
    }

    /// @notice Returns the max amount of assets that the strategy can liquidate, before realizing losses
    function maxLiquidateExact() public view override returns (uint256) {
        return _underlyingBalance() + (_lpValue(cellar.maxWithdraw(address(this)))) * 99 / 100;
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL CORE FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////
    /// @notice Invests `amount` of underlying, depositing it in the Cellar Vault
    /// @param amount The amount of underlying to be deposited in the vault
    /// @param minOutputAfterInvestment minimum expected output after `_invest()` (designated in Cellar receipt tokens)
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
        // Dont't do anything if cellar is paused or shutdown
        if (cellar.isShutdown() || cellar.isPaused()) return 0;

        uint256 underlyingBalance = _underlyingBalance();
        if (amount > underlyingBalance) revert NotEnoughFundsToInvest();

        // 1. Add liquidity to the Balancer pool
        uint256 mintedLpTokens = _joinPool(amount);

        // 2. Deposit into the Sommelier cellar
        uint256 shares = cellar.deposit(mintedLpTokens, address(this));

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
        // 1. Exit cellar
        uint256 lpWithdrawn = cellar.redeem(shares, address(this), address(this));
        // 2. Withdraw from Balancer LP pool
        withdrawn = _exitPool(lpWithdrawn);
        emit Divested(address(this), shares, withdrawn);
    }

    /// @notice Liquidate up to `amountNeeded` of MaxApy Vault's `underlyingAsset` of this strategy's positions,
    /// irregardless of slippage. Any excess will be re-invested with `_adjustPosition()`.
    /// @dev This function should return the amount of MaxApy Vault's `underlyingAsset` tokens made available by the
    /// liquidation. If there is a difference between `amountNeeded` and `liquidatedAmount`, `loss` indicates whether
    /// the
    /// difference is due to a realized loss, or if there is some other sitution at play
    /// (e.g. locked funds) where the amount made available is less than what is needed.
    /// NOTE: The invariant `liquidatedAmount + loss <= amountNeeded` should always be maintained
    /// @param amountNeeded amount of MaxApy Vault's `underlyingAsset` needed to be liquidated
    /// @return liquidatedAmount the actual liquidated amount
    /// @return loss difference between the expected amount needed to reach `amountNeeded` and the actual liquidated
    /// amount
    function _liquidatePosition(uint256 amountNeeded)
        internal
        override
        returns (uint256 liquidatedAmount, uint256 loss)
    {
        uint256 underlyingBalance = _underlyingBalance();
        // if cellar is paused dont liquidate, skips revert
        if (cellar.isPaused()) {
            uint256 amountOut = Math.min(underlyingBalance, amountNeeded);
            return (amountOut, amountNeeded - amountOut);
        }

        // If underlying balance currently held by strategy is not enough to cover
        // the requested amount, we divest from the Cellar Vault
        if (underlyingBalance < amountNeeded) {
            uint256 amountToWithdraw;
            unchecked {
                amountToWithdraw = amountNeeded - underlyingBalance;
            }
            uint256 shares = _sharesForAmount(amountToWithdraw);
            uint256 withdrawn = _divest(shares);
            assembly {
                // if withdrawn < amountToWithdraw
                if lt(withdrawn, amountToWithdraw) { loss := sub(amountToWithdraw, withdrawn) }
            }
        }
        // liquidatedAmount = amountNeeded - loss;
        assembly {
            liquidatedAmount := sub(amountNeeded, loss)
        }
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL VIEW FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////

    /// @notice Determines the current value of `shares`.
    /// @return _assets the estimated amount of underlying computed from shares `shares`
    function _shareValue(uint256 shares) internal view override returns (uint256 _assets) {
        uint256 lpTokens = cellar.convertToAssets(shares);
        // account pessimistically
        _assets = _lpValue(lpTokens) * 998 / 1000;
    }

    /// @notice Determines how many shares depositor of `amount` of underlying would receive.
    /// @return _shares the estimated amount of shares computed in exchange for underlying `amount`
    function _sharesForAmount(uint256 amount) internal view override returns (uint256 _shares) {
        amount = amount * 1e18 / _lpPrice();
        assembly {
            // return cellar.convertToShares(amount);
            mstore(0x00, 0xc6e6f592)
            mstore(0x20, amount)
            if iszero(staticcall(gas(), sload(cellar.slot), 0x1c, 0x24, 0x00, 0x20)) { revert(0x00, 0x04) }
            _shares := mload(0x00)
        }
        // account pessimistically
        _shares = _shares * 998 / 1000;
    }

    /// @notice Returns the current strategy's amount of Cellar vault shares
    /// @return _balance balance the strategy's balance of Cellar vault shares
    function _shareBalance() internal view override returns (uint256 _balance) {
        assembly {
            // return cellar.balanceOf(address(this));
            mstore(0x00, 0x70a08231)
            mstore(0x20, address())
            if iszero(staticcall(gas(), sload(cellar.slot), 0x1c, 0x24, 0x00, 0x20)) { revert(0x00, 0x04) }
            _balance := mload(0x00)
        }
    }

    /// @notice Determines how many lp tokens depositor of `amount` of underlying would receive.
    /// @dev Some loss of precision is occured, but it is not critical as this is only an underestimation of
    /// the actual assets, and profit will be later accounted for.
    /// @return returns the estimated amount of lp tokens computed in exchange for underlying `amount`
    function _lpValue(uint256 amount) internal view returns (uint256) {
        return amount * _lpPrice() / 1e18;
    }

    /// @notice Returns the estimated price for the strategy's Balancer LP token
    /// @return returns the estimated lp token price
    function _lpPrice() internal view returns (uint256) {
        return IBalancerStablePool(balancerLpPool).getRate();
    }

    /// @notice returns the Balancer LP token balance of the contract
    function _lpBalance() internal view returns (uint256) {
        return balancerLpPool.balanceOf(address(this));
    }

    /// @notice Returns the real time estimation of the value in assets held by the strategy
    /// @return the strategy's total assets(idle + investment positions)
    function _estimatedTotalAssets() internal view virtual override returns (uint256) {
        return _underlyingBalance() + _shareValue(_shareBalance());
    }

    /// @notice Get the underlying Balancer stable pair pool's tokens in the right order
    function _getAssets() internal view returns (IAsset[] memory) {
        IAsset[] memory _assets = new IAsset[](2);
        _assets[0] = IAsset(rEth);
        _assets[1] = IAsset(underlyingAsset);
        return _assets;
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL HELPER FUNCTIONS                ///
    ////////////////////////////////////////////////////////////////

    /// @notice Add liqudity to the Balancer stable LP pool with a single token deposit(WETH)
    /// @return the minted LP tokens after adding the liquidity
    function _joinPool(uint256 _wethIn) internal returns (uint256) {
        IAsset[] memory _assets = _getAssets();

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = 0;
        amountsIn[1] = _wethIn;

        JoinPoolRequest memory joinParams = JoinPoolRequest({
            assets: _assets,
            maxAmountsIn: amountsIn,
            userData: abi.encode(JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, amountsIn, 0),
            fromInternalBalance: false
        });

        uint256 lpBalalanceBefore = _lpBalance();

        balancerVault.joinPool(balancerPoolId, address(this), address(this), joinParams);

        return _lpBalance() - lpBalalanceBefore;
    }

    /// @notice Remove liqudity from the Balancer stable LP pool as single token(WETH)
    /// @return the amount of withdrawn WETH
    function _exitPool(uint256 _lpTokens) internal returns (uint256) {
        IAsset[] memory _assets = _getAssets();
        uint256[] memory _minAmountsOut = new uint256[](2);

        ExitPoolRequest memory exitRequest = ExitPoolRequest({
            assets: _assets,
            minAmountsOut: _minAmountsOut,
            userData: abi.encode(ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, _lpTokens, 1),
            toInternalBalance: false
        });
        uint256 balanceBefore = underlyingAsset.balanceOf(address(this));
        balancerVault.exitPool(balancerPoolId, address(this), address(this), exitRequest);
        return underlyingAsset.balanceOf(address(this)) - balanceBefore;
    }
}
