// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import "openzeppelin/interfaces/IERC20.sol";
import "solady/utils/SafeCastLib.sol";

import { CURVE_3POOL_POOL_MAINNET, USDT_MAINNET } from "src/helpers/AddressBook.sol";
import { ICommet } from "src/interfaces/CompoundV2/ICommet.sol";
import { ICommetRewards, RewardOwed } from "src/interfaces/CompoundV2/ICommetRewards.sol";
import { ICurveTriPool } from "src/interfaces/ICurve.sol";
import { BaseCompoundV3Strategy, IMaxApyVault, SafeTransferLib } from "src/strategies/base/BaseCompoundV3Strategy.sol";

import { IUniswapV3Pool, IUniswapV3Router as IRouter } from "src/interfaces/IUniswap.sol";
import { OracleLibrary } from "src/lib/OracleLibrary.sol";

import { console2 } from "forge-std/console2.sol";

import {
    COMP_MAINNET,
    UNISWAP_V3_COMP_WETH_POOL_MAINNET,
    USDC_MAINNET,
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
    address public constant pool = UNISWAP_V3_COMP_WETH_POOL_MAINNET;

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
        ICommet _commet,
        ICommetRewards _commetRewards,
        address _tokenSupplyAddress,
        IRouter _router
    )
        public
        virtual
        initializer
    {
        super.initialize(_vault, _keepers, _strategyName, _strategist, _commet, _commetRewards, _tokenSupplyAddress);

        underlyingAsset.safeApprove(address(triPool), type(uint256).max);
        usdt.safeApprove(address(triPool), type(uint256).max);

        // Set router
        router = _router;

        COMP_MAINNET.safeApprove(address(router), type(uint256).max);
        WETH_MAINNET.safeApprove(address(router), type(uint256).max);

        // Approve tokens

        /// min single trade by default
        minSingleTrade = 10e6;
        /// Unlimited max single trade by default
        maxSingleTrade = 100_000e6;
    }

    /// @notice Sets the new router
    /// @dev Approval for CRV will be granted to the new router if it was not already granted
    /// @param _newRouter The new router address
    function setRouter(address _newRouter) external checkRoles(ADMIN_ROLE) {
        // Remove previous router allowance
        COMP_MAINNET.safeApprove(address(router), 0);
        WETH_MAINNET.safeApprove(address(router), 0);

        // Set new router allowance
        COMP_MAINNET.safeApprove(address(_newRouter), type(uint256).max);
        WETH_MAINNET.safeApprove(address(_newRouter), type(uint256).max);

        assembly ("memory-safe") {
            sstore(router.slot, _newRouter) // set the new router in storage

            // Emit the `RouterUpdated` event
            mstore(0x00, _newRouter)
            log1(0x00, 0x20, _ROUTER_UPDATED_EVENT_SIGNATURE)
        }
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

        uint256 balanceBefore = usdt.balanceOf(address(this));

        // Swap underlying USDC to USDT
        triPool.exchange(1, 2, amount, 1);

        amount = usdt.balanceOf(address(this)) - balanceBefore;

        commet.supply(tokenSupplyAddress, amount);

        commet.balanceOf(address(this));

        console2.log(
            "###   ~ file: CompoundV3USDTStrategy.sol:150 ~ commet.balanceOf(address(this));:",
            commet.balanceOf(address(this))
        );
    }

    /// @notice Divests amount `amount` from Compound Vault
    /// Note that divesting from Compound could potentially cause loss (set to 0.01% as default in
    /// the Vault implementation), so the divested amount might actually be different from
    /// the requested `amount` to divest
    /// @dev care should be taken, as the `amount` parameter is *not* in terms of underlying,
    /// but in terms of yvault amount
    /// @return withdrawn the total amount divested, in terms of base asset of compoundV3
    function _divest(uint256 amount, bool reinvestRewards) internal virtual override returns (uint256 withdrawn) {
        uint256 _before = IERC20(tokenSupplyAddress).balanceOf(address(this));
        commet.withdraw(tokenSupplyAddress, amount);
        uint256 _after = IERC20(tokenSupplyAddress).balanceOf(address(this));
        withdrawn = _after - _before;

        RewardOwed memory reward = commetRewards.getRewardOwed(address(commet), address(this));
        uint256 _rewardBefore = IERC20(reward.token).balanceOf(address(this));
        commetRewards.claim(address(commet), address(this), true);
        uint256 _rewardAfter = IERC20(reward.token).balanceOf(address(this));

        if (reinvestRewards) {
            uint256 wethAmount = swapTokens(COMP_MAINNET, WETH_MAINNET, _rewardAfter - _rewardBefore);
            uint256 usdtAmount = swapTokens(WETH_MAINNET, USDT_MAINNET, wethAmount);
            commet.supply(tokenSupplyAddress, usdtAmount);
        } else {
            uint256 wethAmount = swapTokens(COMP_MAINNET, WETH_MAINNET, _rewardAfter - _rewardBefore);
            uint256 usdcAmount = swapTokens(WETH_MAINNET, USDC_MAINNET, wethAmount);
            withdrawn = withdrawn + usdcAmount;
        }
    }

    function swapTokens(address tokenIn, address tokenOut, uint256 amount) internal returns (uint256) {
        // Swap the COMP rewards to WETH (intermediate token)
        uint256 amountOut = router.exactInputSingle(
            IRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: 100, // 0.01% fee
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        return amountOut;
    }

    function accruedRewardsValue() public returns (uint256) {
        RewardOwed memory reward = commetRewards.getRewardOwed(address(commet), address(this));
        uint256 rewardWETH = _estimateAmountOut(COMP_MAINNET, WETH_MAINNET, reward.owed.toUint128(), 1800);

        uint256 rewardsUSDC = _estimateAmountOut(WETH_MAINNET, USDC_MAINNET, rewardWETH.toUint128(), 1800);
        return rewardsUSDC;
    }

    function totalInvestedAmount(address account) public view returns (uint256) {
        return commet.userBasic(account).principal.toUint256();
        // ICommet.UserBasic memory userDetails =return userDetails.principal.toUint256();
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
            uint256 investedBaseAsset = totalInvestedAmount(address(this));
            // If underlying assest invest currently by strategy is not enough to cover
            // the requested amount, we divest from the Compound rewards
            if (amountToWithdraw > investedBaseAsset) {
                unchecked {
                    amountToWithdraw = amountToWithdraw - investedBaseAsset;
                }
                uint256 rewardsUSDC = accruedRewardsValue();
                assembly {
                    // if withdrawn < amountToWithdraw
                    if gt(amountToWithdraw, rewardsUSDC) { loss := sub(amountToWithdraw, rewardsUSDC) }
                }
            }
        }
        liquidatedAmount = requestedAmount - loss;
    }

    ////////////////////////////////////////////////////////////////
    ///                 INTERNAL VIEW FUNCTIONS                  ///
    ////////////////////////////////////////////////////////////////

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
