// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {
    BaseYearnV3Strategy, SafeTransferLib, IMaxApyVault, IYVaultV3
} from "src/strategies/base/BaseYearnV3Strategy.sol";
import { IStakingRewardsMulti } from "src/interfaces/IStakingRewardsMulti.sol";
import { IUniswapV3Router as IRouter } from "src/interfaces/IUniswap.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { AJNA_MAINNET, UNISWAP_V3_ROUTER_MAINNET } from "src/helpers/AddressBook.sol";

/// @title YearnAjnaWETHStakingStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/strategies.sol
/// @notice `YearnAjnaWETHStakingStrategy` supplies an underlying token into a generic Yearn V3 Vault,
/// and stakes the vault shares for boosted AJNA rewards
contract YearnAjnaWETHStakingStrategy is BaseYearnV3Strategy {
    using SafeTransferLib for address;

    ////////////////////////////////////////////////////////////////
    ///                         CONSTANTS                        ///
    ////////////////////////////////////////////////////////////////

    /// @notice Ethereum mainnet's Ajna Token
    address public constant ajna = AJNA_MAINNET;
    /// @notice Router to perform AJNA-WETH swaps
    IRouter public constant router = IRouter(UNISWAP_V3_ROUTER_MAINNET);

    /// @notice The staking contract to stake the vault shares
    IStakingRewardsMulti public constant yearnStakingRewards =
        IStakingRewardsMulti(0x0Ed535037c013c3628512980C169Ed59Eb805B49);

    ////////////////////////////////////////////////////////////////
    ///            STRATEGY GLOBAL STATE VARIABLES               ///
    ////////////////////////////////////////////////////////////////
    /// @notice Minimun trade size for AJNA token
    uint256 public minSwapAjna;

    ////////////////////////////////////////////////////////////////
    ///                     INITIALIZATION                       ///
    ////////////////////////////////////////////////////////////////

    constructor() initializer { }

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
        IYVaultV3 _yVault
    )
        public
        override
        initializer
    {
        __BaseStrategy_init(_vault, _keepers, _strategyName, _strategist);
        yVault = _yVault;

        /// Perform needed approvals
        underlyingAsset.safeApprove(address(_yVault), type(uint256).max);
        ajna.safeApprove(address(router), type(uint256).max);
        address(_yVault).safeApprove(address(yearnStakingRewards), type(uint256).max);

        minSingleTrade = 1e4;
        maxSingleTrade = 1000e18;

        minSwapAjna = 1e18;
    }

    /////////////////////////////////////////////////////////////////
    ///                    CORE LOGIC                             ///
    ////////////////////////////////////////////////////////////////
    /// @notice Withdraws exactly `amountNeeded` to `vault`.
    /// @dev This may only be called by the respective Vault.
    /// @param amountNeeded How much `underlyingAsset` to withdraw.
    /// @return loss Any realized losses
    function liquidateExact(uint256 amountNeeded) external override checkRoles(VAULT_ROLE) returns (uint256 loss) {
        uint256 underlyingBalance = _underlyingBalance();
        if (underlyingBalance < amountNeeded) {
            uint256 amountToWithdraw;
            unchecked {
                amountToWithdraw = amountNeeded - underlyingBalance;
            }
            uint256 neededVaultShares = yVault.previewWithdraw(amountToWithdraw);
            yearnStakingRewards.withdraw(neededVaultShares);
            uint256 burntShares = yVault.withdraw(amountToWithdraw, address(this), address(this));
            loss = _sub0(_shareValue(burntShares), amountToWithdraw);
        }
        underlyingAsset.safeTransfer(address(vault), amountNeeded);
        // In case all shares were not burnt reinvest them
        uint256 sharesLeft = yVault.balanceOf(address(this));
        if (sharesLeft != 0) {
            yearnStakingRewards.stake(sharesLeft);
        }

        // Note: Reinvest anything leftover on next `harvest`
        _snapshotEstimatedTotalAssets();
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL CORE FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////
    /// @notice unwind extra staking rewards before preparing return
    function _beforePrepareReturn() internal override {
        IStakingRewardsMulti rewardPool = yearnStakingRewards;
        _unwindRewards(rewardPool);
    }

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

        uint256 shares = yVault.deposit(amount, address(this));

        assembly ("memory-safe") {
            // if (shares < minOutputAfterInvestment)
            if lt(shares, minOutputAfterInvestment) {
                // throw the `MinOutputAmountNotReached` error
                mstore(0x00, 0xf7c67a48)
                revert(0x1c, 0x04)
            }
        }

        depositedAmount = _shareValue(shares);

        yearnStakingRewards.stake(shares);

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
        yearnStakingRewards.withdraw(shares);
        withdrawn = yVault.redeem(shares, address(this), address(this));
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
        // If underlying balance currently held by strategy is not enough to cover
        // the requested amount, we divest from the Yearn Vault
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

    /// @notice Claims rewards, converting them to `underlyingAsset`.
    /// @dev MinOutputAmounts are left as 0 and properly asserted globally on `harvest()`.
    function _unwindRewards(IStakingRewardsMulti _yearnStakingRewards) internal {
        // Claim Ajna rewards
        _yearnStakingRewards.getReward();

        // Exchange Ajna <> WETH
        uint256 ajnaBalance = _ajnaBalance();
        if (ajnaBalance > minSwapAjna) {
            router.exactInputSingle(
                IRouter.ExactInputSingleParams({
                    tokenIn: ajna,
                    tokenOut: underlyingAsset,
                    fee: 10_000,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: ajnaBalance,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        }
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL VIEW FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////

    /// @notice Returns the AJNA token balane of the strategy
    /// @return The amount of AJNA tokens held by the current contract
    function _ajnaBalance() internal view returns (uint256) {
        return ajna.balanceOf(address(this));
    }

    /// @notice Returns the current strategy's amount of yearn vault shares
    /// @return _balance balance the strategy's balance of yearn vault shares
    function _shareBalance() internal view override returns (uint256 _balance) {
        return yearnStakingRewards.balanceOf(address(this));
    }
}
