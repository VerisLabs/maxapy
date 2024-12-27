// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { ReentrancyGuard } from "./lib/ReentrancyGuard.sol";
import { IERC20Metadata } from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import { OwnableRoles } from "solady/auth/OwnableRoles.sol";

import { ERC20, ERC4626 } from "solady/tokens/ERC4626.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { StrategyData } from "src/helpers/VaultTypes.sol";
import { IStrategy } from "src/interfaces/IStrategy.sol";

/*KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK
KKKKK0OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO0KKKKKKK
KK0dcclllllllllllllllllllllllllllllccccccccccccccccccclx0KKK
KOc,dKNWWWWWWWWWWWWWWWWWWWWWWWWWWWWNNNNNNNNNNNNNNNNNXOl';xKK
Kd'oWMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMX; ,kK
Ko'xMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMNc .dK
Ko'dMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMNc .oK
Kd'oWMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMNc .oK
KO:,xXWWWWWWWWWWWWWWWWWWWWMMMMMMMMMMMMMMMMMMMMMMMMMMMMNc .oK
KKOl,',;;,,,,,,;;,,,,,,,;;cxXMMMMMMMMMMMMMMMMMMMMMMMMMNc .oK
KKKKOoc;;;;;;;;;;;;;;;;;;;,.cXMMMMMMMMMMMMMMMMMMMMMMMMNc .oK
KKKKKKKKKKKKKKKKKKKK00O00K0:,0MMMMMMMMMMMMMMMMMMMMMMMMNc .oK
KKKKKKKKKKKKKKKKKKklcccccld;,0MMMMMMMMMMMMMMMMMMMMMMMMNc .oK
KKKKKKKKKKKKKKKKkl;ckXNXOc. '0MMMMMMMMMMMMMMMMMMMMMMMMNc .oK
KKKKKKKKKKKKKKkc;l0WMMMMMX; .oKNMMMMMMMMMMMMMMMMMMMMMMNc .oK
KKKKKKKKKKKKkc;l0WMMMMMMMWd.  .,lddddddxONMMMMMMMMMMMMNc .oK
KKKKKKKKKKkc;l0WMMMMMMMMMMWOl::;'.  .....:0WMMMMMMMMMMNc .oK
KKKKKKK0xc;o0WMMMMMMMMMMMMMMMMMWNk'.;xkko'lNMMMMMMMMMMNc .oK
KKKKK0x:;oKWMMMMMMMMMMMMMMMMMMMMMWd..lKKk,lNMMMMMMMMMMNc .oK
KKK0x:;oKWMMMMMMMMMMMMMMMMMMMMMMWO,  c0Kk,lNMMMMMMMMMMNc .oK
KKx:;dKWMMMMMMMMMMMMMMMMMMMMMWN0c.  ;kKKk,lNMMMMMMMMMMNc .oK
Kx,:KWMMMMMMMMMMMMMMMMMMMMMW0c,.  'oOKKKk,lNMMMMMMMMMMNc .oK
Ko'xMMMMMMMMMMMMMMMMMMMMMW0c.   'oOKKKKKk,lNMMMMMMMMMMNc .oK
Ko'xMMMMMMMMMMMMMMMMMMMW0c.  ':oOKKKKKKKk,lNMMMMMMMMMMNc .oK
Ko'xMMMMMMMMMMMMMMMMMW0l.  'oOKKKKKKKKKKk,cNMMMMMMMMMMNc .oK
Ko'xMMMMMMMMMMMMMMMW0l.  'oOKKKKKKKKKKKKk,lNMMMMMMMMMMNc .oK
Ko'dWMMMMMMMMMMMMW0l.  'oOKKKKKKKKKKKKKKk,cNMMMMMMMMMMX: .oK
KO:,xXNWWWWWWWWNOl.  'oOKKKKKKKKKKKKKKKK0c,xNMMMMMMMMNd. .dK
KKOl''',,,,,,,,..  'oOKKKKKKKKKKKKKKKKKKKOl,,ccccccc:'  .c0K
KKKKOoc:;;;;;;;;:ldOKKKKKKKKKKKKKKKKKKKKKKKkl;'......',cx0KK
KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK0OOOOOOO0KKK*/

/// @title MaxApy Vault V2 Contract
/// @notice A ERC4626 vault contract deploying `underlyingAsset` to strategies that earn yield and report gains/losses
/// to the vault
/// @author ERC2626 adaptation of MaxAPYVault:
/// https://github.com/UnlockdFinance/maxapy/blob/development/src/MaxApyVault.sol
contract MaxApyVault is ERC4626, OwnableRoles, ReentrancyGuard {
    using SafeTransferLib for address;
    ////////////////////////////////////////////////////////////////
    ///                         CONSTANTS                        ///
    ////////////////////////////////////////////////////////////////

    uint256 public constant MAXIMUM_STRATEGIES = 20;
    uint256 public constant MAX_BPS = 10_000;
    /// 365.2425 days
    uint256 public constant SECS_PER_YEAR = 31_556_952;
    // every week
    uint256 public constant AUTOPILOT_HARVEST_INTERVAL = 1 weeks;

    /// Roles
    uint256 public constant ADMIN_ROLE = _ROLE_0;
    uint256 public constant EMERGENCY_ADMIN_ROLE = _ROLE_1;
    uint256 public constant STRATEGY_ROLE = _ROLE_2;

    ////////////////////////////////////////////////////////////////
    ///                         ERRORS                           ///
    ////////////////////////////////////////////////////////////////
    error QueueIsFull();
    error VaultInEmergencyShutdownMode();
    error StrategyInEmergencyExitMode();
    error InvalidZeroAddress();
    error StrategyAlreadyActive();
    error StrategyNotActive();
    error InvalidStrategyVault();
    error InvalidStrategyUnderlying();
    error InvalidDebtRatio();
    error InvalidMinDebtPerHarvest();
    error InvalidPerformanceFee();
    error InvalidManagementFee();
    error StrategyDebtRatioAlreadyZero();
    error InvalidQueueOrder();
    error VaultDepositLimitExceeded();
    error InvalidZeroAmount();
    error InvalidZeroShares();
    error LossGreaterThanStrategyTotalDebt();
    error InvalidReportedGainAndDebtPayment();
    error FeesAlreadyAssesed();

    ////////////////////////////////////////////////////////////////
    ///                         EVENTS                           ///
    ////////////////////////////////////////////////////////////////

    /// @notice Emitted when a strategy is newly added to the protocol
    event StrategyAdded(
        address indexed newStrategy,
        uint16 strategyDebtRatio,
        uint128 strategyMaxDebtPerHarvest,
        uint128 strategyMinDebtPerHarvest,
        uint16 strategyPerformanceFee
    );

    /// @notice Emitted when a strategy is removed from the protocol
    event StrategyRemoved(address indexed strategy);

    /// @notice Emitted when a vault's emergency shutdown state is switched
    event EmergencyShutdownUpdated(bool emergencyShutdown);

    /// @notice Emitted when a vault's autopilot mode is enabled or disabled
    event AutopilotEnabled(bool isEnabled);

    /// @notice Emitted when a strategy is revoked from the vault
    event StrategyRevoked(address indexed strategy);

    /// @notice Emitted when a strategy parameters are updated
    event StrategyUpdated(
        address indexed strategy,
        uint16 newDebtRatio,
        uint128 newMaxDebtPerHarvest,
        uint128 newMinDebtPerHarvest,
        uint16 newPerformanceFee
    );

    /// @notice Emitted when a strategy is exited
    event StrategyExited(address indexed strategy, uint256 withdrawn);

    /// @notice Emitted when the withdrawal queue is updated
    event WithdrawalQueueUpdated(address[MAXIMUM_STRATEGIES] withdrawalQueue);

    /// @notice Emitted when the vault's performance fee is updated
    event PerformanceFeeUpdated(uint16 newPerformanceFee);

    /// @notice Emitted when the vault's management fee is updated
    event ManagementFeeUpdated(uint256 newManagementFee);

    /// @notice Emitted when the vault's deposit limit is updated
    event DepositLimitUpdated(uint256 newDepositLimit);

    /// @notice Emitted when the vault's treasury addresss is updated
    event TreasuryUpdated(address treasury);

    /// @notice Emitted on withdrawal strategy withdrawals
    event WithdrawFromStrategy(address indexed strategy, uint128 strategyTotalDebt, uint128 loss);

    /// @notice Emitted after assessing protocol fees
    event FeesReported(uint256 managementFee, uint16 performanceFee, uint256 strategistFee, uint256 duration);

    /// @notice Emitted after a forced harvest fails unexpectedly
    event ForceHarvestFailed(address indexed strategy, bytes reason);

    /// @notice Emitted after a strategy reports to the vault
    event StrategyReported(
        address indexed strategy,
        uint256 unrealizedGain,
        uint256 loss,
        uint256 debtPayment,
        uint128 strategyTotalUnrealizedGain,
        uint128 strategyTotalLoss,
        uint128 strategyTotalDebt,
        uint256 credit,
        uint16 strategyDebtRatio
    );

    // EVENT SIGNATURES
    uint256 internal constant _STRATEGY_ADDED_EVENT_SIGNATURE =
        0x66277e61c003f7703009ad857a4c4900f9cd3ee44535afe5905f98d53922e0f4;

    uint256 internal constant _STRATEGY_REMOVED_EVENT_SIGNATURE =
        0x09a1db4b80c32706328728508c941a6b954f31eb5affd32f236c1fd405f8fea4;

    uint256 internal constant _EMERGENCY_SHUTDOWN_UPDATED_EVENT_SIGNATURE =
        0xa63137c77816d51f856c11ffb11e84757ac9db0ce2569f94edd04c91fe2250a1;

    uint256 internal constant _AUTOPILOT_ENABLED_EVENT_SIGNATURE =
        0xba59cddbbe4aad399b09d7f484fdd0a4bc54da6a697a48549cbe72d79c66fcb3;

    uint256 internal constant _STRATEGY_REVOKED_EVENT_SIGNATURE =
        0x4201c688d84c01154d321afa0c72f1bffe9eef53005c9de9d035074e71e9b32a;

    uint256 internal constant _STRATEGY_UPDATED_EVENT_SIGNATURE =
        0x102a33a8369310733322056f2c0f753209cd77c65b1ce5775c2d6f181e38778f;

    uint256 internal constant _WITHDRAWAL_QUEUE_UPDATED_EVENT_SIGNATURE =
        0x92fa0b6a2861480bf8c9977f0f9fe1d95c535ba23cbf234f2716fc765aec3be8;

    uint256 internal constant _PERFORMANCE_FEE_UPDATED_EVENT_SIGNATURE =
        0x0632b4ddf7c06e7e3bc19b7ce92862c7de91b312a392142116fb574a06a47cfd;

    uint256 internal constant _MANAGEMENT_FEE_UPDATED_EVENT_SIGNATURE =
        0x2147e2bc8c39e67f74b1a9e08896ea1485442096765942206af1f4bc8bcde917;

    uint256 internal constant _DEPOSIT_LIMIT_UPDATED_EVENT_SIGNATURE =
        0xc512617347fd848ec9d7347c99c10e4fa7059132c92d0445930a7fb0c8252ff5;

    uint256 internal constant _TREASURY_UPDATED_EVENT_SIGNATURE =
        0x7dae230f18360d76a040c81f050aa14eb9d6dc7901b20fc5d855e2a20fe814d1;

    uint256 internal constant _WITHDRAW_FROM_STRATEGY_EVENT_SIGNATURE =
        0x8c1171ccd065c6769e1540f65c3c0874e5f7173ccdff7ca293238e69d000bf20;

    uint256 internal constant _FEES_REPORTED_EVENT_SIGNATURE =
        0x25bf703141a84375d04ea08a0c4a21c7406f300f133e12aef555607b4f3ff238;

    uint256 internal constant _STRATEGY_REPORTED_EVENT_SIGNATURE =
        0xc2d7e1173e37528dce423c72b129fa1ad2c5d51e50974c64fe13f1928eb27f89;

    uint256 private constant _DEPOSIT_EVENT_SIGNATURE =
        0xdcbc1c05240f31ff3ad067ef1ee35ce4997762752e3a095284754544f4c709d7;

    uint256 private constant _WITHDRAW_EVENT_SIGNATURE =
        0xfbde797d201c681b91056529119e0b02407c7bb96a4a2c75c01fc9667232c8db;

    uint256 private constant _STRATEGY_EXITED_EVENT_SIGNATURE =
        0x2e8aac9e73a32a1b5926e2c5a2820a51deb01ed40212b6346d96db2a178cf433;

    ////////////////////////////////////////////////////////////////
    ///               VAULT GLOBAL STATE VARIABLES               ///
    ////////////////////////////////////////////////////////////////

    /// @notice Vault state stating if vault is in emergency shutdown mode
    bool public emergencyShutdown;
    /// @notice Vault state stating if vault allows for automated harvesting of strategies
    bool public autoPilotEnabled;
    /// @notice the decimals of the underlying ERC20 token
    uint8 private immutable _decimals;
    /// @notice the index in {withdrawalQueue} of the next strategy to be harvested from the autopilot
    uint8 public nexHarvestStrategyIndex;
    /// @notice Limit for totalAssets the Vault can hold
    uint256 public depositLimit;
    /// @notice Debt ratio for the Vault across all strategies (in BPS, <= 10k)
    uint256 public debtRatio;
    /// @notice Amount of tokens that are in the vault
    uint256 public totalIdle;
    /// @notice Amount of tokens that all strategies have borrowed
    uint256 public totalDebt;
    /// @notice block.timestamp of last report
    uint256 public lastReport;
    /// @notice Rewards address where performance and management fees are sent to
    address public treasury;

    /// @notice Record of all the strategies that are allowed to receive assets from the vault
    mapping(address => StrategyData) public strategies;
    /// @notice Ordering that `withdraw` uses to determine which strategies to pull funds from
    address[MAXIMUM_STRATEGIES] public withdrawalQueue;

    /// @notice Fee minted to the treasury and deducted from yield earned every time the vault harvests a strategy
    uint256 public performanceFee;
    /// @notice Flat rate taken from vault yield over a year
    uint256 public managementFee;

    /// @notice name of the vault shares ERC20 token
    string private _name;
    /// @notice symbol of the vault shares ERC20 token
    string private _symbol;
    /// @notice the assets in which the vault earns interest
    address private immutable _underlyingAsset;

    ////////////////////////////////////////////////////////////////
    ///                         MODIFIERS                        ///
    ////////////////////////////////////////////////////////////////

    modifier checkRoles(uint256 roles) {
        _checkRoles(roles);
        _;
    }

    modifier noEmergencyShutdown() {
        if (emergencyShutdown) {
            revert VaultInEmergencyShutdownMode();
        }
        _;
    }

    constructor(
        address admin,
        address underlyingAsset_,
        string memory name_,
        string memory symbol_,
        address _treasury
    ) {
        _initializeOwner(admin);
        _grantRoles(admin, ADMIN_ROLE);
        performanceFee = 1000; // 10% of reported yield (per Strategy)
        managementFee = 200; // 2% of reported yield (per Strategy)
        lastReport = block.timestamp;
        (bool success, uint8 result) = _tryGetAssetDecimals(underlyingAsset_);
        _decimals = success ? result : _DEFAULT_UNDERLYING_DECIMALS;
        // deposit limit is 10M tokens
        depositLimit = 10_000_000 * 10 ** _decimals;
        treasury = _treasury;
        _underlyingAsset = underlyingAsset_;
        _name = name_;
        _symbol = symbol_;
    }

    ////////////////////////////////////////////////////////////////
    ///                    INTERNAL FUNCTIONS                    ///
    ////////////////////////////////////////////////////////////////
    /// @notice Forces the harvest of a
    /// @param harvester user that will get extra shares for harvesting
    /// @dev it should never revert to ensure users can always deposit
    function _forceOneHarvest(address harvester)
        internal
        returns (address strategy, bool success, bytes memory reason)
    {
        uint256 l = withdrawalQueue.length;
        address[MAXIMUM_STRATEGIES] memory strats = withdrawalQueue;
        // find the first strategy that is in autopilot
        uint8 i = nexHarvestStrategyIndex > l - 1 ? 0 : nexHarvestStrategyIndex;
        bool strategyFound;
        for (i; i < l;) {
            if (strategies[strats[i]].autoPilot) {
                strategy = strats[i];
                strategyFound = true;
                break;
            }
            unchecked {
                ++i;
            }
        }

        // if the strategy we will harvest is the last of the array or its out of bounds
        // because of some change in the withdrawal queue
        // set it back to the first index(0) of the array
        unchecked {
            if (i >= l - 1 || strats[i + 1] == address(0)) {
                nexHarvestStrategyIndex = 0;
            } else {
                nexHarvestStrategyIndex = ++i;
            }
        }

        // if there are no strategies to harvest return
        if (!strategyFound) return (strategy, true, reason);

        // use try/catch so deposits always succeed
        // and next index is updated
        try IStrategy(strategy).harvest(0, 0, harvester, block.timestamp) {
            success = true;
        } catch (bytes memory _reason) {
            reason = _reason;
            success = false;
        }
    }

    /// @notice Reports a strategy loss, adjusting the corresponding vault and strategy parameters
    /// to minimize trust in the strategy
    /// @param strategy The strategy reporting the loss
    /// @param loss The amount of loss to report
    function _reportLoss(address strategy, uint256 loss) internal {
        // Strategy data
        uint128 strategyTotalDebt;
        uint16 strategyDebtRatio;

        // Vault data
        uint256 totalDebt_;
        uint256 debtRatio_;

        // Slot data
        uint256 strategiesSlot;
        uint256 slot0Content;
        uint256 slot2Content;

        assembly ("memory-safe") {
            // Get strategies slot
            mstore(0x00, strategy)
            mstore(0x20, strategies.slot)
            strategiesSlot := keccak256(0x00, 0x40)
            // Obtain strategy slot 0 data
            slot0Content := sload(strategiesSlot)
            // Obtain strategy slot 2 data
            slot2Content := sload(add(strategiesSlot, 2))

            // Cache strategy data
            strategyDebtRatio := shr(240, shl(240, slot0Content))
            strategyTotalDebt := shr(128, shl(128, slot2Content))

            // if loss > strategyData.strategyTotalDebt
            if gt(loss, strategyTotalDebt) { loss := strategyTotalDebt }

            // Obtain vault debtRatio
            debtRatio_ := sload(debtRatio.slot)
            // Obtain vault totalDebt
            totalDebt_ := sload(totalDebt.slot)
        }

        uint256 ratioChange;
        if (totalDebt_ > 0) {
            // Reduce trust in this strategy by the amount of loss, lowering the corresponding strategy debt ratio
            ratioChange = Math.min((loss * debtRatio_) / totalDebt_, strategyDebtRatio);
        }

        assembly {
            // Overflow checks
            if gt(ratioChange, debtRatio_) {
                // throw `Overflow` error
                revert(0, 0)
            }
            if gt(loss, totalDebt_) {
                // throw `Overflow` error
                revert(0, 0)
            }
            if gt(ratioChange, strategyDebtRatio) {
                // throw `Overflow` error
                revert(0, 0)
            }

            // Update vault data
            // debtRatio -= ratioChange;
            // totalDebt -= loss;
            sstore(debtRatio.slot, sub(debtRatio_, ratioChange)) // debtRatio -= ratioChange
            sstore(totalDebt.slot, sub(totalDebt_, loss)) // totalDebt -= loss

            // Update strategy debt ratio
            // strategies[strategy].strategyDebtRatio -= ratioChange
            sstore(
                strategiesSlot,
                or(
                    shr(240, shl(240, sub(strategyDebtRatio, ratioChange))), // Compute
                        // strategies[strategy].strategyDebtRatio - ratioChange
                    shl(16, shr(16, slot0Content)) // Obtain previous slot data, removing `strategyDebtRatio`
                )
            )

            // Adjust final strategy parameters by the loss
            let strategyTotalLoss := shr(128, slot2Content)
            // strategyTotalLoss += loss
            strategyTotalLoss := add(strategyTotalLoss, loss)

            if lt(strategyTotalLoss, loss) {
                // throw `Overflow` error
                revert(0, 0)
            }

            // Pack strategyTotalLoss and strategyTotalDebt into slot2Content
            slot2Content :=
                or(
                    shl(128, strategyTotalLoss),
                    shr(128, shl(128, sub(strategyTotalDebt, loss))) // Compute strategies[strategy].strategyTotalDebt
                        // -=
                        // loss;
                )

            // Update strategy total loss and total debt, store in slot 2
            sstore(add(strategiesSlot, 2), slot2Content)
        }
    }

    /// @notice Issues new shares to cover performance, management and strategist fees
    /// @param strategy The strategy reporting the gain
    /// @return the total fees (performance + management + strategist) extracted from the gain
    function _assessFees(address strategy, uint256 gain, address managementFeeReceiver) internal returns (uint256) {
        bool success;
        uint256 slot0Content;
        assembly ("memory-safe") {
            // Get strategies[strategy] slot
            mstore(0x00, strategy)
            mstore(0x20, strategies.slot)
            // Get strategies[strategy] data
            slot0Content := sload(keccak256(0x00, 0x40))

            // If strategy was just added or no gains were reported, return 0 as fees
            // if (strategyData.strategyActivation == block.timestamp || gain == 0)
            if or(eq(shr(208, shl(176, slot0Content)), timestamp()), eq(gain, 0)) { success := 1 }
        }
        if (success) {
            return 0;
        }

        // Stack variables to cache
        uint256 duration;
        uint256 strategyPerformanceFee;
        uint256 computedManagementFee;
        uint256 computedStrategistFee;
        uint256 computedPerformanceFee;
        uint256 totalFee;

        assembly ("memory-safe") {
            // duration = block.timestamp - strategyData.strategyLastReport;
            duration := sub(timestamp(), shr(208, shl(128, slot0Content)))

            // if duration == 0
            if iszero(duration) {
                // throw the `FeesAlreadyAssesed` error
                mstore(0x00, 0x17de0c6e)
                revert(0x1c, 0x04)
            }

            // Cache strategy performance fee
            strategyPerformanceFee := shr(240, shl(224, slot0Content))

            // Load vault fees
            let managementFee_ := sload(managementFee.slot)
            let performanceFee_ := sload(performanceFee.slot)

            // Overflow check equivalent to require(managementFee_ == 0 || gain <= type(uint256).max / managementFee_)
            if iszero(iszero(mul(managementFee_, gt(gain, div(not(0), managementFee_))))) { revert(0, 0) }

            // Compute vault management fee
            // computedManagementFee = (gain * managementFee) / MAX_BPS
            computedManagementFee := div(mul(gain, managementFee_), MAX_BPS)

            // Overflow check equivalent to require(strategyPerformanceFee == 0 || gain <= type(uint256).max /
            // strategyPerformanceFee)
            if iszero(iszero(mul(strategyPerformanceFee, gt(gain, div(not(0), strategyPerformanceFee))))) {
                revert(0, 0)
            }

            // Compute strategist fee
            // computedStrategistFee = (gain * strategyData.strategyPerformanceFee) / MAX_BPS;
            computedStrategistFee := div(mul(gain, strategyPerformanceFee), MAX_BPS)

            // Overflow check equivalent to require(performanceFee_ == 0 || gain <= type(uint256).max / performanceFee_)
            if iszero(iszero(mul(performanceFee_, gt(gain, div(not(0), performanceFee_))))) { revert(0, 0) }

            // Compute vault performance fee
            // computedPerformanceFee = (gain * performanceFee) / MAX_BPS;
            computedPerformanceFee := div(mul(gain, performanceFee_), MAX_BPS)

            // totalFee = computedManagementFee + computedStrategistFee + computedPerformanceFee
            totalFee := add(add(computedManagementFee, computedStrategistFee), computedPerformanceFee)

            // Ensure total fee is not greater than the gain, set total fee to become the actual gain otherwise
            // if totalFee > gain
            if gt(totalFee, gain) {
                // totalFee = gain
                totalFee := gain
            }
        }

        // Only transfer shares if there are actual shares to transfer
        if (totalFee != 0) {
            // Compute corresponding shares and mint rewards to vault
            uint256 reward = _issueSharesForAmount(address(this), totalFee);

            // Transfer corresponding rewards in shares to strategist
            if (computedStrategistFee != 0) {
                uint256 strategistReward;
                assembly {
                    // Overflow check equivalent to require(reward == 0 || computedStrategistFee <= type(uint256).max /
                    // reward)
                    // No need to check for totalFee == 0 since it is checked in the if clause above
                    if iszero(iszero(mul(reward, gt(computedStrategistFee, div(not(0), reward))))) { revert(0, 0) }

                    // Compute strategist reward
                    // strategistReward = (computedStrategistFee * reward) / totalFee;
                    strategistReward := div(mul(computedStrategistFee, reward), totalFee)
                }
                // Transfer corresponding reward to strategist
                address(this).safeTransfer(IStrategy(strategy).strategist(), strategistReward);
            }

            // Treasury earns remaining shares (performance fee + management fee + any dust leftover from flooring math
            // above)
            uint256 cachedBalance = balanceOf(address(this));
            if (cachedBalance != 0) {
                // if the harvest was triggered by a regular user send management fee to
                // the user that endured the harvest
                if (managementFeeReceiver != address(0)) {
                    address(this).safeTransfer(managementFeeReceiver, cachedBalance * computedManagementFee / totalFee);
                    cachedBalance = balanceOf(address(this));
                }
                // transfer the rest of it to the treasury
                if (cachedBalance != 0) {
                    address(this).safeTransfer(treasury, cachedBalance);
                }
            }
        }

        assembly ("memory-safe") {
            // Emit the `FeesReported` event
            let m := mload(0x40)
            mstore(0x00, computedManagementFee)
            mstore(0x20, computedPerformanceFee)
            mstore(0x40, computedStrategistFee)
            mstore(0x60, duration)
            log1(0x00, 0x80, _FEES_REPORTED_EVENT_SIGNATURE)
            mstore(0x40, m)
            mstore(0x60, 0)
        }

        return totalFee;
    }

    /// @notice Amount of tokens in Vault a Strategy has access to as a credit line.
    /// This will check the Strategy's debt limit, as well as the tokens available in the
    /// Vault, and determine the maximum amount of tokens (if any) the Strategy may draw on
    /// @param strategy The strategy to check
    /// @return The quantity of tokens available for the Strategy to draw on
    function _creditAvailable(address strategy) internal view returns (uint256) {
        if (emergencyShutdown) return 0;

        // Compute necessary data regarding current state of the vault
        uint256 vaultTotalAssets = _totalDeposits();
        uint256 vaultDebtLimit = _computeDebtLimit(debtRatio, vaultTotalAssets);
        uint256 vaultTotalDebt = totalDebt;

        // Stack variables to cache
        bool success;
        uint256 slot;
        uint256 slot0Content;
        uint256 strategyTotalDebt;
        uint256 strategyDebtLimit;
        assembly ("memory-safe") {
            // Compute slot of strategies[strategy]
            mstore(0x00, strategy)
            mstore(0x20, strategies.slot)
            slot := keccak256(0x00, 0x40)
            // Load strategies[strategy].strategyTotalDebt
            strategyTotalDebt := shr(128, shl(128, sload(add(slot, 2))))

            // Load slot 0 content
            slot0Content := sload(slot)

            // Extract strategies[strategy].strategyDebtRatio
            let strategyDebtRatio := shr(240, shl(240, slot0Content))

            // Overflow check equivalent to require(vaultTotalAssets == 0 || strategyDebtRatio <= type(uint256).max /
            // vaultTotalAssets)
            if iszero(iszero(mul(vaultTotalAssets, gt(strategyDebtRatio, div(not(0), vaultTotalAssets))))) {
                revert(0, 0)
            }

            // Compute necessary data regarding current state of the strategy

            // strategyDebtLimit = (strategies[strategy].strategyDebtRatio * vaultTotalAssets) / MAX_BPS;
            strategyDebtLimit := div(mul(strategyDebtRatio, vaultTotalAssets), MAX_BPS)

            // If strategy current debt is already greater than the configured debt limit for that strategy,
            // or if the vault's current debt is already greater than the configured debt limit for that vault,
            // no credit should be given to the strategy
            // if strategies[strategy].strategyTotalDebt > strategyDebtLimit || vaultTotalDebt > vaultDebtLimit
            if or(gt(strategyTotalDebt, strategyDebtLimit), gt(vaultTotalDebt, vaultDebtLimit)) { success := 1 }
        }
        if (success) return 0;

        // Adjust by the vault debt limit left
        uint256 available;
        unchecked {
            available = Math.min(strategyDebtLimit - strategyTotalDebt, vaultDebtLimit - vaultTotalDebt);
        }

        // Adjust by the idle amount of underlying the vault has
        available = Math.min(available, totalIdle);

        assembly {
            // Adjust by min and max borrow limits per harvest

            // if (available < strategies[strategy].strategyMinDebtPerHarvest) return 0;
            if lt(available, shr(128, shl(128, sload(add(slot, 1))))) { success := 1 }
        }
        if (success) return 0;

        // Obtain strategies[strategy].strategyMaxDebtPerHarvest from the previously loaded slot0Content, this saves one
        // SLOAD
        uint256 strategyMaxDebtPerHarvest;
        assembly {
            strategyMaxDebtPerHarvest := shr(128, slot0Content)
        }
        return Math.min(available, strategyMaxDebtPerHarvest);
    }

    /// @notice Performs the debt limit calculation
    /// @param _debtRatio The debt ratio to use for computation
    /// @param totalAssets_ The amount of assets
    /// @return debtLimit The limit amount of assets allowed for the strategy, given the current debt ratio and total
    /// assets
    function _computeDebtLimit(uint256 _debtRatio, uint256 totalAssets_) internal pure returns (uint256 debtLimit) {
        assembly {
            // Overflow check equivalent to require(totalAssets_ == 0 || _debtRatio <= type(uint256).max / totalAssets_)
            if iszero(iszero(mul(totalAssets_, gt(_debtRatio, div(not(0), totalAssets_))))) { revert(0, 0) }
            // _debtRatio * totalAssets_ / MAX_BPS
            debtLimit := div(mul(_debtRatio, totalAssets_), MAX_BPS)
        }
    }

    /// @notice Determines if `strategy` is past its debt limit and if any tokens should be withdrawn to the Vault
    /// @param strategy The Strategy to check
    /// @return _debtOutstanding_ The quantity of tokens to withdraw
    function _debtOutstanding(address strategy) internal view returns (uint256 _debtOutstanding_) {
        uint256 strategyTotalDebt;
        uint256 strategyDebtRatio;
        assembly ("memory-safe") {
            // Get strategies[strategy] slot
            mstore(0x00, strategy)
            mstore(0x20, strategies.slot)
            let slot := keccak256(0x00, 0x40)
            // Obtain strategies[strategy].strategyTotalDebt from slot 2
            strategyTotalDebt := shr(128, shl(128, sload(add(slot, 2))))
            // Obtain strategies[strategy].strategyDebtRatio from slot 0
            strategyDebtRatio := shr(240, shl(240, sload(slot)))
        }
        // If debt ratio configured in vault is zero or emergency shutdown, any amount of debt in the strategy should be
        // returned
        if (debtRatio == 0 || emergencyShutdown) return strategyTotalDebt;

        uint256 strategyDebtLimit = _computeDebtLimit(strategyDebtRatio, _totalDeposits());

        // There will not be debt outstanding if strategy total debt is smaller or equal to the current debt limit
        if (strategyDebtLimit >= strategyTotalDebt) {
            return 0;
        }
        unchecked {
            _debtOutstanding_ = strategyTotalDebt - strategyDebtLimit;
        }
    }

    /// @notice Reorganize `withdrawalQueue` based on premise that if there is an
    /// empty value between two actual values, then the empty value should be
    /// replaced by the later value.
    /// @dev Relative ordering of non-zero values is maintained.
    function _organizeWithdrawalQueue() internal {
        uint256 offset;
        for (uint256 i; i < MAXIMUM_STRATEGIES;) {
            address strategy = withdrawalQueue[i];
            if (strategy == address(0)) {
                unchecked {
                    ++offset;
                }
            } else if (offset > 0) {
                withdrawalQueue[i - offset] = strategy;
                withdrawalQueue[i] = address(0);
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Revoke a Strategy, setting its debt limit to 0 and preventing any future deposits
    /// @param strategy The strategy to revoke
    /// @param strategyDebtRatio The strategy debt ratio
    function _revokeStrategy(address strategy, uint256 strategyDebtRatio) internal {
        debtRatio -= strategyDebtRatio;
        strategies[strategy].strategyDebtRatio = 0;
        assembly {
            log2(0x00, 0x00, _STRATEGY_REVOKED_EVENT_SIGNATURE, strategy)
        }
    }

    /// @notice Issues `amount` Vault shares to `to`
    /// @dev Shares must be issued prior to taking on new collateral, or calculation will be wrong
    /// This means that only *trusted* tokens (with no capability for exploitative behavior) can be used
    /// @param to The shares recipient
    /// @param amount The amount considered to compute the shares
    /// @return shares The amount of shares computed from the amount
    function _issueSharesForAmount(address to, uint256 amount) internal returns (uint256 shares) {
        shares = convertToShares(amount);
        assembly ("memory-safe") {
            // if shares == 0
            if iszero(shares) {
                // Throw the `InvalidZeroShares` error
                mstore(0x00, 0x5a870a25)
                revert(0x1c, 0x04)
            }
        }

        _mint(to, shares);
    }

    /// @dev Private helper to return if either value is zero.
    function _eitherIsZero_(uint256 a, uint256 b) internal pure virtual returns (bool result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := or(iszero(a), iszero(b))
        }
    }

    /// @dev Private helper to return the value plus one.
    function _inc_(uint256 x) internal pure virtual returns (uint256) {
        unchecked {
            return x + 1;
        }
    }

    /// @dev Private helper to substract a - b or return 0 if it underflows
    function _sub0(uint256 a, uint256 b) internal pure virtual returns (uint256) {
        unchecked {
            return a - b > a ? 0 : a - b;
        }
    }

    ////////////////////////////////////////////////////////////////
    ///                INTERNAL VIEW FUNCTIONS                   ///
    ////////////////////////////////////////////////////////////////

    /// @notice the number of decimals of the underlying token
    function _underlyingDecimals() internal view override returns (uint8) {
        return _decimals;
    }

    /// @dev Override to return a non-zero value to make the inflation attack even more unfeasible.
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }

    /// @notice Returns the estimate amount of assets held by the vault and strategy positions,
    /// including unrealised profit or losses
    /// @return totalAssets_ The total assets under control of this Vault
    function _totalAssets() internal view returns (uint256 totalAssets_) {
        // use accounted assets for the vault balance, prevents inflation attacks or similar
        totalAssets_ = totalIdle;
        address[MAXIMUM_STRATEGIES] memory _withdrawalQueue = withdrawalQueue;
        for (uint256 i; i < MAXIMUM_STRATEGIES;) {
            address strategy = _withdrawalQueue[i];
            // Check if we have exhausted the queue
            if (strategy == address(0)) break;
            totalAssets_ += IStrategy(strategy).estimatedTotalAssets();
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Returns the total quantity of all assets under control of this Vault,
    /// whether they're loaned out to a Strategy, or currently held in the Vault
    /// @return totalAssets_ The total assets under control of this Vault
    function _totalDeposits() internal view returns (uint256 totalAssets_) {
        assembly {
            let totalDebt_ := sload(totalDebt.slot)
            totalAssets_ := add(sload(totalIdle.slot), totalDebt_)

            // Perform overflow check
            if lt(totalAssets_, totalDebt_) { revert(0, 0) }
        }
    }

    ////////////////////////////////////////////////////////////////
    ///                EXTERNAL VIEW FUNCTIONS                   ///
    ////////////////////////////////////////////////////////////////

    /// @notice Returns the name of the vault shares token.
    function name() public view override returns (string memory) {
        return _name;
    }

    /// @notice Returns the symbol of the token.
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /// @notice Returns the address of the underlying asset.
    function asset() public view override returns (address) {
        return _underlyingAsset;
    }

    /// @notice Returns the total amount of the underlying asset managed by the Vault.
    function totalAssets() public view override returns (uint256) {
        return _totalAssets();
    }

    /// @notice Returns the total amount of accounted idle and strategy debt assets
    function totalDeposits() public view returns (uint256) {
        return _totalDeposits();
    }

    /// @notice Returns the maximum amount of the underlying asset that can be deposited
    /// into the Vault for `to`, via a deposit call.
    function maxDeposit(address /*to*/ ) public view override returns (uint256 maxAssets) {
        /// @dev use sub0 to prevent underflow
        return _sub0(depositLimit, totalAssets());
    }

    /// @notice Returns the maximum amount of the Vault shares that can be minter for `to`,
    /// via a mint call.
    function maxMint(address /*to*/ ) public view override returns (uint256 maxShares) {
        return convertToShares(maxDeposit(address(0)));
    }

    /// @notice Returns the maximum amount of the underlying asset that can be withdrawn
    /// from the `owner`'s balance in the Vault, via a withdraw call.
    function maxWithdraw(address owner) public view override returns (uint256 maxAssets) {
        return previewRedeem(maxRedeem(owner) * 99 / 100);
    }

    /// @notice Returns the estimate price of 1 vault share
    function sharePrice() external view returns (uint256) {
        return convertToAssets(10 ** decimals());
    }

    /// @notice Returns the amount of shares that the Vault will exchange for the amount of
    /// assets provided, in an ideal scenario where all conditions are met.
    /// @dev some the virtual shares and decimal offset checks have been removed for further
    /// gas optimization
    function convertToShares(uint256 assets) public view override returns (uint256 shares) {
        uint256 o = _decimalsOffset();
        return Math.fullMulDiv(assets, totalSupply() + 10 ** o, _inc_(_totalAssets()));
    }

    /// @dev Returns the amount of assets that the Vault will exchange for the amount of
    /// shares provided, in an ideal scenario where all conditions are met.
    /// @dev some the virtual shares and decimal offset checks have been removed for further
    /// gas optimization
    function convertToAssets(uint256 shares) public view override returns (uint256 assets) {
        uint256 o = _decimalsOffset();
        return Math.fullMulDiv(shares, _totalAssets() + 1, totalSupply() + 10 ** o);
    }

    /// @dev Allows an on-chain or off-chain user to simulate the effects of their mint
    /// at the current block, given current on-chain conditions.
    function previewMint(uint256 shares) public view override returns (uint256 assets) {
        uint256 o = _decimalsOffset();
        return Math.fullMulDivUp(shares, _totalAssets() + 1, totalSupply() + 10 ** o);
    }

    /// @dev Allows an on-chain or off-chain user to simulate the effects of their withdrawal
    /// at the current block, given the current on-chain conditions.
    function previewWithdraw(uint256 assets) public view override returns (uint256 shares) {
        if (assets == 0) return 0;
        if (assets == type(uint256).max) assets = convertToAssets(balanceOf(msg.sender));

        uint256 _totalAssets_ = _totalAssets();
        uint256 vaultBalance = totalIdle;
        uint256 o = _decimalsOffset();
        // convert the assets to shares without any losses
        // very important: ROUND UP
        shares = Math.fullMulDivUp(assets, totalSupply() + 10 ** o, _inc_(_totalAssets_));

        // in case the vault's balance doesn't cover the requested `assets`
        if (assets > vaultBalance) {
            // Vault balance is not enough to cover withdrawal. We need to perform forced withdrawals
            // from strategies until requested value amount is covered.
            // During forced withdrawal, the vault will do exact amount requests to the strategies
            // and account the losses needed to achieve those amounts. Those
            // losses are reported back to the vault This will affect the withdrawer, affecting the amount of shares
            // that will
            // burn in order to withdraw exactly @param assets assets

            uint256 totalLoss;
            // Iterate over strategies
            for (uint256 i; i < MAXIMUM_STRATEGIES;) {
                address strategy = withdrawalQueue[i];

                // Check if we have exhausted the queue
                if (strategy == address(0)) break;

                // Check if the vault balance is finally enough to cover the requested withdrawal
                if (vaultBalance >= assets) break;

                // Compute remaining amount to request considering the current balance of the vault
                uint256 amountRequested = assets - vaultBalance;
                // Can't request more than allowed by the strategy
                amountRequested = Math.min(amountRequested, IStrategy(strategy).maxLiquidateExact());

                // Try the next strategy if the current strategy has no debt to be withdrawn
                if (amountRequested == 0) {
                    unchecked {
                        ++i;
                    }
                    continue;
                }

                // Withdraw from strategy. Compute amount withdrawn(should be requestedAmount)
                // considering the difference between balances pre/post withdrawal
                uint256 withdrawn = IStrategy(strategy).previewLiquidateExact(amountRequested);
                uint256 loss = withdrawn - amountRequested;

                // increase the vault balance by requested amount
                vaultBalance += amountRequested;

                // If loss has been realised, withdrawer will incur it, affecting to the amount
                // of shares that the user will burn
                if (loss != 0) {
                    totalLoss += loss;
                }

                unchecked {
                    ++i;
                }
            }
            // Increase the shares if there are any losses
            shares += Math.fullMulDivUp(totalLoss, totalSupply() + 10 ** o, _inc_(_totalAssets_));
        }

        // if there are more assets to cover(when requesting more assets then total)
        // we add the extra shares needed, even though it would revert if someone tries
        // to withdraw that much since they wouln't have the needed shares
        if (vaultBalance < assets) {
            shares += Math.fullMulDivUp(assets - vaultBalance, totalSupply() + 10 ** o, _inc_(_totalAssets_));
        }
    }

    /// @dev Allows an on-chain or off-chain user to simulate the effects of their redemption
    /// at the current block, given current on-chain conditions.
    function previewRedeem(uint256 shares) public view override returns (uint256 assets) {
        if (shares == 0) return 0;
        if (shares == type(uint256).max) shares = balanceOf(msg.sender);

        assets = convertToAssets(shares);

        uint256 vaultBalance = totalIdle;

        if (vaultBalance >= assets) {
            return assets;
        } else {
            // Iterate over strategies
            for (uint256 i; i < MAXIMUM_STRATEGIES;) {
                address strategy = withdrawalQueue[i];

                // Check if we have exhausted the queue
                if (strategy == address(0)) break;

                // Check if the vault balance is finally enough to cover the requested withdrawal
                if (vaultBalance >= assets) break;

                // Compute remaining amount to withdraw considering the current balance of the vault
                uint256 amountRequested;
                assembly ("memory-safe") {
                    // amountRequested = assets - vaultBalance;
                    amountRequested := sub(assets, vaultBalance)
                }

                // ask for the min between the needed amount and max withdraw of the strategy
                amountRequested = Math.min(amountRequested, IStrategy(strategy).maxLiquidate());

                // Try the next strategy if the current strategy has no debt to be withdrawn
                if (amountRequested == 0) {
                    unchecked {
                        ++i;
                    }
                    continue;
                }

                // Withdraw from strategy. Compute amount withdrawn
                // considering the difference between balances pre/post withdrawal
                uint256 withdrawn = IStrategy(strategy).previewLiquidate(amountRequested);
                uint256 loss = amountRequested - withdrawn;

                // Increase cached vault balance to track the newly withdrawn amount
                vaultBalance += withdrawn;

                if (loss != 0) {
                    assets -= loss;
                }
                unchecked {
                    ++i;
                }
            }
        }
    }

    ////////////////////////////////////////////////////////////////
    ///                 DEPOSIT/WITHDRAWAL LOGIC                 ///
    ////////////////////////////////////////////////////////////////

    /// @notice Mints `shares` Vault shares to `to` by depositing exactly `assets`
    /// of underlying tokens.
    /// @dev overriden to add the `noEmergencyShutdown` & `nonReentrant` modifiers
    /// @dev reverts with custom `VaultDepositLimitExceeded` error instead of Solady's `DepositMoreThanMax`
    function deposit(
        uint256 assets,
        address receiver
    )
        public
        virtual
        override
        noEmergencyShutdown
        nonReentrant
        returns (uint256 shares)
    {
        uint256 _maxDeposit = maxDeposit(msg.sender);
        assembly ("memory-safe") {
            if gt(assets, _maxDeposit) {
                // throw the `VaultDepositLimitExceeded` error
                mstore(0x00, 0x0c11966b)
                revert(0x1c, 0x04)
            }
        }
        _deposit(msg.sender, receiver, assets, shares = previewDeposit(assets));
    }

    /// @notice Mints exactly `shares` Vault shares to `to` by depositing `assets`
    /// of underlying tokens.
    /// @dev overriden to add the `noEmergencyShutdown` & `nonReentrant` modifiers
    /// @dev reverts with custom `VaultDepositLimitExceeded` error instead of Solady's `MinttMoreThanMax`
    function mint(
        uint256 shares,
        address receiver
    )
        public
        virtual
        override
        noEmergencyShutdown
        nonReentrant
        returns (uint256 assets)
    {
        uint256 _maxMint = maxMint(msg.sender);
        assembly ("memory-safe") {
            if gt(shares, _maxMint) {
                // throw the `VaultDepositLimitExceeded` error
                mstore(0x00, 0x0c11966b)
                revert(0x1c, 0x04)
            }
        }
        _deposit(msg.sender, receiver, assets = previewMint(shares), shares);
    }

    /// @dev override the Solady's internal function to add extra checks
    function _deposit(address by, address to, uint256 assets, uint256 shares) internal override {
        asset().safeTransferFrom(by, address(this), assets);
        uint256 totalIdle_;
        assembly ("memory-safe") {
            // if to == address(0)
            if iszero(shl(96, to)) {
                // throw the `InvalidZeroAddress` error
                mstore(0x00, 0xf6b2911f)
                revert(0x1c, 0x04)
            }
            // if assets == 0
            if iszero(assets) {
                // throw the `InvalidZeroAmount` error
                mstore(0x00, 0xdd484e70)
                revert(0x1c, 0x04)
            }

            // Get totalDeposits
            totalIdle_ := sload(totalIdle.slot)
            let totalAssets_ := add(totalIdle_, sload(totalDebt.slot))
            if lt(totalAssets_, totalIdle_) { revert(0, 0) }

            // check if totalDeposits + assets overflows
            let total := add(totalAssets_, assets)
            if lt(total, totalAssets_) { revert(0, 0) }
        }

        assembly ("memory-safe") {
            // if shares == 0
            if iszero(shares) {
                // Throw the `InvalidZeroShares` error
                mstore(0x00, 0x5a870a25)
                revert(0x1c, 0x04)
            }
        }

        _mint(to, shares);
        assembly ("memory-safe") {
            sstore(totalIdle.slot, add(totalIdle_, assets))
            // Emit the {Deposit} event.
            mstore(0x00, assets)
            mstore(0x20, shares)
            let m := shr(96, not(0))
            log3(0x00, 0x40, _DEPOSIT_EVENT_SIGNATURE, and(m, by), and(m, to))
        }
        // if autipilot is enabled and > 1 week from last harvest check if there is any strategy in autopilot
        // and harvest one strategy
        if (autoPilotEnabled && lastReport + AUTOPILOT_HARVEST_INTERVAL < block.timestamp) {
            // `to` will receive the extra shares from the management fees
            (address strategy, bool success, bytes memory reason) = _forceOneHarvest(to);
            if (!success) {
                emit ForceHarvestFailed(strategy, reason);
            }
        }
    }

    /// @notice Burns `shares` from `owner` and sends exactly `assets` of underlying tokens to `to`.
    /// @dev overriden to add the `noEmergencyShutdown` & `nonReentrant` modifiers
    function withdraw(
        uint256 assets,
        address to,
        address owner
    )
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        if (assets == type(uint256).max) assets = maxWithdraw(owner);
        if (assets > maxWithdraw(owner)) {
            assembly ("memory-safe") {
                mstore(0x00, 0x936941fc) // `WithdrawMoreThanMax()`.
                revert(0x1c, 0x04)
            }
        }
        shares = _withdraw(msg.sender, to, owner, assets);
    }

    /// @notice Burns exactly `shares` from `owner` and sends `assets` of underlying tokens to `to`.
    /// @dev overriden to add the `noEmergencyShutdown` & `nonReentrant` modifiers
    function redeem(uint256 shares, address to, address owner) public override nonReentrant returns (uint256 assets) {
        if (shares == type(uint256).max) shares = maxRedeem(owner);
        if (shares > maxRedeem(owner)) {
            assembly ("memory-safe") {
                mstore(0x00, 0x4656425a) // `RedeemMoreThanMax()`.
                revert(0x1c, 0x04)
            }
        }

        // substract losses to the total assets
        assets = _redeem(msg.sender, to, owner, shares);
    }

    /// @dev Withdraws the needed amount of assets realising losses such as slippage
    /// @return assets the real amount of assets withdrawn
    function _redeem(address by, address to, address owner, uint256 shares) private returns (uint256 assets) {
        if (by != owner) {
            _spendAllowance(owner, by, shares);
        }
        assembly ("memory-safe") {
            // if shares == 0
            if iszero(shares) {
                // throw the `InvalidZeroShares` error
                mstore(0x00, 0x5a870a25)
                revert(0x1c, 0x04)
            }
        }

        // Calculate assets from shares
        assets = convertToAssets(shares);

        // Cache underlying asset
        address underlying = asset();
        uint256 vaultBalance = totalIdle;

        // Check if value to withdraw exceeds vault balance
        if (assets > vaultBalance) {
            // Vault balance is not enough to cover withdrawal. We need to perform forced withdrawals
            // from strategies until requested value amount is covered.
            // During forced withdrawal, a Strategy may realize a loss, which is reported back to the
            // Vault. This will affect the withdrawer, affecting the amount of tokens they will
            // receive in exchange for their shares.

            uint256 totalLoss;

            // Iterate over strategies
            for (uint256 i; i < MAXIMUM_STRATEGIES;) {
                address strategy = withdrawalQueue[i];

                // Check if we have exhausted the queue
                if (strategy == address(0)) break;

                // Check if the vault balance is finally enough to cover the requested withdrawal
                if (vaultBalance >= assets) break;

                uint256 slotStrategies2;
                assembly {
                    // cache slot strategies[strategy].strategyTotalDebt
                    mstore(0x00, strategy)
                    mstore(0x20, strategies.slot)
                    slotStrategies2 := add(keccak256(0x00, 0x40), 2)
                }

                // Compute remaining amount to withdraw considering the current balance of the vault
                uint256 amountRequested;
                assembly ("memory-safe") {
                    // amountRequested = assets - vaultBalance;
                    amountRequested := sub(assets, vaultBalance)
                }
                // ask for the min between the needed amount and max withdraw of the strategy
                amountRequested = Math.min(amountRequested, IStrategy(strategy).maxLiquidate());

                // Try the next strategy if the current strategy has no debt to be withdrawn
                if (amountRequested == 0) {
                    unchecked {
                        ++i;
                    }
                    continue;
                }

                // Withdraw from strategy. Compute amount withdrawn
                // considering the difference between balances pre/post withdrawal
                uint256 preBalance = SafeTransferLib.balanceOf(underlying, address(this));

                uint256 withdrawn;
                uint256 loss;
                // Use try/catch logic to avoid DoS
                try IStrategy(strategy).liquidate(amountRequested) returns (uint256 _loss) {
                    loss = _loss;
                    withdrawn = SafeTransferLib.balanceOf(underlying, address(this)) - preBalance;
                } catch {
                    unchecked {
                        ++i;
                    }
                    continue;
                }

                if (withdrawn == 0) {
                    unchecked {
                        ++i;
                    }
                    continue;
                }

                // Increase cached vault balance to track the newly withdrawn amount
                vaultBalance += withdrawn;

                // If loss has been realised, withdrawer will incur it, affecting to the amount
                // of value they will receive in exchange for their shares
                if (loss != 0) {
                    assets -= loss;
                    totalLoss += loss;
                    _reportLoss(strategy, loss);
                }

                // If the strategy has unharvested profit we could end up withdrawing more than its debt
                // Then we will only decrease his debt by the strategy's debt
                uint256 debtReduction = Math.min(strategies[strategy].strategyTotalDebt, withdrawn);
                unchecked {
                    totalDebt = totalDebt - debtReduction;
                }

                uint128 strategyTotalDebt = uint128(strategies[strategy].strategyTotalDebt - debtReduction);

                strategies[strategy].strategyTotalDebt = strategyTotalDebt;

                assembly ("memory-safe") {
                    // Emit the `WithdrawFromStrategy` event
                    mstore(0x00, strategyTotalDebt)
                    mstore(0x20, loss)
                    log2(0x00, 0x40, _WITHDRAW_FROM_STRATEGY_EVENT_SIGNATURE, strategy)
                }

                unchecked {
                    ++i;
                }
            }

            // Update total idle with the actual vault balance that considers the total withdrawn amount
            totalIdle = vaultBalance;

            assembly ("memory-safe") {
                let sum := add(assets, totalLoss)
                if lt(sum, assets) {
                    // throw the `Overflow` error
                    revert(0, 0)
                }
            }
        }

        assembly ("memory-safe") {
            if eq(assets, 0x00) {
                // throw the `InvalidZeroAmount` error
                mstore(0x00, 0xdd484e70)
                revert(0x1c, 0x04)
            }
        }

        // Burn shares
        _burn(owner, shares);

        // Reduce value withdrawn from vault total idle
        if (assets > totalIdle) {
            assets = totalIdle;
        }

        assembly ("memory-safe") {
            if iszero(assets) {
                // throw the `InvalidZeroAmount` error
                mstore(0x00, 0xdd484e70)
                revert(0x1c, 0x04)
            }
        }

        unchecked {
            totalIdle -= assets;
        }

        // Transfer underlying to `recipient`
        SafeTransferLib.safeTransfer(underlying, to, assets);
        assembly ("memory-safe") {
            // Emit the {Withdraw} event.
            mstore(0x00, assets)
            mstore(0x20, shares)
            let m := shr(96, not(0))
            log4(0x00, 0x40, _WITHDRAW_EVENT_SIGNATURE, and(m, by), and(m, to), and(m, owner))
        }

        return assets;
    }

    /// @dev Burns the needed amount of shares to withdraw @param assets after realising loses
    /// @return shares the real amount shares burnt
    function _withdraw(address by, address to, address owner, uint256 assets) private returns (uint256 shares) {
        assembly ("memory-safe") {
            // if assets == 0
            if iszero(assets) {
                // throw the `InvalidZeroAmount` error
                mstore(0x00, 0xdd484e70)
                revert(0x1c, 0x04)
            }
        }

        uint256 _totalAssets_ = _totalAssets();
        uint256 vaultBalance = totalIdle;
        uint256 o = _decimalsOffset();
        address underlying = asset();
        // convert the assets to shares without any losses
        // very important: ROUND UP
        shares = Math.fullMulDivUp(assets, totalSupply() + 10 ** o, _inc_(_totalAssets_));

        // in case the vault's balance doesn't cover the requested `assets`
        if (assets > vaultBalance) {
            // Vault balance is not enough to cover withdrawal. We need to perform forced withdrawals
            // from strategies until requested value amount is covered.
            // During forced withdrawal, the vault will do exact amount requests to the strategies
            // and account the losses needed to achieve those amounts. Those
            // losses are reported back to the vault This will affect the withdrawer, affecting the amount of shares
            // that will
            // burn in order to withdraw exactly @param assets assets

            uint256 totalLoss;
            // Iterate over strategies
            for (uint256 i; i < MAXIMUM_STRATEGIES;) {
                address strategy = withdrawalQueue[i];

                // Check if we have exhausted the queue
                if (strategy == address(0)) break;

                // Check if the vault balance is finally enough to cover the requested withdrawal
                if (vaultBalance >= assets) break;

                // Compute remaining amount to withdraw considering the current balance of the vault
                uint256 amountRequested = assets - vaultBalance;
                // Can't request more than allowed by the strategy
                amountRequested = Math.min(amountRequested, IStrategy(strategy).maxLiquidateExact());

                // Try the next strategy if the current strategy has no debt to be withdrawn
                if (amountRequested == 0) {
                    unchecked {
                        ++i;
                    }
                    continue;
                }

                // Withdraw from strategy. Compute amount withdrawn(should be requestedAmount)
                // considering the difference between balances pre/post withdrawal
                uint256 preBalance = underlying.balanceOf(address(this));

                uint256 withdrawn;

                uint256 loss;
                // Use try/catch logic to avoid DoS
                try IStrategy(strategy).liquidateExact(amountRequested) returns (uint256 _loss) {
                    loss = _loss;
                    withdrawn = SafeTransferLib.balanceOf(underlying, address(this)) - preBalance;
                } catch {
                    unchecked {
                        ++i;
                    }
                    continue;
                }

                if (withdrawn == 0) {
                    unchecked {
                        ++i;
                    }
                    continue;
                }

                // increase the vault balance by the needed amount
                vaultBalance += withdrawn;

                // If loss has been realised, withdrawer will incur it, affecting to the amount
                // of shares that the user will burn
                if (loss != 0) {
                    totalLoss += loss;
                    _reportLoss(strategy, loss);
                }

                // If the strategy has unharvested profit we could end up withdrawing more than its debt
                // Then we will only decrease his debt by the strategy's debt
                uint256 debtReduction = Math.min(strategies[strategy].strategyTotalDebt, withdrawn);
                unchecked {
                    totalDebt = totalDebt - debtReduction;
                }

                uint128 strategyTotalDebt = uint128(strategies[strategy].strategyTotalDebt - debtReduction);

                strategies[strategy].strategyTotalDebt = strategyTotalDebt;

                assembly ("memory-safe") {
                    // Emit the `WithdrawFromStrategy` event
                    mstore(0x00, strategyTotalDebt)
                    mstore(0x20, loss)
                    log2(0x00, 0x40, _WITHDRAW_FROM_STRATEGY_EVENT_SIGNATURE, strategy)
                }

                unchecked {
                    ++i;
                }
            }

            // Update total idle with the actual vault balance that considers the total withdrawn amount
            totalIdle = vaultBalance;
            // Increase the shares if there are any losses
            shares += Math.fullMulDivUp(totalLoss, totalSupply() + 10 ** o, _inc_(_totalAssets_));

            // if there are more assets to cover(when requesting more assets then total)
            // we add the extra shares needed, even though it would revert if someone tries
            // to withdraw that much since they wouln't have the needed shares
            if (vaultBalance < assets) {
                shares += Math.fullMulDivUp(assets - vaultBalance, totalSupply() + 10 ** o, _inc_(_totalAssets_));
            }
        }

        // spend allowance
        if (by != owner) {
            _spendAllowance(owner, by, shares);
        }

        // Burn shares
        _burn(owner, shares);

        // Reduce value withdrawn from vault total idle
        if (assets > totalIdle) {
            revert();
        }
        unchecked {
            totalIdle -= assets;
        }

        // Transfer underlying to `recipient`
        SafeTransferLib.safeTransfer(underlying, to, assets);

        assembly ("memory-safe") {
            // Emit the {Withdraw} event.
            mstore(0x00, assets)
            mstore(0x20, shares)
            let m := shr(96, not(0))
            log4(0x00, 0x40, _WITHDRAW_EVENT_SIGNATURE, and(m, by), and(m, to), and(m, owner))
        }
    }

    ////////////////////////////////////////////////////////////////
    ///                      REPORT LOGIC                        ///
    ////////////////////////////////////////////////////////////////

    /// @notice  Reports the amount of assets the calling Strategy has free (usually in terms of ROI).
    /// The performance fee is determined here, off of the strategy's profits (if any), and sent to governance.
    /// The strategist's fee is also determined here (off of profits), to be handled according to the strategist on the
    /// next harvest.
    /// @dev For approved strategies, this is the most efficient behavior. The Strategy reports back what it has free,
    /// then
    /// Vault "decides" whether to take some back or give it more.
    /// Note that the most it can take is `gain + debtPayment`, and the most it can give is all of the
    /// remaining reserves. Anything outside of those bounds is abnormal behavior
    /// @param unrealizedGain Amount Strategy accounted as gain on its investment since its last report
    /// @param loss Amount Strategy has realized as a loss on its investment since its last report, and should be
    /// accounted for on the Vault's balance sheet. The loss will reduce the debtRatio for the strategy and vault.
    /// The next time the strategy will harvest, it will pay back the debt in an attempt to adjust to the new debt
    /// limit.
    /// @param debtPayment Amount Strategy has made available to cover outstanding debt
    /// @param managementFeeReceiver Address receiving the protocol fees
    /// @return debt Amount of debt outstanding (if totalDebt > debtLimit or emergency shutdown).
    function report(
        uint128 unrealizedGain,
        uint128 loss,
        uint128 debtPayment,
        address managementFeeReceiver
    )
        external
        checkRoles(STRATEGY_ROLE)
        returns (uint256)
    {
        // Cache underlying asset
        address underlying = asset();
        // Cache strategy balance
        uint256 senderBalance = SafeTransferLib.balanceOf(underlying, msg.sender);

        assembly ("memory-safe") {
            // if (underlying.balanceOf(msg.sender) < realizedGain + debtPayment)
            if lt(senderBalance, debtPayment) {
                // throw the `InvalidReportedGainAndDebtPayment` error
                mstore(0x00, 0x746feeec)
                revert(0x1c, 0x04)
            }
        }

        // If strategy suffered a loss, report it
        if (loss > 0) {
            _reportLoss(msg.sender, loss);
        }

        uint256 _totalFees = _assessFees(msg.sender, uint256(unrealizedGain), managementFeeReceiver);
        // silence compiler warnings
        _totalFees;

        // Set reported gains as gains for the vault
        strategies[msg.sender].strategyTotalUnrealizedGain += unrealizedGain;

        // Compute the line of credit the Vault is able to offer the Strategy (if any)
        uint256 credit = _creditAvailable(msg.sender);

        // Compute excess of debt the Strategy wants to transfer back to the Vault (if any)
        uint256 debt = strategies[msg.sender].strategyTotalDebt;

        uint256 totalReportedAmount = debtPayment;

        // Adjust excess of reported debt payment by the debt outstanding computed
        debtPayment = uint128(Math.min(uint256(debtPayment), debt));

        if (debtPayment != 0) {
            strategies[msg.sender].strategyTotalDebt -= debtPayment;
            totalDebt -= debtPayment;
            debt -= debtPayment;
        }

        // Update the actual debt based on the full credit we are extending to the Strategy
        if (credit != 0) {
            strategies[msg.sender].strategyTotalDebt += uint128(credit);
            totalDebt += credit;
        }

        // Give/take corresponding amount to/from Strategy, based on the debt needed to be paid off (if any)
        unchecked {
            if (credit > totalReportedAmount) {
                // Credit is greater than the amount reported by the strategy, send funds **to** strategy
                totalIdle -= (credit - totalReportedAmount);
                SafeTransferLib.safeTransfer(underlying, msg.sender, credit - totalReportedAmount);
            } else if (totalReportedAmount > credit) {
                // Amount reported by the strategy is greater than the credit, take funds **from** strategy
                totalIdle += (totalReportedAmount - credit);
                asset().safeTransferFrom(msg.sender, address(this), totalReportedAmount - credit);
            }

            // else don't do anything (credit and reported amounts are balanced, hence no transfers need to be executed)
        }

        // Update reporting time
        strategies[msg.sender].strategyLastReport = uint48(block.timestamp);
        lastReport = block.timestamp;

        emit StrategyReported(
            msg.sender,
            unrealizedGain,
            loss,
            debtPayment,
            strategies[msg.sender].strategyTotalUnrealizedGain,
            strategies[msg.sender].strategyTotalLoss,
            strategies[msg.sender].strategyTotalDebt,
            credit,
            strategies[msg.sender].strategyDebtRatio
        );

        if (strategies[msg.sender].strategyDebtRatio == 0 || emergencyShutdown) {
            // Take every last penny the Strategy has (Emergency Exit/revokeStrategy)
            return IStrategy(msg.sender).estimatedTotalAssets();
        }

        // Otherwise, just return what we have as debt outstanding
        return _debtOutstanding(msg.sender);
    }

    ////////////////////////////////////////////////////////////////
    ///                STRATEGIES CONFIGURATION                  ///
    ////////////////////////////////////////////////////////////////

    /// @notice Adds a new strategy
    /// @dev The Strategy will be appended to `withdrawalQueue`, and `_organizeWithdrawalQueue` will reorganize the
    /// queue order
    /// @param newStrategy The new strategy to add
    /// @param strategyDebtRatio The percentage of the total assets in the vault that the `newStrategy` has access to
    /// @param strategyMaxDebtPerHarvest Lower limit on the increase of debt since last harvest
    /// @param strategyMinDebtPerHarvest Upper limit on the increase of debt since last harvest
    /// @param strategyPerformanceFee The fee the strategist will receive based on this Vault's performance
    function addStrategy(
        address newStrategy,
        uint256 strategyDebtRatio,
        uint256 strategyMaxDebtPerHarvest,
        uint256 strategyMinDebtPerHarvest,
        uint256 strategyPerformanceFee
    )
        external
        checkRoles(ADMIN_ROLE)
        noEmergencyShutdown
    {
        uint256 slot; // Slot where strategies[newStrategy] slot will be stored

        assembly ("memory-safe") {
            // General checks

            // if (withdrawalQueue[MAXIMUM_STRATEGIES - 1] != address(0))
            if sload(add(withdrawalQueue.slot, sub(MAXIMUM_STRATEGIES, 1))) {
                // throw `QueueIsFull()` error
                mstore(0x00, 0xa3d0cff3)
                revert(0x1c, 0x04)
            }

            // Strategy checks
            // if (newStrategy == address(0))
            if iszero(newStrategy) {
                // throw `InvalidZeroAddress()` error
                mstore(0x00, 0xf6b2911f)
                revert(0x1c, 0x04)
            }

            // Compute strategies[newStrategy] slot
            mstore(0x00, newStrategy)
            mstore(0x20, strategies.slot)
            slot := keccak256(0x00, 0x40)

            // if (strategies[newStrategy].strategyActivation != 0)
            if shr(208, shl(176, sload(slot))) {
                // throw `StrategyAlreadyActive()` error
                mstore(0x00, 0xc976754d)
                revert(0x1c, 0x04)
            }
        }
        if (IStrategy(newStrategy).vault() != address(this)) {
            assembly ("memory-safe") {
                // throw `InvalidStrategyVault()` error
                mstore(0x00, 0xac4e0773)
                revert(0x1c, 0x04)
            }
        }
        if (IStrategy(newStrategy).underlyingAsset() != asset()) {
            assembly ("memory-safe") {
                // throw `InvalidStrategyUnderlying()` error
                mstore(0x00, 0xf083d3f1)
                revert(0x1c, 0x04)
            }
        }

        if (IStrategy(newStrategy).strategist() == address(0)) {
            assembly ("memory-safe") {
                // throw `StrategyMustHaveStrategist()` error
                mstore(0x00, 0xeb8bf8b6)
                revert(0x1c, 0x04)
            }
        }

        uint256 debtRatio_;
        assembly ("memory-safe") {
            debtRatio_ := sload(debtRatio.slot)
            // Compute debtRatio + strategyDebtRatio
            let sum := add(debtRatio_, strategyDebtRatio)
            if lt(sum, strategyDebtRatio) {
                // throw the `Overflow` error
                revert(0, 0)
            }

            // if (debtRatio + strategyDebtRatio > MAX_BPS)
            if gt(sum, MAX_BPS) {
                // throw the `InvalidDebtRatio` error
                mstore(0x00, 0x79facb0d)
                revert(0x1c, 0x04)
            }

            // if (strategyMinDebtPerHarvest > strategyMaxDebtPerHarvest)
            if gt(strategyMinDebtPerHarvest, strategyMaxDebtPerHarvest) {
                // throw the `InvalidMinDebtPerHarvest` error
                mstore(0x00, 0x5f3bd953)
                revert(0x1c, 0x04)
            }

            // if (strategyPerformanceFee > 5000)
            if gt(strategyPerformanceFee, 5000) {
                // throw the `InvalidPerformanceFee` error
                mstore(0x00, 0xf14508d0)
                revert(0x1c, 0x04)
            }

            // Add strategy to strategies mapping
            // Strategy struct
            // StrategyData({
            //     strategyPerformanceFee: uint16(strategyPerformanceFee),
            //     strategyDebtRatio: uint16(strategyDebtRatio),
            //     strategyActivation: uint48(block.timestamp),
            //     strategyLastReport: uint48(block.timestamp),
            //     strategyMaxDebtPerHarvest: uint128(strategyMaxDebtPerHarvest),
            //     strategyMinDebtPerHarvest: uint128(strategyMinDebtPerHarvest),
            //     strategyTotalDebt: 0,
            //     strategyTotalUnrealizedGain: 0,
            //     strategyTotalLoss: 0
            // });

            // Using yul saves 5k gas, bitmasks are used to create the `StrategyData` struct above.
            // Slot 0 and slot 1 will be updated. Slot 2 is not updated since it stores `strategyTotalDebt`
            // and `strategyTotalLoss`, which will remain with a value of 0 upon strategy addition.

            // Store data for slot 0 in strategies[newStrategy]
            sstore(
                slot,
                or(
                    shl(128, strategyMaxDebtPerHarvest),
                    or(
                        shl(80, and(0xffffffffffff, timestamp())), // Set `strategyLastReport` to `block.timestamp`
                        or(
                            shl(32, and(0xffffffffffff, timestamp())), // Set `strategyActivation` to `block.timestamp`
                            or(shl(16, and(0xffff, strategyPerformanceFee)), and(0xffff, strategyDebtRatio))
                        )
                    )
                )
            )

            // Store data for slot 1 in strategies[newStrategy]
            sstore(add(slot, 1), shr(128, shl(128, strategyMinDebtPerHarvest)))
        }

        // Grant `STRATEGY_ROLE` to strategy
        _grantRoles(newStrategy, STRATEGY_ROLE);

        assembly {
            // Update vault parameters
            // debtRatio += strategyDebtRatio;
            sstore(debtRatio.slot, add(debtRatio_, strategyDebtRatio))
            // Add strategy to withdrawal queue
            // withdrawalQueue[MAXIMUM_STRATEGIES - 1] = newStrategy;
            sstore(add(withdrawalQueue.slot, sub(MAXIMUM_STRATEGIES, 1)), newStrategy)
        }

        _organizeWithdrawalQueue();

        assembly ("memory-safe") {
            // Emit the `StrategyAdded` event
            mstore(0x00, strategyDebtRatio)
            mstore(0x20, strategyMaxDebtPerHarvest)
            mstore(0x40, strategyMinDebtPerHarvest)
            mstore(0x60, strategyPerformanceFee)
            log2(0x00, 0x80, _STRATEGY_ADDED_EVENT_SIGNATURE, newStrategy)
        }
    }

    /// @notice Removes a strategy from the queue
    /// @dev  We don't do this with `revokeStrategy` because it should still be possible to withdraw from the Strategy
    /// if it's unwinding.
    /// @param strategy The strategy to remove
    function removeStrategy(address strategy) external checkRoles(ADMIN_ROLE) noEmergencyShutdown {
        address[MAXIMUM_STRATEGIES] memory cachedWithdrawalQueue = withdrawalQueue;
        for (uint256 i; i < MAXIMUM_STRATEGIES;) {
            if (cachedWithdrawalQueue[i] == strategy) {
                // The strategy was found and can be removed
                withdrawalQueue[i] = address(0);

                _removeRoles(strategy, STRATEGY_ROLE);

                // Update withdrawal queue
                _organizeWithdrawalQueue();

                // Emit the `StrategyRemoved` event
                assembly {
                    log2(0x00, 0x00, _STRATEGY_REMOVED_EVENT_SIGNATURE, strategy)
                }
                return;
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Revoke a Strategy, setting its debt limit to 0 and preventing any future deposits
    /// @dev This function should only be used in the scenario where the Strategy is being retired but no migration
    /// of the positions is possible, or in the extreme scenario that the Strategy needs to be put into "Emergency Exit"
    /// mode in order for it to exit as quickly as possible. The latter scenario could be for any reason that is
    /// considered
    /// "critical" that the Strategy exits its position as fast as possible, such as a sudden change in market
    /// conditions leading to losses, or an imminent failure in an external dependency.
    /// @param strategy The strategy to revoke
    function revokeStrategy(address strategy) external checkRoles(ADMIN_ROLE) {
        uint256 cachedStrategyDebtRatio = strategies[strategy].strategyDebtRatio; // Saves an SLOAD if strategy is !=
            // addr(0)
        assembly ("memory-safe") {
            // if (strategies[strategy].strategyActivation == 0)
            if iszero(cachedStrategyDebtRatio) {
                // throw `StrategyDebtRatioAlreadyZero()` error
                mstore(0x00, 0xe3a1d5ed)
                revert(0x1c, 0x04)
            }
        }
        // Remove `STRATEGY_ROLE` from strategy
        _removeRoles(strategy, STRATEGY_ROLE);

        // Revoke the strategy
        _revokeStrategy(strategy, cachedStrategyDebtRatio);
    }

    /// @notice Fully exit a strategy
    /// @dev This is the most aggressive strategy exit plan, it liquidates all the positions
    /// from the strategy, revoke the strategy role, and remove it from the withdrawal queue
    /// as well
    /// @param strategy The strategy to revoke
    function exitStrategy(address strategy) external checkRoles(ADMIN_ROLE) {
        // Liquidate the strategy fully
        IStrategy _strategy = IStrategy(strategy);
        uint256 _maxWithdraw = _strategy.maxLiquidate();
        uint256 loss = _strategy.liquidate(_maxWithdraw);
        uint256 withdrawn = _sub0(_maxWithdraw, loss);
        uint256 strategyTotalDebt = strategies[strategy].strategyTotalDebt;
        uint256 strategyDebtRatio = strategies[strategy].strategyDebtRatio;
        totalIdle += withdrawn;
        // Cannot underflow
        unchecked {
            totalDebt -= strategyTotalDebt;
            debtRatio -= strategyDebtRatio;
        }
        // Clear debt of strategy
        strategies[strategy].autoPilot = false;
        strategies[strategy].strategyActivation = 0;
        strategies[strategy].strategyTotalDebt = 0;
        strategies[strategy].strategyDebtRatio = 0;

        // Remove the strategy from the queue
        address[MAXIMUM_STRATEGIES] memory cachedWithdrawalQueue = withdrawalQueue;
        for (uint256 i; i < MAXIMUM_STRATEGIES;) {
            if (cachedWithdrawalQueue[i] == strategy) {
                // The strategy was found and can be removed
                withdrawalQueue[i] = address(0);

                // Remove `STRATEGY_ROLE` from strategy
                _removeRoles(strategy, STRATEGY_ROLE);

                // Update withdrawal queue
                _organizeWithdrawalQueue();

                assembly {
                    // Emit the `StrategyRemoved` event
                    log2(0x00, 0x00, _STRATEGY_REMOVED_EVENT_SIGNATURE, strategy)

                    // Emit the `StrategyExited` event
                    mstore(0x00, withdrawn)
                    log2(0x00, 0x20, _STRATEGY_EXITED_EVENT_SIGNATURE, strategy)
                }

                return;
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Updates a given strategy configured data
    /// @param strategy The strategy to change the data to
    /// @param newDebtRatio The new percentage of the total assets in the vault that `strategy` has access to
    /// @param newMaxDebtPerHarvest New lower limit on the increase of debt since last harvest
    /// @param newMinDebtPerHarvest New upper limit on the increase of debt since last harvest
    /// @param newPerformanceFee New fee the strategist will receive based on this Vault's performance
    function updateStrategyData(
        address strategy,
        uint256 newDebtRatio,
        uint256 newMaxDebtPerHarvest,
        uint256 newMinDebtPerHarvest,
        uint256 newPerformanceFee
    )
        external
        checkRoles(ADMIN_ROLE)
    {
        uint256 slot; // Slot where strategies[strategy] slot will be stored
        uint256 slotContent; // Used to store strategies[strategy] slot content

        assembly ("memory-safe") {
            // Compute strategies[newStrategy] slot
            mstore(0x00, strategy)
            mstore(0x20, strategies.slot)
            slot := keccak256(0x00, 0x40)

            // Load strategies[newStrategy] data into `slotContent`
            slotContent := sload(slot)
            // if (strategyData.strategyActivation == 0)
            if iszero(shr(208, shl(176, slotContent))) {
                // throw `StrategyNotActive()` error
                mstore(0x00, 0xdc974a98)
                revert(0x1c, 0x04)
            }
        }
        if (IStrategy(strategy).emergencyExit() == 2) {
            assembly ("memory-safe") {
                // throw `StrategyInEmergencyExitMode()` error
                mstore(0x00, 0x57c7c24f)
                revert(0x1c, 0x04)
            }
        }
        assembly ("memory-safe") {
            // if (newMinDebtPerHarvest > newMaxDebtPerHarvest)
            if gt(newMinDebtPerHarvest, newMaxDebtPerHarvest) {
                // throw the `InvalidMinDebtPerHarvest` error
                mstore(0x00, 0x5f3bd953)
                revert(0x1c, 0x04)
            }

            // if (strategyPerformanceFee > 5000)
            if gt(newPerformanceFee, 5000) {
                // throw the `InvalidPerformanceFee` error
                mstore(0x00, 0xf14508d0)
                revert(0x1c, 0x04)
            }
        }

        uint256 strategyDebtRatio_;
        assembly {
            // Compute strategies[newStrategy].strategyDebtRatio
            strategyDebtRatio_ := shr(240, shl(240, slotContent))
        }

        uint256 debtRatio_;
        unchecked {
            // Update `debtRatio` storage as well as cache `debtRatio` final value result in `debtRatio_`
            // Underflowing will make maxbps check fail later
            debtRatio_ = debtRatio -= strategyDebtRatio_;
        }

        assembly ("memory-safe") {
            let sum := add(debtRatio_, newDebtRatio)
            if lt(sum, debtRatio_) {
                // throw the `Overflow` error
                revert(0, 0)
            }
            // if (debtRatio_ + newDebtRatio > MAX_BPS)
            if gt(sum, MAX_BPS) {
                // throw the `InvalidDebtRatio` error
                mstore(0x00, 0x79facb0d)
                revert(0x1c, 0x04)
            }
        }

        unchecked {
            // Add new debt ratio to current `debtRatio`
            debtRatio = debtRatio_ + newDebtRatio;
        }

        assembly ("memory-safe") {
            // Update strategies[strategy] with new updated data: debtRatio, maxDebtPerHarvest, minDebtPerHarvest,
            // performanceFee
            // Slot 0 and slot 1 will be updated with the new values. Slot 2 is not updated since it stores
            // `strategyTotalDebt`
            // and `strategyTotalLoss`, which are not updated in `updateStrategyData()`.

            // Store data for slot 0 in strategies[strategy]
            sstore(
                slot,
                or(
                    // Obtain old values in slot
                    and(shl(32, 0xffffffffffffffffffffffff), slotContent), // Extract previously stored
                        // `strategyActivation` and `strategyLastReport`
                    // Build new values to store
                    or(
                        shl(128, newMaxDebtPerHarvest),
                        or(shl(16, and(0xffff, newPerformanceFee)), and(0xffff, newDebtRatio))
                    )
                )
            )
            // Store data for slot 1 in strategies[strategy]
            sstore(
                add(slot, 1),
                or(
                    // Obtain old values in slot
                    shl(128, shr(128, sload(add(slot, 1)))), // Extract previously stored `strategyTotalUnrealizedGain`
                    // Build new values to store
                    shr(128, shl(128, newMinDebtPerHarvest))
                )
            )

            // Emit the `StrategyUpdated` event
            mstore(0x00, newDebtRatio)
            mstore(0x20, newMaxDebtPerHarvest)
            mstore(0x40, newMinDebtPerHarvest)
            mstore(0x60, newPerformanceFee)
            log2(0x00, 0x80, _STRATEGY_UPDATED_EVENT_SIGNATURE, strategy)
        }
    }

    ////////////////////////////////////////////////////////////////
    ///                   VAULT CONFIGURATION                    ///
    ////////////////////////////////////////////////////////////////

    /// @notice Updates the withdrawalQueue to match the addresses and order specified by `queue`
    /// @dev There can be fewer strategies than the maximum, as well as fewer than the total number
    /// of strategies active in the vault.
    /// Note This is order sensitive, specify the addresses in the order in which funds should be
    /// withdrawn (so `queue`[0] is the first Strategy withdrawn from, `queue`[1] is the second, etc.),
    /// and add address(0) only when strategies to be added have occupied first queue positions.
    /// This means that the least impactful Strategy (the Strategy that will have its core positions
    /// impacted the least by having funds removed) should be at `queue`[0], then the next least
    /// impactful at `queue`[1], and so on.
    /// @param queue The array of addresses to use as the new withdrawal queue. **This is order sensitive**.
    function setWithdrawalQueue(address[MAXIMUM_STRATEGIES] calldata queue) external checkRoles(ADMIN_ROLE) {
        address prevStrategy;
        // Check queue order is correct
        for (uint256 i; i < MAXIMUM_STRATEGIES;) {
            assembly ("memory-safe") {
                let strategy := calldataload(add(4, mul(i, 0x20)))
                // if (prevStrategy == address(0) && queue[i] != address(0) && i != 0)
                if and(gt(strategy, 0), and(iszero(prevStrategy), gt(i, 0))) {
                    // throw the `InvalidQueueOrder` error
                    mstore(0x00, 0xefb91db4)
                    revert(0x1c, 0x04)
                }

                // Store data necessary to compute strategies[newStrategy] slot
                mstore(0x00, strategy)
                mstore(0x20, strategies.slot)

                // if (strategy != address(0) && strategies[strategy].strategyActivation == 0)
                if and(iszero(shr(208, shl(176, sload(keccak256(0x00, 0x40))))), gt(strategy, 0)) {
                    // throw the `StrategyNotActive` error
                    mstore(0x00, 0xdc974a98)
                    revert(0x1c, 0x04)
                }
                prevStrategy := strategy
            }

            unchecked {
                ++i;
            }
        }
        withdrawalQueue = queue;
        emit WithdrawalQueueUpdated(queue);
    }

    /// @notice Used to change the value of `performanceFee`
    /// @dev Should set this value below the maximum strategist performance fee
    /// @param _performanceFee The new performance fee to use
    function setPerformanceFee(uint256 _performanceFee) external checkRoles(ADMIN_ROLE) {
        assembly ("memory-safe") {
            // if (strategyPerformanceFee > 5000)
            if gt(_performanceFee, 5000) {
                // throw the `InvalidPerformanceFee` error
                mstore(0x00, 0xf14508d0)
                revert(0x1c, 0x04)
            }
        }
        performanceFee = _performanceFee;
        assembly ("memory-safe") {
            // Emit the `PerformanceFeeUpdated` event
            mstore(0x00, _performanceFee)
            log1(0x00, 0x20, _PERFORMANCE_FEE_UPDATED_EVENT_SIGNATURE)
        }
    }

    /// @notice Used to change the value of `managementFee`
    /// @param _managementFee The new performance fee to use
    function setManagementFee(uint256 _managementFee) external checkRoles(ADMIN_ROLE) {
        assembly ("memory-safe") {
            // if (_managementFee > MAX_BPS)
            if gt(_managementFee, MAX_BPS) {
                // throw the `InvalidManagementFee` error
                mstore(0x00, 0x8e9b51ff)
                revert(0x1c, 0x04)
            }
        }
        managementFee = _managementFee;
        assembly {
            // Emit the `ManagementFeeUpdated` event
            mstore(0x00, _managementFee)
            log1(0x00, 0x20, _MANAGEMENT_FEE_UPDATED_EVENT_SIGNATURE)
        }
    }

    /// @notice Changes the maximum amount of tokens that can be deposited in this Vault
    /// @dev This is not how much may be deposited by a single depositor,
    /// but the maximum amount that may be deposited across all depositors
    /// @param _depositLimit The new deposit limit to use
    function setDepositLimit(uint256 _depositLimit) external checkRoles(ADMIN_ROLE) {
        depositLimit = _depositLimit;
        assembly ("memory-safe") {
            // Emit the `DepositLimitUpdated` event
            mstore(0x00, _depositLimit)
            log1(0x00, 0x20, _DEPOSIT_LIMIT_UPDATED_EVENT_SIGNATURE)
        }
    }

    /// @notice Activates or deactivates Vault mode where all Strategies go into full withdrawal.
    /// During Emergency Shutdown:
    /// 1. No users may deposit into the Vault (but may withdraw as usual)
    /// 2. No new Strategies may be added
    /// 3. Each Strategy must pay back their debt as quickly as reasonable to minimally affect their position
    /// @param _emergencyShutdown If true, the Vault goes into Emergency Shutdown. If false, the Vault goes back into
    /// normal operation
    function setEmergencyShutdown(bool _emergencyShutdown) external checkRoles(EMERGENCY_ADMIN_ROLE) {
        emergencyShutdown = _emergencyShutdown;
        assembly ("memory-safe") {
            // Emit the `EmergencyShutdownUpdated` event
            mstore(0x00, _emergencyShutdown)
            log1(0x00, 0x20, _EMERGENCY_SHUTDOWN_UPDATED_EVENT_SIGNATURE)
        }
    }

    /// @notice Updates the treasury address
    /// @param _treasury The new treasury address
    function setTreasury(address _treasury) external checkRoles(ADMIN_ROLE) {
        treasury = _treasury;
        assembly ("memory-safe") {
            // Emit the `TreasuryUpdated` event
            mstore(0x00, _treasury)
            log1(0x00, 0x20, _TREASURY_UPDATED_EVENT_SIGNATURE)
        }
    }

    /// @notice Enables or disables the autopilot mode, that allows for automated harvesting
    /// of strategies from the vault
    /// If autopilot is enabled:
    /// 1. Strategies can switch to autopilot mode
    /// 2. Every week ,when one user deposits the vault with force the harvest of one strategy every time
    /// 3. The depositing user that calls harvest will get extra shares as a reward for paying for the harvest gas
    /// @param _autoPilotEnabled  If true, it is  activated, if false it is disabled
    function setAutopilotEnabled(bool _autoPilotEnabled) external checkRoles(ADMIN_ROLE) {
        autoPilotEnabled = _autoPilotEnabled;
        assembly ("memory-safe") {
            // Emit the `AutoPilotEnabled` event
            mstore(0x00, _autoPilotEnabled)
            log1(0x00, 0x20, _AUTOPILOT_ENABLED_EVENT_SIGNATURE)
        }
    }

    /// @notice Switches the autopilot mode of a strategy
    /// @param _autoPilot If true, set the strategy in autiopilot mode
    function setAutoPilot(bool _autoPilot) external checkRoles(STRATEGY_ROLE) {
        strategies[msg.sender].autoPilot = _autoPilot;
    }

    ////////////////////////////////////////////////////////////////
    ///                    VIEW FUNCTIONS                        ///
    ////////////////////////////////////////////////////////////////

    /// @notice Amount of tokens in Vault a Strategy has access to as a credit line.
    /// This will check the Strategy's debt limit, as well as the tokens available in the
    /// Vault, and determine the maximum amount of tokens (if any) the Strategy may draw on
    /// @param strategy The strategy to check
    /// @return The quantity of tokens available for the Strategy to draw on
    function creditAvailable(address strategy) external view returns (uint256) {
        return _creditAvailable(strategy);
    }

    /// @notice Determines if `strategy` is past its debt limit and if any tokens should be withdrawn to the Vault
    /// @param strategy The Strategy to check
    /// @return The quantity of tokens to withdraw
    function debtOutstanding(address strategy) external view returns (uint256) {
        return _debtOutstanding(strategy);
    }

    /// @notice returns stratetegyTotalDebt, saves gas, no need to return the whole struct
    /// @param strategy The Strategy to check
    /// @return strategyTotalDebt The strategy's total debt
    function getStrategyTotalDebt(address strategy) external view returns (uint256 strategyTotalDebt) {
        assembly ("memory-safe") {
            // Store data necessary to compute strategies[newStrategy] slot
            mstore(0x00, strategy)
            mstore(0x20, strategies.slot)

            // Obtain strategies[strategy].strategyTotalDebt, stored in struct's slot 2
            strategyTotalDebt := shr(128, shl(128, sload(add(keccak256(0x00, 0x40), 2))))
        }
    }
}
