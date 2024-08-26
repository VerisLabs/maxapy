// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { OwnableRoles } from "solady/auth/OwnableRoles.sol";
import { IStrategy } from "src/interfaces/IStrategy.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";

/// @title MaxApyHarvester
/// @dev This is an internal contract to call harvest in an atomic way.
contract MaxApyHarvester is OwnableRoles {
    ////////////////////////////////////////////////////////////////
    ///                        ERRORS                            ///
    ////////////////////////////////////////////////////////////////
    error HarvestFailed();
    error NotOwner();
    error CantReceiveETH();
    error Fallback();

    ////////////////////////////////////////////////////////////////
    ///                        STRUCTS                           ///
    ////////////////////////////////////////////////////////////////
    /// @dev Params for harvesting
    struct HarvestData {
        address strategyAddress;
        uint256 minExpectedBalance;
        uint256 minOutputAfterInvestment;
        uint256 deadline;
    }

    /// @dev Params for allocation
    struct AllocationData {
        address strategyAddress;
        uint256 debtRatio;
        uint256 maxDebtPerHarvest;
        uint256 minDebtPerHarvest;
        uint256 performanceFee;
    }

    ////////////////////////////////////////////////////////////////
    ///                        CONSTANTS                         ///
    ////////////////////////////////////////////////////////////////
    uint256 public constant ADMIN_ROLE = _ROLE_0;
    uint256 public constant KEEPER_ROLE = _ROLE_1;
    uint256 public constant ALLOCATOR_ROLE = _ROLE_2;
    address public constant DEFAULT_HARVESTER = address(0);

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

    /// @dev Constructor to set the initial state of the contract.
    /// @param admin Contract admin
    /// @param keepers The addresses that will be added to a keeper role
    constructor(address admin, address[] memory keepers, address[] memory allocators) {
        // loop to add the keepers to a mapping
        _initializeOwner(admin);
        _grantRoles(admin, ADMIN_ROLE);

        uint256 length = keepers.length;

        // Iterate through each keeper in the array in order to grant roles.
        for (uint256 i = 0; i < length;) {
            _grantRoles(keepers[i], KEEPER_ROLE);

            unchecked {
                ++i;
            }
        }

        length = allocators.length;

        // Iterate through each allocator in the array in order to grant roles.
        for (uint256 i = 0; i < length;) {
            _grantRoles(allocators[i], ALLOCATOR_ROLE);

            unchecked {
                ++i;
            }
        }
    }

    ////////////////////////////////////////////////////////////////
    ///                     FALLBACK & RECEIVE                   ///
    ////////////////////////////////////////////////////////////////
    /// @dev Explicitly reject any raw call
    fallback() external payable {
        revert Fallback();
    }

    /// @dev Explicitly reject any Ether transfered to the contract
    receive() external payable {
        revert CantReceiveETH();
    }

    ////////////////////////////////////////////////////////////////
    ///                     LOGIC                                ///
    ////////////////////////////////////////////////////////////////
    /// @notice Orchestrates a batch harvest for the MaxApy protocol.
    /// @param harvests An array of strategy harvests
    function batchHarvests(HarvestData[] calldata harvests) public checkRoles(KEEPER_ROLE) {
        uint256 length = harvests.length;

        // Iterate through each strategy in the array in order to call the harvest.
        for (uint256 i = 0; i < length;) {
            address strategyAddress = harvests[i].strategyAddress;
            uint256 minExpectedBalance = harvests[i].minExpectedBalance;
            uint256 minOutputAfterInvestment = harvests[i].minOutputAfterInvestment;
            uint256 deadline = harvests[i].deadline;

            IStrategy(strategyAddress).harvest(
                minExpectedBalance, minOutputAfterInvestment, DEFAULT_HARVESTER, deadline
            );

            // Use unchecked block to bypass overflow checks for efficiency.
            unchecked {
                i++;
            }
        }
    }

    /// @notice Orchestrates a batch allocation for the MaxApy protocol.
    /// @param allocations An array of strategy allocations
    function batchAllocate(
        IMaxApyVault vault,
        AllocationData[] calldata allocations
    )
        public
        checkRoles(ALLOCATOR_ROLE)
    {
        uint256 length = allocations.length;

        // Iterate through each strategy in the array in order to call the allocate.
        for (uint256 i = 0; i < length;) {
            address strategyAddress = allocations[i].strategyAddress;
            uint256 debtRatio = allocations[i].debtRatio;
            uint256 maxDebtPerHarvest = allocations[i].maxDebtPerHarvest;
            uint256 minDebtPerHarvest = allocations[i].minDebtPerHarvest;
            uint256 performanceFee = allocations[i].performanceFee;

            vault.updateStrategyData(strategyAddress, debtRatio, maxDebtPerHarvest, minDebtPerHarvest, performanceFee);

            // Use unchecked block to bypass overflow checks for efficiency.
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
        batchHarvests(harvests);
        return true;
    }
}
