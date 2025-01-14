// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {ITokenSwapRoutingOracle, SwapRoute, TokenPair} from "./interfaces/ITokenSwapRoutingOracle.sol";

import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {console2} from "forge-std/console2.sol";

contract TokenSwapRoutingOracle is ITokenSwapRoutingOracle, OwnableRoles {
    /// @notice Role identifier for admin capabilities
    uint256 public constant ADMIN_ROLE = _ROLE_0;

    error InvalidAdminAddress();

    // Mapping of paths (keyed by a hash of fromToken and toToken) to an array of swap routes.
    mapping(bytes32 => SwapRoute[]) public path;

    // Array to store all registered token pairs
    TokenPair[] public registeredPairs;

    mapping(bytes32 => bool) public pairExists;

    ////////////////////////////////////////////////////////////////
    ///                       MODIFIERS                           ///
    ////////////////////////////////////////////////////////////////

    /// @notice Restricts function access to admin role
    modifier onlyAdmin() {
        _checkRoles(ADMIN_ROLE);
        _;
    }

    // Constructor to initialize the contract, setting the contract owner.
    constructor(address _admin) {
        if (_admin == address(0)) revert InvalidAdminAddress();
        _initializeOwner(_admin);
        _grantRoles(_admin, ADMIN_ROLE);
    }

    /**
     * @dev Updates the swap routes for a given token pair (fromToken to toToken).
     * This will overwrite any existing routes for that pair.
     * @param fromToken The address of the token being swapped from.
     * @param toToken The address of the token being swapped to.
     * @param _routes An array of SwapRoute structs representing the new set of swap routes.
     * Only the owner can call this function.
     */
    function updateRoutes(
        address fromToken,
        address toToken,
        SwapRoute[] calldata _routes
    ) external {
        bytes32 key = getPathKey(fromToken, toToken);

        // Clear the current routes for the path before setting new ones.
        delete path[key];

        // Manually copy each route from calldata into storage.
        for (uint256 i = 0; i < _routes.length; i++) {
            path[key].push(_routes[i]);
        }

        emit RoutesUpdated(key); // Emit RoutesUpdated event after the routes are updated.
    }

    function updateMultipleRoutes(
        address[] calldata fromTokens,
        address[] calldata toTokens,
        SwapRoute[][] calldata routes
    ) external {
        require(
            fromTokens.length == toTokens.length,
            "Mismatched array lengths"
        );
        require(fromTokens.length == routes.length, "Mismatched array lengths");

        for (uint256 i = 0; i < fromTokens.length; i++) {
            bytes32 key = getPathKey(fromTokens[i], toTokens[i]);

            // Clear the current routes for the path before setting new ones.
            delete path[key];

            // Manually copy each route from calldata into storage.
            for (uint256 j = 0; j < routes[i].length; j++) {
                path[key].push(routes[i][j]);
            }

            emit RoutesUpdated(key);
        }
    }

    /**
     * @dev Registers a token pair if it doesn't already exist.
     * @param from The address of the token being swapped from.
     * @param to The address of the token being swapped to.
     */
    function addTokenPair(address from, address to) public {
        bytes32 key = getPathKey(from, to);

        // Ensure the pair is not already registered
        if (!pairExists[key]) {
            pairExists[key] = true;

            // Add the pair to the array
            registeredPairs.push(TokenPair({fromToken: from, toToken: to}));
        }
    }

    /**
     * @dev Generates a unique key for a token pair using keccak256 hashing of the token addresses.
     * @param _from The address of the token being swapped from.
     * @param _to The address of the token being swapped to.
     * @return A unique bytes32 key representing the token pair.
     */
    function getPathKey(
        address _from,
        address _to
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_from, _to)); // Return the hash of the concatenated addresses.
    }

    /**
     * @dev Returns all registered token pairs as an array of structs.
     * @return An array of TokenPair structs.
     */
    function getAllRegisteredPairs()
        external
        view
        returns (TokenPair[] memory)
    {
        return registeredPairs;
    }

    /**
     * @dev Returns the swap route array associated with a specific path key.
     * @param key The bytes32 key generated from a token pair.
     * @return _routes An array of SwapRoute structs containing the routing information.
     */
    function getPath(
        bytes32 key
    ) public view returns (SwapRoute[] memory _routes) {
        return path[key];
    }
}
