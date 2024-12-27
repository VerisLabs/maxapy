// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { MaxApyVault, StrategyData } from "../../src/MaxApyVault.sol";
import { IMaxApyVault } from "../../src/interfaces/IMaxApyVault.sol";
import { BaseTest, IERC20, Vm, console2 } from "../base/BaseTest.t.sol";
import { MaxApyVaultEvents } from "../helpers/MaxApyVaultEvents.sol";

import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";

contract BaseVaultTest is BaseTest, MaxApyVaultEvents {
    ////////////////////////////////////////////////////////////////
    ///                      STRUCTS                             ///
    ////////////////////////////////////////////////////////////////
    struct StrategyWithdrawalPreviousData {
        uint256 balance;
        uint256 debtRatio;
        uint256 totalLoss;
        uint256 totalDebt;
    }

    ////////////////////////////////////////////////////////////////
    ///                      STORAGE                             ///
    ////////////////////////////////////////////////////////////////

    IMaxApyVault public vault;
    address public TREASURY;

    function setupVault(string memory chain, address asset) public {
        super._setUp(chain);
        /// Fork mode activated
        TREASURY = makeAddr("treasury");
        MaxApyVault maxApyVault = new MaxApyVault(users.alice, asset, "MaxApyVaultUSDC", "maxUSDCv2", TREASURY);
        vault = IMaxApyVault(address(maxApyVault));
    }

    /*//////////////////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////////////////*/
    function _deposit(address user, IMaxApyVault _vault, uint256 amount) internal returns (uint256) {
        address asset = _vault.asset();
        vm.startPrank(user);
        uint256 expectedShares = _vault.previewDeposit(amount);
        uint256 vaultBalanceBefore = IERC20(asset).balanceOf(address(vault));
        vm.expectEmit();
        emit Deposit(user, user, amount, expectedShares);
        uint256 shares = _vault.deposit(amount, user);
        assertEq(_vault.balanceOf(user), expectedShares);
        assertEq(IERC20(asset).balanceOf(address(vault)), vaultBalanceBefore + amount);

        vm.stopPrank();
        return shares;
    }

    function _withdraw(address user, IMaxApyVault _vault, uint256 assets) internal returns (uint256) {
        vm.startPrank(user);

        address asset = _vault.asset();
        uint256 userBalanceBefore = IERC20(asset).balanceOf(user);

        uint256 expectedShares = vault.previewWithdraw(assets);
        uint256 burntShares = _vault.withdraw(assets, user, user);
        uint256 withdrawn = IERC20(asset).balanceOf(user) - userBalanceBefore;

        assertEq(withdrawn, assets);
        assertLe(burntShares, expectedShares);
        vm.stopPrank();

        return assets;
    }

    function _redeem(
        address user,
        IMaxApyVault _vault,
        uint256 shares,
        uint256 expectedLoss
    )
        internal
        returns (uint256)
    {
        expectedLoss;
        vm.startPrank(user);

        uint256 sharesBalanceBefore = IERC20(_vault).balanceOf(user);
        uint256 sharesComputed = shares;

        uint256 expectedValue = _vault.previewRedeem(sharesComputed);
        uint256 valueWithdrawn = _vault.redeem(shares, user, user);
        uint256 sharesBurnt = sharesBalanceBefore - IERC20(_vault).balanceOf(user);

        assertGe(valueWithdrawn, expectedValue);
        assertEq(shares, sharesBurnt);
        vm.stopPrank();

        return valueWithdrawn;
    }

    function _calculateExpectedShares(uint256 amount) internal view returns (uint256 shares) {
        return vault.previewDeposit(amount);
    }

    function _calculateExpectedStrategistFees(
        uint256 computedStrategistFee,
        uint256 reward,
        uint256 totalFee
    )
        internal
        pure
        returns (uint256)
    {
        return (computedStrategistFee * reward) / totalFee;
    }

    function _calculateMaxExpectedLoss(
        uint256 maxLoss,
        uint256 valueToWithdraw,
        uint256 totalLoss
    )
        internal
        pure
        returns (uint256)
    {
        return (maxLoss * (valueToWithdraw + totalLoss)) / MAX_BPS;
    }

    function _computeExpectedRatioChange(
        IMaxApyVault _vault,
        address strategy,
        uint256 loss
    )
        internal
        returns (uint256)
    {
        return Math.min((loss * _vault.debtRatio()) / _vault.totalDebt(), _vault.strategies(strategy).strategyDebtRatio);
    }
}
