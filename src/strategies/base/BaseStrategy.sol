// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { IERC20Metadata } from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import { OwnableRoles } from "solady/auth/OwnableRoles.sol";
import { IStrategy } from "../../interfaces/IStrategy.sol";
import { IMaxApyVault } from "../../interfaces/IMaxApyVault.sol";
import { Initializable } from "../../lib/Initializable.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";

/// @title BaseStrategy
/// @author Forked and adapted from https://github.com/yearn/yearn-vaults/blob/master/contracts/BaseStrategy.sol
/// @notice `BaseStrategy` sets the base functionality to be implemented by MaxApy strategies.
/// @dev Inheriting strategies should implement functionality according to the standards defined in this
/// contract.
abstract contract BaseStrategy is Initializable, OwnableRoles {
    using SafeTransferLib for address;

    ////////////////////////////////////////////////////////////////
    ///                        CONSTANTS                         ///
    ////////////////////////////////////////////////////////////////
    uint256 public constant ADMIN_ROLE = _ROLE_0;
    uint256 public constant EMERGENCY_ADMIN_ROLE = _ROLE_1;
    uint256 public constant VAULT_ROLE = _ROLE_2;
    uint256 public constant KEEPER_ROLE = _ROLE_3;
    uint256 public constant MAX_BPS = 10_000;

    ////////////////////////////////////////////////////////////////
    ///                         EVENTS                           ///
    ////////////////////////////////////////////////////////////////

    /// @notice Emitted when the strategy is harvested
    event Harvested(uint256 profit, uint256 loss, uint256 debtPayment, uint256 debtOutstanding);

    /// @notice Emitted when the strategy's emergency exit status is updated
    event StrategyEmergencyExitUpdated(address indexed strategy, uint256 emergencyExitStatus);

    /// @notice Emitted when the strategy's strategist is updated
    event StrategistUpdated(address indexed strategy, address newStrategist);

    /// @notice Emitted when the strategy's autopilot status is updated
    event StrategyAutopilotUpdated(address indexed strategy, bool autoPilotStatus);

    /// @dev `keccak256(bytes("Harvested(uint256,uint256,uint256,uint256)"))`.
    uint256 internal constant _HARVESTED_EVENT_SIGNATURE =
        0x4c0f499ffe6befa0ca7c826b0916cf87bea98de658013e76938489368d60d509;

    /// @dev `keccak256(bytes("StrategyEmergencyExitUpdated(address,uint256)"))`.
    uint256 internal constant _STRATEGY_EMERGENCYEXIT_UPDATED_EVENT_SIGNATURE =
        0x379f62e57e9c386867f64a9d19eb934e27af596d21fe22da1e9ce6b0bd1ba664;

    /// @dev `keccak256(bytes("StrategistUpdated(address,address)"))`.
    uint256 internal constant _STRATEGY_STRATEGIST_UPDATED_EVENT_SIGNATURE =
        0xf6a8d961ba4f41874e38ad8bed56ca4bcf2356a3dd5bfa626b8a73a0da9f5c69;

    /// @dev `keccak256(bytes("StrategyAutopilotUpdated(address,bool)"))`.
    uint256 internal constant _STRATEGY_AUTOPILOT_UPDATED =
        0x517fe77f85715a129ee7e042c1b69addb2890b8cc86b9dcad191c565d43d69d3;

    ////////////////////////////////////////////////////////////////
    ///            STRATEGY GLOBAL STATE VARIABLES               ///
    ////////////////////////////////////////////////////////////////

    /// @notice The MaxApy vault linked to this strategy
    IMaxApyVault public vault;
    /// @notice The strategy's underlying asset (`want` token)
    address public underlyingAsset;
    /// @notice Strategy state stating if vault is in emergency shutdown mode
    uint256 public emergencyExit;
    /// @notice Name of the strategy
    bytes32 public strategyName;
    /// @notice Strategist's address
    address public strategist;
    /// @notice Strategy's last recorded estimated total assets
    uint256 public lastEstimatedTotalAssets;
    /// @notice Gap for upgradeability
    uint256[20] private __gap;

    ////////////////////////////////////////////////////////////////
    ///                       MODIFIERS                          ///
    ////////////////////////////////////////////////////////////////
    modifier checkRoles(uint256 roles) {
        _checkRoles(roles);
        _;
    }

    ////////////////////////////////////////////////////////////////
    ///                     INITIALIZATION                       ///
    ////////////////////////////////////////////////////////////////
    constructor() initializer { }

    /// @notice Initialize a new Strategy
    /// @param _vault The address of the MaxApy Vault associated to the strategy
    /// @param _keepers The addresses of the keepers to be granted the keeper role
    /// @param _strategyName the name of the strategy
    function __BaseStrategy_init(
        IMaxApyVault _vault,
        address[] calldata _keepers,
        bytes32 _strategyName,
        address _strategist
    )
        internal
        virtual
        onlyInitializing
    {
        assembly ("memory-safe") {
            // Ensure `_strategist` address is != from address(0)
            if eq(_strategist, 0) {
                // throw the `InvalidZeroAddress` error
                mstore(0x00, 0xf6b2911f)
                revert(0x1c, 0x04)
            }
        }

        vault = _vault;
        _grantRoles(address(_vault), VAULT_ROLE);

        // Cache underlying asset
        address _underlyingAsset = _vault.asset();

        underlyingAsset = _underlyingAsset;

        // Approve MaxApyVault to transfer underlying
        _underlyingAsset.safeApprove(address(_vault), type(uint256).max);

        // Grant keepers with `KEEPER_ROLE`
        for (uint256 i; i < _keepers.length;) {
            _grantRoles(_keepers[i], KEEPER_ROLE);
            unchecked {
                ++i;
            }
        }

        // Set caller as admin and owner
        _initializeOwner(msg.sender);
        _grantRoles(msg.sender, ADMIN_ROLE);

        strategyName = _strategyName;

        emergencyExit = 1;

        strategist = _strategist;
    }

    ////////////////////////////////////////////////////////////////
    ///                STRATEGY CORE LOGIC                       ///
    ////////////////////////////////////////////////////////////////
    /// @notice Tries to withdraw `amountNeeded` to `vault`.
    /// @dev This may only be called by the respective Vault.
    /// @param amountNeeded How much `underlyingAsset` to withdraw.
    /// @return loss Any realized losses
    function liquidate(uint256 amountNeeded) external virtual checkRoles(VAULT_ROLE) returns (uint256 loss) {
        uint256 amountFreed;
        // Liquidate as much as possible to `underlyingAsset`, up to `amountNeeded`
        (amountFreed, loss) = _liquidatePosition(amountNeeded);
        // Send it directly back to vault
        if (amountFreed > 0) underlyingAsset.safeTransfer(address(vault), amountFreed);
        // Note: update estimatedTotalAssets
        _snapshotEstimatedTotalAssets();
    }

    /// @notice Withdraws exactly `amountNeeded` to `vault`.
    /// @dev This may only be called by the respective Vault.
    /// @param amountNeeded How much `underlyingAsset` to withdraw.
    /// @return loss Any realized losses
    /// NOTE : while in the {withdraw} function the vault gets `amountNeeded` - `loss`
    /// in {liquidateExact} the vault always gets `amountNeeded` and `loss` is the amount
    /// that had to be lost in order to withdraw exactly `amountNeeded`
    function liquidateExact(uint256 amountNeeded) external virtual checkRoles(VAULT_ROLE) returns (uint256 loss) {
        uint256 amountRequested = previewLiquidateExact(amountNeeded);
        uint256 amountFreed;
        // liquidate `amountRequested` in order to get exactly or more than `amountNeeded`
        (amountFreed, loss) = _liquidatePosition(amountRequested);

        // Send it directly back to vault
        if (amountFreed >= amountNeeded) underlyingAsset.safeTransfer(address(vault), amountNeeded);
        // something didn't work as expected
        // this should NEVER happen in normal conditions
        else revert();
        // Note: update esteimated totalAssets
        _snapshotEstimatedTotalAssets();
    }

    /// @notice Harvests the Strategy and reports any gain in its positions to the vault
    /// In the rare case the Strategy is in emergency shutdown, this will exit
    /// the Strategy's position.
    /// @dev When `harvest()` is called, the strategy reinvests a percentage of the profit and
    /// reports the rest of it to the MaxAPY vault (via`MaxApyVault.report()`), so this function is meant
    /// to  be called when there are profits or there is new credit available for the strategy
    /// @param minExpectedBalance minimum balance amount of `underlyingAsset` expected after performing any
    /// @param minOutputAfterInvestment minimum expected output after `_invest()`
    /// strategy unwinding (if applies).
    /// @param harvester only relevant when the harvest is triggered from the vault, is the address of the user that is
    /// enduring the harvest gas cost
    /// from the vault and will receive the managemente fees in return
    /// @param deadline max allowed timestamp for the transaction to be included in a block
    function harvest(
        uint256 minExpectedBalance,
        uint256 minOutputAfterInvestment,
        address harvester,
        uint256 deadline
    )
        external
        checkRoles(KEEPER_ROLE)
    {
        assembly ("memory-safe") {
            // if block.timestamp > deadline
            if gt(timestamp(), deadline) {
                // revert
                revert(0, 0)
            }
        }
        // normally the treasury would get the management fee
        address managementFeeReceiver;
        // if the harvest was done from the vault means it the
        // harvest was triggered on a deposit
        if (msg.sender == address(vault)) {
            // the depositing user will get the management fees as a reward
            // for paying gas costs of harvest
            managementFeeReceiver = harvester;
        }

        uint256 unrealizedProfit;
        uint256 loss;
        uint256 debtPayment;
        uint256 debtOutstanding;

        address cachedVault = address(vault); // Cache `vault` address to avoid multiple SLOAD's

        assembly ("memory-safe") {
            // Store `vault`'s `debtOutstanding()` function selector:
            // `bytes4(keccak256("debtOutstanding(address)"))`
            mstore(0x00, 0xbdcf36bb)
            mstore(0x20, address()) // append the current address as parameter

            // query `vault`'s `debtOutstanding()`
            if iszero(
                staticcall(
                    gas(), // Remaining amount of gas
                    cachedVault, // Address of `vault`
                    0x1c, // byte offset in memory where calldata starts
                    0x24, // size of the calldata to copy
                    0x00, // byte offset in memory to store the return data
                    0x20 // size of the return data
                )
            ) {
                // Revert if debt outstanding query fails
                revert(0x00, 0x04)
            }

            // Store debt outstanding returned by staticcall into `debtOutstanding`
            debtOutstanding := mload(0x00)
        }

        if (emergencyExit == 2) {
            // Do what needed before
            _beforePrepareReturn();

            uint256 balanceBefore = _estimatedTotalAssets();
            // Free up as much capital as possible
            uint256 amountFreed = _liquidateAllPositions();

            // silence compiler warnings
            amountFreed;

            uint256 balanceAfter = _estimatedTotalAssets();

            assembly {
                // send everything back to the vault
                debtPayment := balanceAfter
                if lt(balanceAfter, balanceBefore) { loss := sub(balanceBefore, balanceAfter) }
            }
        } else {
            // Do what needed before
            _beforePrepareReturn();
            // Free up returns for vault to pull
            (unrealizedProfit, loss, debtPayment) = _prepareReturn(debtOutstanding, minExpectedBalance);
        }

        assembly ("memory-safe") {
            let m := mload(0x40) // Store free memory pointer
            // Store `vault`'s `report()` function selector:
            // `bytes4(keccak256("report(uint128,uint128,uint128,address)"))`
            mstore(0x00, 0x80919dd5)
            mstore(0x20, unrealizedProfit) // append the `profit` argument
            mstore(0x40, loss) // append the `loss` argument
            mstore(0x60, debtPayment) // append the `debtPayment` argument
            mstore(0x80, managementFeeReceiver) // append the `debtPayment` argument

            // Report to vault
            if iszero(
                call(
                    gas(), // Remaining amount of gas
                    cachedVault, // Address of `vault`
                    0, // `msg.value`
                    0x1c, // byte offset in memory where calldata starts
                    0x84, // size of the calldata to copy
                    0x00, // byte offset in memory to store the return data
                    0x20 // size of the return data
                )
            ) {
                // If call failed, throw the error thrown in the previous `call`
                revert(0x00, 0x04)
            }

            // Store debt outstanding returned by call to `report()` into `debtOutstanding`
            debtOutstanding := mload(0x00)

            mstore(0x60, 0) // Restore the zero slot
            mstore(0x40, m) // Restore the free memory pointer
        }
        // Check if vault transferred underlying and re-invest it
        _adjustPosition(debtOutstanding, minOutputAfterInvestment);
        _snapshotEstimatedTotalAssets();

        assembly ("memory-safe") {
            let m := mload(0x40) // Store free memory pointer

            mstore(0x00, unrealizedProfit)
            mstore(0x20, loss)
            mstore(0x40, debtPayment)
            mstore(0x60, debtOutstanding)

            log1(0x00, 0x80, _HARVESTED_EVENT_SIGNATURE)

            mstore(0x60, 0) // Restore the zero slot
            mstore(0x40, m) // Restore the free memory pointer
        }
    }

    ////////////////////////////////////////////////////////////////
    ///                 STRATEGY CONFIGURATION                   ///
    ////////////////////////////////////////////////////////////////

    /// @notice Sets the strategy in emergency exit mode
    /// @param _emergencyExit The new emergency exit value: 1 for unactive, 2 for active
    function setEmergencyExit(uint256 _emergencyExit) external checkRoles(ADMIN_ROLE) {
        assembly ("memory-safe") {
            sstore(emergencyExit.slot, _emergencyExit)
            // Emit the `StrategyEmergencyExitUpdated` event
            mstore(0x00, _emergencyExit)
            log2(0x00, 0x20, _STRATEGY_EMERGENCYEXIT_UPDATED_EVENT_SIGNATURE, address())
        }
    }

    /// @notice Sets the strategy's new strategist
    /// @param _newStrategist The new strategist address
    function setStrategist(address _newStrategist) external checkRoles(ADMIN_ROLE) {
        assembly ("memory-safe") {
            if iszero(_newStrategist) {
                // throw the `InvalidZeroAddress` error
                mstore(0x00, 0xf6b2911f)
                revert(0x1c, 0x04)
            }

            sstore(strategist.slot, _newStrategist)

            // Emit the `StrategistUpdated` event
            mstore(0x00, _newStrategist)
            log2(0x00, 0x20, _STRATEGY_STRATEGIST_UPDATED_EVENT_SIGNATURE, address())
        }
    }

    /// @notice Sets the strategy in autopilot mode, meaning that it will be automatically
    /// harvested from the vault using the strategy
    /// @param _autoPilot The new autopilot status: true for active false for inactive
    function setAutopilot(bool _autoPilot) external checkRoles(ADMIN_ROLE) {
        // grante the keeper role to the vault
        if (!hasAnyRole(address(vault), KEEPER_ROLE)) {
            _grantRoles(address(vault), KEEPER_ROLE);
        }
        vault.setAutoPilot(_autoPilot);
        assembly ("memory-safe") {
            // Emit the `StrategyAutopilotUpdated` event
            mstore(0x00, _autoPilot)
            log2(0x00, 0x20, _STRATEGY_AUTOPILOT_UPDATED, address())
        }
    }

    ////////////////////////////////////////////////////////////////
    ///                    INTERNAL FUNCTIONS                    ///
    ////////////////////////////////////////////////////////////////
    /// @notice Performs any adjustments to the core position(s) of this Strategy given
    /// what change the MaxApy Vault made in the "investable capital" available to the
    /// Strategy.
    /// @dev Note that all "free capital" (capital not invested) in the Strategy after the report
    /// was made is available for reinvestment. This number could be 0, and this scenario should be handled accordingly.
    /// @param debtOutstanding Total principal + interest of debt yet to be paid back
    /// @param minOutputAfterInvestment minimum expected output after `_invest()` (designated in receipt tokens obtained
    /// after depositing in a third-party protocol)
    function _adjustPosition(uint256 debtOutstanding, uint256 minOutputAfterInvestment) internal virtual;

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
        virtual
        returns (uint256 liquidatedAmount, uint256 loss);

    /// @notice Liquidates everything and returns the amount that got freed.
    /// @dev This function is used during emergency exit instead of `_prepareReturn()` to
    /// liquidate all of the Strategy's positions back to the MaxApy Vault.
    function _liquidateAllPositions() internal virtual returns (uint256 amountFreed);

    /// Perform any Strategy unwinding or other calls necessary to capture the
    /// "free return" this Strategy has generated since the last time its core
    /// position(s) were adjusted. Examples include unwrapping extra rewards.
    /// This call is only used during "normal operation" of a Strategy, and
    /// should be optimized to minimize losses as much as possible.
    ///
    /// This method returns any realized and unrealized profits and/or realized and unrealized losses
    /// incurred, and should return the total amounts of profits/losses/debt
    /// payments (in MaxApy Vault's `underlyingAsset` tokens) for the MaxApy Vault's accounting (e.g.
    /// `underlyingAsset.balanceOf(this) >= debtPayment + profit`).
    ///
    /// `debtOutstanding` will be 0 if the Strategy is not past the configured
    /// debt limit, otherwise its value will be how far past the debt limit
    /// the Strategy is. The Strategy's debt limit is configured in the MaxApy Vault.
    ///
    /// NOTE: `debtPayment` should be less than or equal to `debtOutstanding`.
    ///       It is okay for it to be less than `debtOutstanding`, as that
    ///       should only be used as a guide for how much is left to pay back.
    ///       Payments should be made to minimize loss from slippage, debt,
    ///       withdrawal fees, etc.
    ///
    /// See `MaxApyVault.debtOutstanding()`.
    function _prepareReturn(
        uint256 debtOutstanding,
        uint256 minExpectedBalance
    )
        internal
        virtual
        returns (uint256 unrealizedProfit, uint256 loss, uint256 debtPayment);

    /// @dev custom hook to perform extra actions/checks before preparing th return
    function _beforePrepareReturn() internal virtual { }

    /// @notice Returns the current strategy's balance in underlying token
    /// @return the strategy's balance of underlying token
    function _underlyingBalance() internal view returns (uint256) {
        return underlyingAsset.balanceOf(address(this));
    }

    /// @notice Returns the real time estimation of the value in assets held by the strategy
    /// @return the strategy's total assets(idle + investment positions)
    function _estimatedTotalAssets() internal view virtual returns (uint256);

    /// @notice Returns the real gain/loss from the last harvest
    function unharvestedAmount() external view virtual returns (int256) {
        return int256(_estimatedTotalAssets()) - int256(lastEstimatedTotalAssets);
    }

    ////////////////////////////////////////////////////////////////
    ///                    EXTERNAL VIEW FUNCTIONS               ///
    ////////////////////////////////////////////////////////////////
    /// @notice Provide an accurate estimate for the total amount of assets
    /// (principle + return) that this Strategy is currently managing,
    /// denominated in terms of `underlyingAsset` tokens.
    /// This total should be "realizable" e.g. the total value that could
    /// *actually* be obtained from this Strategy if it were to divest its
    /// entire position based on current on-chain conditions.
    /// @dev Care must be taken in using this function, since it relies on external
    /// systems, which could be manipulated by the attacker to give an inflated
    /// (or reduced) value produced by this function, based on current on-chain
    /// conditions (e.g. this function is possible to influence through
    /// flashloan attacks, oracle manipulations, or other DeFi attack
    /// mechanisms).
    /// @return The estimated total assets in this Strategy.
    function estimatedTotalAssets() public view returns (uint256) {
        // always try to use the value from the last harvest so share price is not updated before the harvest
        // always be pessimistic, take the lowest between the last harvest assets and assets in that moment
        return Math.min(lastEstimatedTotalAssets, _estimatedTotalAssets());
    }

    /// @notice Provides an indication of whether this strategy is currently "active"
    /// in that it is managing an active position, or will manage a position in
    /// the future. This should correlate to `harvest()` activity, so that Harvest
    /// events can be tracked externally by indexing agents.
    /// @return True if the strategy is actively managing a position.
    function isActive() public view returns (bool) {
        return estimatedTotalAssets() != 0;
    }

    /// @notice This function is meant to be called from the vault
    /// @dev calculates the real output of a withdrawal(including losses) for a @param requestedAmount
    /// for the vault to be able to provide an accurate amount when calling `previewRedeem`
    /// @return liquidatedAmount output in assets
    function previewLiquidate(uint256 requestedAmount) public view virtual returns (uint256 liquidatedAmount);

    /// @notice This function is meant to be called from the vault
    /// @dev calculates the @param requestedAmount the vault has to request to this strategy
    /// in order to actually get @param liquidatedAmount assets when calling `previewWithdraw`
    /// @return requestedAmount
    function previewLiquidateExact(uint256 liquidatedAmount) public view virtual returns (uint256 requestedAmount);

    /// @notice Returns the max amount of assets that the strategy can withdraw after losses
    function maxLiquidateExact() public view virtual returns (uint256);

    /// @notice Returns the max amount of assets that the strategy can liquidate, before realizing losses
    function maxLiquidate() public view virtual returns (uint256);

    ////////////////////////////////////////////////////////////////
    ///                      HELPER FUNCTIONS                    ///
    ////////////////////////////////////////////////////////////////
    /// @dev Private helper to substract a - b or return 0 if it underflows
    function _sub0(uint256 a, uint256 b) internal pure virtual returns (uint256) {
        unchecked {
            return a - b > a ? 0 : a - b;
        }
    }

    /// @notice caches estimated total assets
    function _snapshotEstimatedTotalAssets() internal {
        // snapshot of the estimated total assets
        lastEstimatedTotalAssets = _estimatedTotalAssets();
    }

    ////////////////////////////////////////////////////////////////
    ///                      SIMULATION                          ///
    ////////////////////////////////////////////////////////////////

    function _simulateHarvest() public virtual;

    function simulateHarvest() public returns (uint256 expectedBalance, uint256 outputAfterInvestment) {
        try this._simulateHarvest() { }
        catch (bytes memory e) {
            (expectedBalance, outputAfterInvestment) = abi.decode(e, (uint256, uint256));
        }
    }
}
