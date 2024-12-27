// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { MaxApyVault } from "./MaxApyVault.sol";

import { OwnableRoles } from "solady/auth/OwnableRoles.sol";
import { CREATE3 } from "solady/utils/CREATE3.sol";
import { MetadataReaderLib } from "solady/utils/MetadataReaderLib.sol";

contract MaxApyVaultFactory is OwnableRoles {
    using MetadataReaderLib for address;
    ////////////////////////////////////////////////////////////////
    ///                         EVENTS                           ///
    ////////////////////////////////////////////////////////////////

    event CreateVault(address indexed asset, address vaultAddress);

    uint256 internal constant _CREATE_VAULT_EVENT_SIGNATURE =
        0x61d77434230bc4628b3ed22c0c8e26455cdc6f3cafeb2f032ea3b8e375822ab1;

    ////////////////////////////////////////////////////////////////
    ///                         CONSTANTS                        ///
    ////////////////////////////////////////////////////////////////
    /// Roles
    uint256 public constant ADMIN_ROLE = _ROLE_0;
    uint256 public constant DEPLOYER_ROLE = _ROLE_1;
    /// MaxApy treasury
    address public immutable treasury;

    ////////////////////////////////////////////////////////////////
    ///                         STORAGE                          ///
    ////////////////////////////////////////////////////////////////
    constructor(address _treasury) {
        _initializeOwner(msg.sender);
        _grantRoles(msg.sender, ADMIN_ROLE);
        _grantRoles(msg.sender, DEPLOYER_ROLE);
        treasury = _treasury;
    }

    ////////////////////////////////////////////////////////////////
    ///                         DEPLOYMENT                       ///
    ////////////////////////////////////////////////////////////////
    /// @notice Deploys a vault with a deterministic address
    /// @param underlyingAsset address of the ERC20 deposit token of the vault
    /// @param salt seed hash to compute the new address from
    function deploy(
        address underlyingAsset,
        address vaultAdmin,
        bytes32 salt
    )
        external
        onlyRoles(DEPLOYER_ROLE)
        returns (address deployed)
    {
        // Get asset symbol
        string memory symbol = underlyingAsset.readSymbol();
        // Deploy to deterministic address
        deployed = CREATE3.deploy(
            salt,
            abi.encodePacked(
                type(MaxApyVault).creationCode,
                abi.encode(vaultAdmin, underlyingAsset, parseName(symbol), parseSymbol(symbol), treasury)
            ),
            0
        );

        assembly {
            // Emit `CreateVault` event
            mstore(0x00, deployed)
            log2(0x00, 0x20, _CREATE_VAULT_EVENT_SIGNATURE, underlyingAsset)
        }
    }

    ////////////////////////////////////////////////////////////////
    ///                    INTERNAL VIEW FUNCTIONS               ///
    ////////////////////////////////////////////////////////////////
    /// @dev return the new vault name for a given asset symbol
    /// @param symbol underlying asset symbol
    function parseName(string memory symbol) private pure returns (string memory) {
        return string.concat(string.concat("MaxApy-", symbol), " Vault");
    }

    /// @dev return the new vault symbol for a given asset symbol
    /// @param symbol underlying asset symbol
    function parseSymbol(string memory symbol) private pure returns (string memory) {
        return string.concat("max", symbol);
    }

    ////////////////////////////////////////////////////////////////
    ///                    EXTERNAL VIEW FUNCTIONS               ///
    ////////////////////////////////////////////////////////////////
    /// @notice Computes the deterministic deployment address of a vault given a salt
    /// @param salt the deployment salt
    function computeAddress(bytes32 salt) external view returns (address) {
        return CREATE3.getDeployed(salt);
    }
}
