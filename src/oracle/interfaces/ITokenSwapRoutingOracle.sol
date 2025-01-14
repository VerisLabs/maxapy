// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

////////////////////////////////////////////////////////////////
///                       STRUCTS                            ///
////////////////////////////////////////////////////////////////

/// @notice Struct to represent a swap route with information about the tokens and the source.
struct SwapRoute {
    address from; // Address of the token being swapped from.
    address to; // Address of the token being swapped to.
    bytes32 source; // Identifier for the swap source (e.g., exchange or liquidity pool).
    uint16 proportionBps; // The proportion in basis points (100 bps = 1%).
}

/// @notice Struct to store token pairs.
struct TokenPair {
    address fromToken; // Address of the token being swapped from.
    address toToken; // Address of the token being swapped to.
}

interface ITokenSwapRoutingOracle {
    ////////////////////////////////////////////////////////////////
    ///                       EVENTS                             ///
    ////////////////////////////////////////////////////////////////

    /// @notice Event emitted when the swap routes for a given path are updated.
    /// @param key The key representing the token pair (fromToken, toToken).
    event RoutesUpdated(bytes32 key);

    ////////////////////////////////////////////////////////////////
    ///                       FUNCTIONS                          ///
    ////////////////////////////////////////////////////////////////

    /**
     * @notice Updates the swap routes for a given token pair (fromToken to toToken).
     * @dev This will overwrite any existing routes for that pair.
     * @param fromToken The address of the token being swapped from.
     * @param toToken The address of the token being swapped to.
     * @param _routes An array of SwapRoute structs representing the new set of swap routes.
     */
    function updateRoutes(
        address fromToken,
        address toToken,
        SwapRoute[] calldata _routes
    ) external;

    /**
     * @notice Updates multiple swap routes for multiple token pairs.
     * @param fromTokens An array of token addresses being swapped from.
     * @param toTokens An array of token addresses being swapped to.
     * @param routes A 2D array of SwapRoute structs representing the new set of swap routes for each pair.
     */
    function updateMultipleRoutes(
        address[] calldata fromTokens,
        address[] calldata toTokens,
        SwapRoute[][] calldata routes
    ) external;

    /**
     * @notice Registers a token pair if it doesn't already exist.
     * @param from The address of the token being swapped from.
     * @param to The address of the token being swapped to.
     */
    function addTokenPair(address from, address to) external;

    /**
     * @notice Generates a unique key for a token pair using keccak256 hashing of the token addresses.
     * @param _from The address of the token being swapped from.
     * @param _to The address of the token being swapped to.
     * @return A unique bytes32 key representing the token pair.
     */
    function getPathKey(
        address _from,
        address _to
    ) external pure returns (bytes32);

    /**
     * @notice Returns all registered token pairs as an array of structs.
     * @return An array of TokenPair structs.
     */
    function getAllRegisteredPairs() external view returns (TokenPair[] memory);

    /**
     * @notice Checks if a token pair is registered.
     * @param key The bytes32 key representing the token pair (fromToken, toToken).
     * @return A boolean indicating whether the pair exists.
     */
    function pairExists(bytes32 key) external view returns (bool);

    /**
     * @dev Returns the swap route array associated with a specific path key.
     * @param key The bytes32 key generated from a token pair.
     * @return _routes An array of SwapRoute structs containing the routing information.
     */
    function getPath(
        bytes32 key
    ) external view returns (SwapRoute[] memory _routes);
}
