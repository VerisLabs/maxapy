// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { AJNA_MAINNET, UNISWAP_V3_ROUTER_MAINNET, WETH_MAINNET } from "src/helpers/AddressBook.sol";
import { CURVE_3POOL_POOL_MAINNET, DAI_MAINNET } from "src/helpers/AddressBook.sol";
import { ICurveTriPool } from "src/interfaces/ICurve.sol";
import { IStakingRewardsMulti } from "src/interfaces/IStakingRewardsMulti.sol";
import { IUniswapV3Router as IRouter } from "src/interfaces/IUniswap.sol";
import {
    BaseYearnV3Strategy,
    IMaxApyVault,
    IYVaultV3,
    Math,
    SafeTransferLib
} from "src/strategies/base/BaseYearnV3Strategy.sol";

/// @title YearnAjnaDAIStakingStrategy
/// @author Adapted from https://github.com/Grandthrax/yearn-steth-acc/blob/master/contracts/strategies.sol
/// @notice `YearnAjnaDAIStakingStrategy` supplies an underlying token into a generic Yearn V3 Vault,
/// and stakes the vault shares for boosted AJNA rewards
contract YearnAjnaDAIStakingStrategy is BaseYearnV3Strategy {
    using SafeTransferLib for address;

    ////////////////////////////////////////////////////////////////
    ///                         CONSTANTS                        ///
    ////////////////////////////////////////////////////////////////

    /// @notice Ethereum mainnet's Ajna Token
    address public constant ajna = AJNA_MAINNET;
    /// @notice Ethereum mainnet's WETHToken
    address public constant weth = WETH_MAINNET;
    /// @notice Router to perform AJNA-WETH-DAI swaps
    IRouter public constant router = IRouter(UNISWAP_V3_ROUTER_MAINNET);

    /// @notice The staking contract to stake the vault shares
    IStakingRewardsMulti public constant yearnStakingRewards =
        IStakingRewardsMulti(0x54C6b2b293297e65b1d163C3E8dbc45338bfE443);

    ICurveTriPool public constant triPool = ICurveTriPool(CURVE_3POOL_POOL_MAINNET);
    address constant dai = DAI_MAINNET;

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
        dai.safeApprove(address(_yVault), type(uint256).max);
        ajna.safeApprove(address(router), type(uint256).max);
        address(_yVault).safeApprove(address(yearnStakingRewards), type(uint256).max);
        underlyingAsset.safeApprove(address(triPool), type(uint256).max);
        dai.safeApprove(address(triPool), type(uint256).max);

        minSingleTrade = 1e6;
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
            amountToWithdraw = Math.mulDiv(amountNeeded * 1e12, 101, 100);
            uint256 neededVaultShares = yVault.previewWithdraw(amountToWithdraw);
            yearnStakingRewards.withdraw(neededVaultShares);
            uint256 burntShares = yVault.withdraw(amountToWithdraw, address(this), address(this));
            loss = _sub0(_shareValue(burntShares), amountToWithdraw);
        }
        uint256 daiBalance = dai.balanceOf(address(this));

        triPool.exchange(0, 1, daiBalance, 0);

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
    /// @notice unwind rewards before preparing return
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

        uint256 balanceBefore = dai.balanceOf(address(this));

        uint256 scaledAmount = amount * 1e12;
        uint256 minAmount = (Math.min(scaledAmount, maxSingleTrade));
        // Scale back down to 6 decimals
        amount = minAmount / 1e12;

        assembly {
            // Emit the `Invested` event
            mstore(0x00, amount)
            log2(0x00, 0x20, _INVESTED_EVENT_SIGNATURE, address())
        }

        // Swap underlying to DAI
        triPool.exchange(1, 0, amount, 0);

        amount = dai.balanceOf(address(this)) - balanceBefore;

        uint256 shares = yVault.deposit(amount, address(this));

        assembly ("memory-safe") {
            // if (shares < minOutputAfterInvestment)
            if lt(shares, minOutputAfterInvestment) {
                // throw the `MinOutputAmountNotReached` error
                mstore(0x00, 0xf7c67a48)
                revert(0x1c, 0x04)
            }
        }

        yearnStakingRewards.stake(shares);

        depositedAmount = _shareValue(shares);
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
        uint256 balanceBefore = underlyingAsset.balanceOf(address(this));

        // Swap DAI to underlying
        triPool.exchange(0, 1, withdrawn, 0);

        withdrawn = underlyingAsset.balanceOf(address(this)) - balanceBefore;
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

    /// @notice Liquidates everything and returns the amount that got freed.
    /// @dev This function is used during emergency exit instead of `_prepareReturn()` to
    /// liquidate all of the Strategy's positions back to the MaxApy Vault.
    function _liquidateAllPositions() internal override returns (uint256 amountFreed) {
        IStakingRewardsMulti rewardPool = yearnStakingRewards;
        _unwindRewards(rewardPool);
        _divest(_shareBalance());
        amountFreed = _underlyingBalance();
    }

    /// @notice Claims rewards, converting them to `underlyingAsset`.
    /// @dev MinOutputAmounts are left as 0 and properly asserted globally on `harvest()`.
    function _unwindRewards(IStakingRewardsMulti _yearnStakingRewards) internal {
        // Claim Ajna rewards
        _yearnStakingRewards.getReward();

        // Exchange Ajna <> DAI
        uint256 ajnaBalance = _ajnaBalance();
        if (ajnaBalance > minSwapAjna) {
            router.exactInputSingle(
                IRouter.ExactInputSingleParams({
                    tokenIn: ajna,
                    tokenOut: underlyingAsset,
                    fee: 3000,
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

    /// @notice Determines the current value of `shares`.
    /// @dev if sqrt(yVault.totalAssets()) >>> 1e39, this could potentially revert
    /// @return returns the estimated amount of underlying computed from shares `shares`
    function _shareValue(uint256 shares) internal view override returns (uint256) {
        uint256 sharesValue = super._shareValue(shares);
        if (sharesValue > 0) {
            return triPool.get_dy(0, 1, sharesValue);
        }
    }

    /// @notice Determines how many shares depositor of `amount` of underlying would receive.
    /// @return shares returns the estimated amount of shares computed in exchange for the underlying `amount`
    function _sharesForAmount(uint256 amount) internal view override returns (uint256 shares) {
        if (amount > 0) {
            amount = triPool.get_dy(1, 0, amount);
        }
        return super._sharesForAmount(amount);
    }

    /// @notice This function is meant to be called from the vault
    /// @dev calculates estimated the @param requestedAmount the vault has to request to this strategy
    /// in order to actually get @param liquidatedAmount assets when calling `previewWithdraw`
    /// @return requestedAmount
    function previewLiquidateExact(uint256 liquidatedAmount)
        public
        view
        virtual
        override
        returns (uint256 requestedAmount)
    {
        uint256 underlyingBalance = _underlyingBalance();
        if (underlyingBalance < liquidatedAmount) {
            unchecked {
                liquidatedAmount = liquidatedAmount - underlyingBalance;
            }
            requestedAmount = _shareValue(yVault.previewWithdraw(Math.mulDiv(liquidatedAmount * 1e12, 101, 100)));
        }
        return requestedAmount + underlyingBalance;
    }

    /// @notice Returns the max amount of assets that the strategy can liquidate, before realizing losses
    function maxLiquidateExact() public view virtual override returns (uint256) {
        // make sure it doesnt revert when increaseing it 1% in the withdraw
        return previewLiquidate(estimatedTotalAssets()) * 99 / 100;
    }
}
