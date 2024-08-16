// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {
    BaseSommelierStrategy,
    ICellar,
    IWETH,
    IMaxApyVault,
    SafeTransferLib
} from "src/strategies/base/BaseSommelierStrategy.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { ICurveLpPool } from "src/interfaces/ICurve.sol";
import { STETH_MAINNET, CURVE_ETH_STETH_POOL_MAINNET } from "src/helpers/AddressBook.sol";

/// @title SommelierStEthDepositTurboStEthStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/strategies.sol
/// @notice `SommelierStEthDepositTurboStEthStrategy` supplies an underlying token into a generic Sommelier Vault,
/// earning the Sommelier Vault's yield
contract SommelierStEthDepositTurboStEthStrategy is BaseSommelierStrategy {
    using SafeTransferLib for address;

    ////////////////////////////////////////////////////////////////
    ///                         CONSTANTS                        ///
    ////////////////////////////////////////////////////////////////

    /// @notice Ethereum mainnet's StETH Token
    address public constant stEth = STETH_MAINNET;

    ////////////////////////////////////////////////////////////////
    ///            STRATEGY GLOBAL STATE VARIABLES               ///
    ////////////////////////////////////////////////////////////////
    /// @notice The Curve pool
    ICurveLpPool public constant pool = ICurveLpPool(CURVE_ETH_STETH_POOL_MAINNET);

    ////////////////////////////////////////////////////////////////
    ///                     INITIALIZATION                       ///
    ////////////////////////////////////////////////////////////////
    constructor() initializer { }

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

        /// Approve pool to perform swaps
        underlyingAsset.safeApprove(address(pool), type(uint256).max);
        stEth.safeApprove(address(pool), type(uint256).max);
        /// Approve Cellar Vault to transfer underlying
        stEth.safeApprove(address(_cellar), type(uint256).max);
        maxSingleTrade = 1000 * 1e18;
        minSingleTrade = 1e4;
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
            uint256 withdrawn = cellar.previewRedeem(shares);
            withdrawn = pool.get_dy(1, 0, withdrawn);
            if (withdrawn < amountToWithdraw) loss = amountToWithdraw - withdrawn;
        }
        liquidatedAmount = requestedAmount - loss;
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

    /// @notice Performs any adjustments to the core position(s) of this Strategy given
    /// what change the MaxApy Vault made in the "investable capital" available to the
    /// Strategy.
    /// @dev Note that all "free capital" (capital not invested) in the Strategy after the report
    /// was made is available for reinvestment. This number could be 0, and this scenario should be handled accordingly.
    function _adjustPosition(uint256, uint256 minOutputAfterInvestment) internal override {
        uint256 toInvest = _underlyingBalance();
        if (toInvest > minSingleTrade) {
            toInvest = Math.min(maxSingleTrade, toInvest);
            _invest(toInvest, minOutputAfterInvestment);
        }
    }

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
        uint256 maxDeposit = cellar.maxDeposit(address(this));
        amount = Math.min(amount, maxDeposit);

        uint256 underlyingBalance = _underlyingBalance();
        if (amount > underlyingBalance) revert NotEnoughFundsToInvest();

        IWETH(underlyingAsset).withdraw(amount);

        uint256 stEthReceived = pool.exchange{ value: amount }(0, 1, amount, 0);

        uint256 shares = cellar.deposit(stEthReceived, address(this));

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
        uint256 stEthWithdrawn = cellar.redeem(shares, address(this), address(this));
        withdrawn = pool.exchange(1, 0, stEthWithdrawn, 0);
        IWETH(underlyingAsset).deposit{ value: withdrawn }();
        emit Divested(address(this), shares, withdrawn);
    }

    /// @notice Allow to receive native assets
    receive() external payable { }
}
