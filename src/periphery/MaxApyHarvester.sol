// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { StrategyData } from "../helpers/VaultTypes.sol";
import { OwnableRoles } from "solady/auth/OwnableRoles.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";
import { IStrategy } from "src/interfaces/IStrategy.sol";

/**
 * @title MaxHarvester
 * @dev This is an internal contract to call harvest in an atomic way.
 */
contract MaxApyHarvester is OwnableRoles {
    /*//////////////////////////////////////////////////////////////
                             ERRORS
    //////////////////////////////////////////////////////////////*/

    error AddStrategyFailed();
    error CantReceiveETH();
    error Fallback();
    error HarvestFailed();
    error NotOwner();
    error MaximumStrategiesReached();

    IStrategy strategy;

    /*//////////////////////////////////////////////////////////////
                              STRUCTS
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev Struct to encapsulate information about the strategy to add.
     * @param strategyAddress The address of the strategy.
     * @param strategyDebtRatio The debt ratio for the strategy.
     * @param strategyMaxDebtPerHarvest The maximum debt per harvest for the strategy.
     * @param strategyMinDebtPerHarvest The minimum debt per harvest for the strategy.
     * @param strategyPerformanceFee The performance fee for the strategy.
     */
    struct AllocationData {
        address strategyAddress;
        uint256 debtRatio;
        uint256 maxDebtPerHarvest;
        uint256 minDebtPerHarvest;
        uint256 performanceFee;
    }

    /**
     * @dev Struct to encapsulate information about an individual harvest.
     * @param strategyAddress The address of the strategy to harvest from.
     * @param minExpectedBalance The minimum expected balance after the harvest.
     * @param minOutputAfterInvestment The minimum output after the investment.
     * @param deadline The deadline for the harvest operation.
     */
    struct HarvestData {
        address strategyAddress;
        uint256 minExpectedBalance;
        uint256 minOutputAfterInvestment;
        uint256 deadline;
    }

    ////////////////////////////////////////////////////////////////
    ///                        CONSTANTS                         ///
    ////////////////////////////////////////////////////////////////
    // ROLES
    uint256 public constant ADMIN_ROLE = _ROLE_0;
    uint256 public constant KEEPER_ROLE = _ROLE_1;
    // ACTORS
    address public constant DEFAULT_HARVESTER = address(0);

    ////////////////////////////////////////////////////////////////
    ///                       MODIFIERS                          ///
    ////////////////////////////////////////////////////////////////
    /**
     * @dev Modifier to check if the caller has the required roles.
     * @param roles The roles to check.
     */
    modifier checkRoles(uint256 roles) {
        _checkRoles(roles);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev Constructor to set the initial state of the contract.
     * @param admin The address of the admin.
     * @param keepers An array of addresses for the keepers that will call the contract functions.
     */
    constructor(address admin, address[] memory keepers) {
        // loop to add the keepers to a mapping
        _initializeOwner(admin);
        _grantRoles(admin, ADMIN_ROLE);

        uint256 length = keepers.length;

        // Iterate through each Keeper in the array in order to grant roles.
        for (uint256 i = 0; i < length;) {
            _grantRoles(keepers[i], KEEPER_ROLE);

            unchecked {
                ++i;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                    Fallback and Receive Functions
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev Fallback function to reject any Ether sent to the contract.
     */
    fallback() external payable {
        revert Fallback();
    }

    /**
     * @dev Receive function to reject any Ether transferred to the contract.
     */
    receive() external payable {
        revert CantReceiveETH();
    }

    /*//////////////////////////////////////////////////////////////
                          LOGIC
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev Orchestrates a batch add strategy for the maxapy protocol.
     * @param vault The MaxApyVault contract instance.
     * @param strategies An array of strategy values to add to the vault.
     */
    function batchAllocate(IMaxApyVault vault, AllocationData[] calldata strategies) public checkRoles(KEEPER_ROLE) {
        uint256 length = strategies.length;

        AllocationData calldata stratData;
        StrategyData memory isStratActive;

        // Iterate through each strategy in the array in order to add the strategy .
        for (uint256 i = 0; i < length;) {
            stratData = strategies[i];
            isStratActive = vault.strategies(stratData.strategyAddress);
            if (isStratActive.strategyActivation != 0) {
                vault.updateStrategyData(
                    stratData.strategyAddress,
                    stratData.debtRatio,
                    stratData.maxDebtPerHarvest,
                    stratData.minDebtPerHarvest,
                    stratData.performanceFee
                );
            } else {
                vault.addStrategy(
                    stratData.strategyAddress,
                    stratData.debtRatio,
                    stratData.maxDebtPerHarvest,
                    stratData.minDebtPerHarvest,
                    stratData.performanceFee
                );
            }

            unchecked {
                i++;
            }
        }
    }

    /**
     * @dev Orchestrates a batch remove strategy for the maxapy protocol.
     * @param vault The MaxApyVault contract instance.
     * @param harvests An array of harvest data for strategies to remove from the vault.
     */
    function batchHarvest(IMaxApyVault vault, HarvestData[] calldata harvests) public checkRoles(KEEPER_ROLE) {
        uint256 length = harvests.length;

        // Iterate through each strategy in the array in order to call the harvest.
        StrategyData memory strategyData;

        for (uint256 i = 0; i < length;) {
            address strategyAddress = harvests[i].strategyAddress;

            strategyData = vault.strategies(strategyAddress);

            strategy = IStrategy(strategyAddress);
            strategy.harvest(
                harvests[i].minExpectedBalance,
                harvests[i].minOutputAfterInvestment,
                DEFAULT_HARVESTER,
                harvests[i].deadline
            );

            if (strategyData.strategyDebtRatio == 0) {
                vault.exitStrategy(strategyAddress);
            }

            unchecked {
                i++;
            }
        }
    }

    function batchAllocateAndHarvest(
        IMaxApyVault vault,
        AllocationData[] calldata allocations,
        HarvestData[] calldata harvests
    )
        external
        returns (bool)
    {
        batchAllocate(vault, allocations);
        batchHarvest(vault, harvests);
        return true;
    }

    function _simulateBatchAllocateAndHarvest(
        IMaxApyVault vault,
        AllocationData[] calldata allocations,
        HarvestData[] calldata harvests
    )
        public
    {
        // Store totalAssets before allocation and harvest
        uint256 totalAssetsBefore = vault.totalAssets();

        // 1. Simulate allocation
        uint256 length = allocations.length;

        AllocationData calldata stratData;
        StrategyData memory isStratActive;

        // Iterate through each strategy in the array in order to add the strategy .
        for (uint256 i = 0; i < length;) {
            stratData = allocations[i];
            isStratActive = vault.strategies(stratData.strategyAddress);
            if (isStratActive.strategyActivation != 0) {
                vault.updateStrategyData(
                    stratData.strategyAddress,
                    stratData.debtRatio,
                    stratData.maxDebtPerHarvest,
                    stratData.minDebtPerHarvest,
                    stratData.performanceFee
                );
            } else {
                vault.addStrategy(
                    stratData.strategyAddress,
                    stratData.debtRatio,
                    stratData.maxDebtPerHarvest,
                    stratData.minDebtPerHarvest,
                    stratData.performanceFee
                );
            }

            unchecked {
                i++;
            }
        }

        // 2. Simulate harvests
        length = harvests.length;

        // Iterate through each strategy in the array in order to call the harvest.
        StrategyData memory strategyData;
        bytes[] memory simulationResults = new bytes[](length);

        for (uint256 i = 0; i < length;) {
            address strategyAddress = harvests[i].strategyAddress;

            strategyData = vault.strategies(strategyAddress);

            strategy = IStrategy(strategyAddress);
            {
                (
                    uint256 expectedBalance,
                    uint256 outputAfterInvestment,
                    uint256 intendedInvest,
                    uint256 actualInvest,
                    uint256 intendedDivest,
                    uint256 actualDivest
                ) = strategy.simulateHarvest();
                simulationResults[i] = abi.encode(
                    expectedBalance, outputAfterInvestment, intendedInvest, actualInvest, intendedDivest, actualDivest
                );
            }
            strategy.harvest(
                harvests[i].minExpectedBalance,
                harvests[i].minOutputAfterInvestment,
                DEFAULT_HARVESTER,
                harvests[i].deadline
            );

            if (strategyData.strategyDebtRatio == 0) {
                vault.exitStrategy(strategyAddress);
            }

            unchecked {
                i++;
            }
        }

        uint256 totalAssetsAfter = vault.totalAssets();

        bytes memory returnData = abi.encode(totalAssetsBefore, totalAssetsAfter, simulationResults);

        assembly {
            revert(add(returnData, 0x20), mload(returnData))
        }
    }

    function simulateBatchAllocateAndHarvest(
        IMaxApyVault vault,
        AllocationData[] calldata allocations,
        HarvestData[] calldata harvests
    )
        external
        returns (uint256 totalAssetsBefore, uint256 totalAssetsAfter, bytes[] memory simulationResults)
    {
        try this._simulateBatchAllocateAndHarvest(vault, allocations, harvests) { }
        catch (bytes memory e) {
            (totalAssetsBefore, totalAssetsAfter, simulationResults) = abi.decode(e, (uint256, uint256, bytes[]));
        }
    }
}
