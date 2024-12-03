// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { SafeCastLib } from "solady/utils/SafeCastLib.sol";
import { IComet } from "src/interfaces/CompoundV2/IComet.sol";
import { ICometRewards, RewardOwed } from "src/interfaces/CompoundV2/ICometRewards.sol";
import { ICurveTriPool } from "src/interfaces/ICurve.sol";
import { IUniswapV3Router as IRouter } from "src/interfaces/IUniswap.sol";
import {
    BaseCompoundV3Strategy,
    IERC20Metadata,
    IMaxApyVault,
    SafeTransferLib
} from "src/strategies/base/BaseCompoundV3Strategy.sol";

import {
    COMP_MAINNET,
    CURVE_3POOL_POOL_MAINNET,
    UNISWAP_V3_COMP_WETH_POOL_MAINNET,
    UNISWAP_V3_WETH_USDC_POOL_MAINNET,
    USDC_MAINNET,
    USDT_MAINNET,
    USDT_MAINNET,
    WETH_MAINNET
} from "src/helpers/AddressBook.sol";

contract CompoundV3USDTStrategy is BaseCompoundV3Strategy {
    using SafeTransferLib for address;
    using SafeCastLib for uint256;
    using SafeCastLib for int104;

    ////////////////////////////////////////////////////////////////
    ///                        CONSTANTS                         ///
    ////////////////////////////////////////////////////////////////
    ICurveTriPool public constant triPool = ICurveTriPool(CURVE_3POOL_POOL_MAINNET);
    address constant usdt = USDT_MAINNET;

    /// @notice Router to perform COMP-WETH-USDT swaps
    IRouter public router;
    /// @notice Address of Uniswap V3 COMP-WETH pool
    address public constant poolA = UNISWAP_V3_COMP_WETH_POOL_MAINNET;
    /// @notice Address of Uniswap V3 WETH-USDC pool
    address public constant poolB = UNISWAP_V3_WETH_USDC_POOL_MAINNET;

    ////////////////////////////////////////////////////////////////
    ///                     INITIALIZATION                       ///
    ////////////////////////////////////////////////////////////////
    constructor() initializer { }

    /// @notice Initialize the Strategy
    /// @param _vault The address of the MaxApy Vault associated to the strategy
    /// @param _keepers The addresses of the keepers to be added as valid keepers to the strategy
    /// @param _strategyName the name of the strategy
    /// @param _router The router address to perform swaps
    function initialize(
        IMaxApyVault _vault,
        address[] calldata _keepers,
        bytes32 _strategyName,
        address _strategist,
        IComet _comet,
        ICometRewards _cometRewards,
        address _tokenSupplyAddress,
        IRouter _router
    )
        public
        virtual
        override
        initializer
    {
        __BaseStrategy_init(_vault, _keepers, _strategyName, _strategist);
        comet = _comet;
        cometRewards = _cometRewards;
        tokenSupplyAddress = _tokenSupplyAddress;

        tokenSupplyAddress.safeApprove(address(comet), type(uint256).max);
        underlyingAsset.safeApprove(address(triPool), type(uint256).max);
        usdt.safeApprove(address(triPool), type(uint256).max);

        // Set router
        router = _router;

        COMP_MAINNET.safeApprove(address(router), type(uint256).max);

        /// Mininmum single trade is 0.01 token units
        minSingleTrade = 10 ** IERC20Metadata(underlyingAsset).decimals() / 100;

        /// Unlimited max single trade by default
        maxSingleTrade = type(uint256).max;
    }

    /// @notice Sets the new router
    /// @dev Approval for COMP will be granted to the new router if it was not already granted
    /// @param _newRouter The new router address
    function setRouter(address _newRouter) external checkRoles(ADMIN_ROLE) {
        // Remove previous router allowance
        COMP_MAINNET.safeApprove(address(router), 0);

        // Set new router allowance
        COMP_MAINNET.safeApprove(address(_newRouter), type(uint256).max);

        assembly ("memory-safe") {
            sstore(router.slot, _newRouter) // set the new router in storage

            // Emit the `RouterUpdated` event
            mstore(0x00, _newRouter)
            log1(0x00, 0x20, _ROUTER_UPDATED_EVENT_SIGNATURE)
        }
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL CORE FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////

    /// @notice Invests `amount` of underlying, depositing it in the Compound Vault
    /// @param amount The amount of underlying to be deposited in the vault
    /// @param minOutputAfterInvestment minimum expected output after `_invest()` (designated in Compound receipt
    /// tokens)
    /// @return depositedAmount The amount of base token of compound pool invested, in terms of USDT
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

        uint256 baseScale = comet.baseScale();
        uint256 minForRewards = comet.baseMinForRewards();

        // check if it's the first ever investment in compound V2 USDT
        if (_totalInvestedBaseAsset() == 0 && (_convertUsdcToBaseAsset(amount) * baseScale) < minForRewards) {
            assembly ("memory-safe") {
                // throw the `InitialInvestmentTooLow` error
                mstore(0x00, 0xbffb2b0e)
                revert(0x1c, 0x04)
            }
        }

        uint256 balanceBefore = usdt.balanceOf(address(this));
        // Swap underlying USDC to USDT
        triPool.exchange(1, 2, amount, 1);
        uint256 amountUsdt = usdt.balanceOf(address(this)) - balanceBefore;
        comet.supply(tokenSupplyAddress, amountUsdt);

        depositedAmount = comet.balanceOf(address(this));

        emit Invested(address(this), amount);
    }

    /// @notice Divests amount `amount` from Compound Vault
    /// Note that divesting from Compound could potentially cause loss (set to 0.01% as default in
    /// the Vault implementation), so the divested amount might actually be different from
    /// the requested `amount` to divest
    /// @dev care should be taken, as the `amount` parameter is *not* in terms of underlying,
    /// but in terms of base asset of Compound pool
    /// @return withdrawn the total amount divested, in terms of underlying asset
    function _divest(
        uint256 amount,
        uint256 rewardstoWithdraw,
        bool reinvestRemainingRewards
    )
        internal
        virtual
        override
        returns (uint256 withdrawn)
    {
        uint256 _before = tokenSupplyAddress.balanceOf(address(this));

        comet.withdraw(tokenSupplyAddress, amount);
        uint256 _after = tokenSupplyAddress.balanceOf(address(this));

        uint256 tokenDivested = _after - _before;

        uint256 balanceBefore = USDC_MAINNET.balanceOf(address(this));

        // Swap underlying USDT to USDC
        triPool.exchange(2, 1, tokenDivested, 1);
        uint256 amountUsdc = USDC_MAINNET.balanceOf(address(this)) - balanceBefore;

        withdrawn = amountUsdc + _unwindRewards(rewardstoWithdraw, reinvestRemainingRewards);

        emit Divested(address(this), amount, withdrawn);
    }

    /// @notice Claims rewards, converting them to `underlyingAsset`.
    /// @dev MinOutputAmounts are left as 0 and properly asserted globally on `harvest()`.
    function _unwindRewards(
        uint256 rewardstoWithdraw,
        bool reinvestRemainingRewards
    )
        internal
        virtual
        override
        returns (uint256 withdrawn)
    {
        RewardOwed memory reward = cometRewards.getRewardOwed(address(comet), address(this));

        uint256 _rewardBefore = reward.token.balanceOf(address(this));
        cometRewards.claim(address(comet), address(this), true);
        uint256 _rewardAfter = reward.token.balanceOf(address(this));

        if (_rewardAfter - _rewardBefore > 0) {
            if (rewardstoWithdraw > 0) {
                uint256 usdcAmount = swapTokens(COMP_MAINNET, WETH_MAINNET, USDC_MAINNET, rewardstoWithdraw);
                withdrawn = usdcAmount;
                _rewardAfter = reward.token.balanceOf(address(this));
            }

            if (reinvestRemainingRewards) {
                uint256 usdtAmount = swapTokens(COMP_MAINNET, WETH_MAINNET, USDT_MAINNET, _rewardAfter - _rewardBefore);
                comet.supply(tokenSupplyAddress, usdtAmount);
            } else {
                uint256 usdcAmount = swapTokens(COMP_MAINNET, WETH_MAINNET, USDC_MAINNET, _rewardAfter - _rewardBefore);
                withdrawn = usdcAmount;
            }
        }
    }

    function swapTokens(
        address tokenIn,
        address intermediaryToken,
        address tokenOut,
        uint256 amount
    )
        internal
        returns (uint256)
    {
        bytes memory path = abi.encodePacked(
            tokenIn,
            uint24(3000), // 0.3%
            intermediaryToken,
            uint24(3000), // 0.3%
            tokenOut
        );

        uint256 amountOut = router.exactInput(
            IRouter.ExactInputParams({
                path: path,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amount,
                amountOutMinimum: 0
            })
        );

        return amountOut;
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
        uint256 loss;
        uint256 underlyingBalance = _underlyingBalance();

        // If underlying balance currently held by strategy is not enough to cover
        // the requested amount, we divest from the Compound Vault
        if (underlyingBalance < requestedAmount) {
            uint256 amountToWithdraw;
            unchecked {
                amountToWithdraw = requestedAmount - underlyingBalance;
            }

            uint256 totalInvestedValue = _totalInvestedValue();

            // If underlying assest invested currently by strategy is not enough to cover
            // the requested amount, we divest from the Compound rewards
            if (amountToWithdraw > totalInvestedValue) {
                unchecked {
                    amountToWithdraw = amountToWithdraw - totalInvestedValue;
                }
                uint256 rewardsUSDC = _accruedRewardValue();

                assembly {
                    // if withdrawn < amountToWithdraw
                    if gt(amountToWithdraw, rewardsUSDC) { loss := sub(amountToWithdraw, rewardsUSDC) }
                }
            }
        }
        liquidatedAmount = (requestedAmount - loss) * 996 / 1000;
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL VIEW FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////

    function _accruedRewardValue() public view override returns (uint256) {
        uint256 reward = uint256(comet.userBasic(address(this)).baseTrackingAccrued);

        uint256 rewardWETH = _estimateAmountOut(COMP_MAINNET, WETH_MAINNET, reward.toUint128(), poolA, 1800);

        uint256 rewardsUSDC = _estimateAmountOut(WETH_MAINNET, USDC_MAINNET, rewardWETH.toUint128(), poolB, 1800);
        return rewardsUSDC;
    }

    function _totalInvestedValue() public view override returns (uint256 totalInvestedValue) {
        uint256 totalInvestedAsset = _totalInvestedBaseAsset();
        if (totalInvestedAsset > 0) {
            totalInvestedValue = triPool.get_dy(2, 1, _totalInvestedBaseAsset());
        }
    }

    // @notice Converts USDC to USDT
    /// @param usdcAmount Amount of USDC
    /// @return Equivalent amount in USDT
    function _convertUsdcToBaseAsset(uint256 usdcAmount) internal view override returns (uint256) {
        return triPool.get_dy(1, 2, usdcAmount);
    }
}
