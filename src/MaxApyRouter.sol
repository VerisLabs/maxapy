// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { IWrappedToken } from "src/interfaces/IWrappedToken.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IERC20Permit } from "openzeppelin/token/ERC20/extensions/IERC20Permit.sol";

/// @title MaxApy Vault Universal Router
/// @notice A helper contract to safely and easily interact with MaxApy universal vaults
/// @author Adapted from: https://github.com/ERC4626-Alliance/ERC4626-Contracts/blob/main/src/ERC4626Router.sol
contract MaxApyRouter {
    using SafeTransferLib for address;

    ////////////////////////////////////////////////////////////////
    ///                       CONSTANTS                          ///
    ////////////////////////////////////////////////////////////////
    /// @notice The chain's wrapped native token
    IWrappedToken public immutable wrappedToken;

    ////////////////////////////////////////////////////////////////
    ///                        ERRORS                            ///
    ////////////////////////////////////////////////////////////////
    error FailedNativeTransfer();
    error InsufficientShares();
    error InsufficientAssets();
    error ReceiveNotAllowed();
    error InvalidRecipient();

    /// @notice Create the WrappedToken Gateway
    /// @param _wrappedToken The wrapped token of the chain the contract will be deployed to
    constructor(IWrappedToken _wrappedToken) {
        wrappedToken = _wrappedToken;
    }

    /// @notice Deposits `amount` tokens in the vault, issuing shares to `recipient`
    /// @param vault The MaxApy vault to interact with
    /// @param amount The amount of underlying assets to deposit
    /// @param recipient The address to issue the shares from MaxApy's Vault to
    /// @param minSharesOut The minimum acceptable amount of vault shares to get after the deposit
    /// @return sharesOut The actual amount of minted shares
    function deposit(
        IMaxApyVault vault,
        uint256 amount,
        address recipient,
        uint256 minSharesOut
    )
        external
        returns (uint256 sharesOut)
    {
        if (recipient == address(0)) revert InvalidRecipient();
        address asset = vault.asset();
        address cachedVault = address(vault);
        asset.safeTransferFrom(msg.sender, address(this), amount);
        _approveMax(cachedVault, asset);
        assembly ("memory-safe") {
            // Cache the free memory pointer
            let m := mload(0x40)
            // Store MaxApy vault's `deposit()` function selector:
            // `bytes4(keccak256("deposit(uint256,address)"))`
            mstore(0x00, 0x6e553f65)
            mstore(0x20, amount) // Append the `amount` argument
            mstore(0x40, recipient) // Append the `recipient` argument

            // Deposit into MaxApy vault
            if iszero(
                call(
                    gas(), // Remaining amount of gas
                    cachedVault, // Address of `vault`
                    0, // `msg.value`
                    0x1c, // byte offset in memory where calldata starts
                    0x44, // size of the calldata to copy
                    0x00, // byte offset in memory to store the return data
                    0x20 // size of the return data
                )
            ) {
                // If call failed, throw the error thrown in the previous `call`
                revert(0x00, 0x04)
            }

            // cache shares
            sharesOut := mload(0x00)

            // check that shares aren't fewer than requested
            if lt(sharesOut, minSharesOut) {
                // throw the `InsufficientShares` error
                mstore(0x00, 0x39996567)
                revert(0x1c, 0x04)
            }

            mstore(0x40, m) // Restore the free memory pointer
        }
    }

    /// @notice Deposits `amount` tokens in the vault, issuing shares to `recipient`
    /// @param vault The MaxApy vault to interact with
    /// @param amount The amount of underlying assets to deposit
    /// @param recipient The address to issue the shares from MaxApy's Vault to
    /// @param deadline Deadline for the EIP712-Permit signature
    /// @param v `v` component of the digital signature
    /// @param r `r` component of the digital signature
    /// @param s `s` component of the digital signature
    /// @param minSharesOut The minimum acceptable amount of vault shares to get after the deposit
    /// @return sharesOut The actual amount of minted shares
    function depositWithPermit(
        IMaxApyVault vault,
        uint256 amount,
        address recipient,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint256 minSharesOut
    )
        external
        returns (uint256 sharesOut)
    {
        if (recipient == address(0)) revert InvalidRecipient();
        address asset = vault.asset();
        address cachedVault = address(vault);
        IERC20Permit(asset).permit(msg.sender, address(this), amount, deadline, v, r, s);
        asset.safeTransferFrom(msg.sender, address(this), amount);
        _approveMax(cachedVault, asset);
        assembly ("memory-safe") {
            // Cache the free memory pointer
            let m := mload(0x40)
            // Store MaxApy vault's `deposit()` function selector:
            // `bytes4(keccak256("deposit(uint256,address)"))`
            mstore(0x00, 0x6e553f65)
            mstore(0x20, amount) // Append the `amount` argument
            mstore(0x40, recipient) // Append the `recipient` argument

            // Deposit into MaxApy vault
            if iszero(
                call(
                    gas(), // Remaining amount of gas
                    cachedVault, // Address of `vault`
                    0, // `msg.value`
                    0x1c, // byte offset in memory where calldata starts
                    0x44, // size of the calldata to copy
                    0x00, // byte offset in memory to store the return data
                    0x20 // size of the return data
                )
            ) {
                // If call failed, throw the error thrown in the previous `call`
                revert(0x00, 0x04)
            }

            // cache shares
            sharesOut := mload(0x00)

            // check that shares aren't fewer than requested
            if lt(sharesOut, minSharesOut) {
                // throw the `InsufficientShares` error
                mstore(0x00, 0x39996567)
                revert(0x1c, 0x04)
            }

            mstore(0x40, m) // Restore the free memory pointer
        }
    }

    /// @notice  Deposits `msg.value` of `_wrappedToken`, issuing shares to `recipient`
    /// @param vault The MaxApy vault to interact with
    /// @param recipient The address to issue the shares from MaxApy's Vault to
    /// @param minSharesOut The minimum acceptable amount of vault shares to get after the deposit
    /// @return sharesOut The actual amount of minted shares
    function depositNative(
        IMaxApyVault vault,
        address recipient,
        uint256 minSharesOut
    )
        external
        payable
        returns (uint256 sharesOut)
    {
        if (recipient == address(0)) revert InvalidRecipient();
        // Cache `wrappedToken` and `vault` due to assembly's immutable access restrictions
        address cachedWrappedToken = address(wrappedToken);
        address cachedVault = address(vault);
        _approveMax(cachedVault, cachedWrappedToken);

        assembly ("memory-safe") {
            // Check if `msg.value` is 0
            if iszero(callvalue()) {
                // Throw the `InvalidZeroValue()` error
                mstore(0x00, 0xef7a63d0)
                revert(0x1c, 0x04)
            }

            // Cache the free memory pointer
            let m := mload(0x40)

            // Store Wrapped Token's `deposit()` function selector:
            // `bytes4(keccak256("deposit()"))`
            mstore(0x00, 0xd0e30db0)

            // Deposit native token in exchange for wrapped native token
            // Note: using some wrapped tokens' fallback function for deposit allows saving the previous
            // selector loading into memory to call wrappedToken's `deposit()`.
            // This is avoided due to some chain's wrapped native versions not allowing such behaviour
            if iszero(
                call(
                    gas(), // Remaining amount of gas
                    cachedWrappedToken, // Address of `wrappedToken`
                    callvalue(), // `msg.value`
                    0x1c, // byte offset in memory where calldata starts
                    0x04, // size of the calldata to copy
                    0x00, // byte offset in memory to store the return data
                    0x00 // size of the return data
                )
            ) {
                // Throw the `WrappedTokenDepositFailed()` error
                mstore(0x00, 0x22cd2378)
                revert(0x1c, 0x04)
            }

            // Store MaxApy vault's `deposit()` function selector:
            // `bytes4(keccak256("deposit(uint256,address)"))`
            mstore(0x00, 0x6e553f65)
            mstore(0x20, callvalue()) // Append the `amount` argument
            mstore(0x40, recipient) // Append the `recipient` argument

            // Deposit into MaxApy vault
            if iszero(
                call(
                    gas(), // Remaining amount of gas
                    cachedVault, // Address of `vault`
                    0, // `msg.value`
                    0x1c, // byte offset in memory where calldata starts
                    0x44, // size of the calldata to copy
                    0x00, // byte offset in memory to store the return data
                    0x20 // size of the return data
                )
            ) {
                // If call failed, throw the error thrown in the previous `call`
                revert(0x00, 0x04)
            }

            // cache shares
            sharesOut := mload(0x00)

            // check that shares aren't fewer than requested
            if lt(sharesOut, minSharesOut) {
                // throw the `InsufficientShares` error
                mstore(0x00, 0x39996567)
                revert(0x1c, 0x04)
            }

            mstore(0x40, m) // Restore the free memory pointer
        }
    }

    /// @notice Withdraws the calling account's tokens from MaxApy's Vault, redeeming
    /// amount `shares` for the corresponding amount of tokens, which will be transferred to
    /// `recipient`
    /// @param vault The MaxApy vault to interact with
    /// @param shares How many shares to try and redeem for tokens
    /// @param recipient The address to issue the shares from MaxApy's Vault to
    /// @param minAmountOut The minimum acceptable amount of assets to get in exchange for the burnt shares
    /// @return amountOut The actual amount of redeemed assets
    function redeem(
        IMaxApyVault vault,
        uint256 shares,
        address recipient,
        uint256 minAmountOut
    )
        external
        returns (uint256 amountOut)
    {
        if (recipient == address(0)) revert InvalidRecipient();
        // Cache `wrappedToken` and `vault` due to assembly's immutable access restrictions
        address cachedVault = address(vault);

        assembly ("memory-safe") {
            // Cache the free memory pointer
            let m := mload(0x40)

            // Store `vault`'s `redeem()` function selector:
            // `bytes4(keccak256("redeem(uint256,address,address)"))`
            mstore(0x00, 0xba087652)
            mstore(0x20, shares) // append the `shares` argument
            mstore(0x40, recipient) // append the `recipient` argument
            mstore(0x60, caller()) // append the `operator` argument

            // Withdraw from MaxApy vault
            if iszero(
                call(
                    gas(), // Remaining amount of gas
                    cachedVault, // Address of `vault`
                    0, // `msg.value`
                    0x1c, // byte offset in memory where calldata starts
                    0x64, // size of the calldata to copy
                    0x00, // byte offset in memory to store the return data
                    0x20 // size of the return data
                )
            ) {
                // If call failed, throw the error thrown in the previous `call`
                revert(0x00, 0x04)
            }

            // Store `amountOut` returned by the previous call to `withdraw()`
            amountOut := mload(0x00)

            if lt(amountOut, minAmountOut) {
                // Throw the `InsufficientAssets` error
                mstore(0x00, 0x96d80433)
                revert(0x1c, 0x04)
            }

            mstore(0x60, 0) // Restore the zero slot
            mstore(0x40, m) // Restore the free memory pointer
        }
    }

    /// @notice Withdraws the calling account's tokens from MaxApy's Vault, redeeming
    /// amount of `shares` for the corresponding amount of tokens, which will be transferred to
    /// `recipient` in the form of the chain's native token
    /// @param vault The MaxApy vault to interact with
    /// @param shares How many shares to try and redeem for tokens
    /// @param recipient The address to issue the shares from MaxApy's Vault to
    /// @param minAmountOut The minimum acceptable amount of assets to get in exchange for the burnt shares
    /// @return amountOut The actual amount of redeemed assets
    function redeemNative(
        IMaxApyVault vault,
        uint256 shares,
        address recipient,
        uint256 minAmountOut
    )
        external
        returns (uint256 amountOut)
    {
        if (recipient == address(0)) revert InvalidRecipient();
        // Cache `wrappedToken` and `vault` due to assembly's immutable access restrictions
        address cachedWrappedToken = address(wrappedToken);
        address cachedVault = address(vault);

        assembly ("memory-safe") {
            // Cache the free memory pointer
            let m := mload(0x40)

            // Store `vault`'s `redeem()` function selector:
            // `bytes4(keccak256("redeem(uint256,address,address)"))`
            mstore(0x00, 0xba087652)
            mstore(0x20, shares) // append the `shares` argument
            mstore(0x40, address()) // append the `recipient` argument
            mstore(0x60, caller()) // append the `operator` argument

            // Withdraw from MaxApy vault
            if iszero(
                call(
                    gas(), // Remaining amount of gas
                    cachedVault, // Address of `vault`
                    0, // `msg.value`
                    0x1c, // byte offset in memory where calldata starts
                    0x64, // size of the calldata to copy
                    0x00, // byte offset in memory to store the return data
                    0x20 // size of the return data
                )
            ) {
                // If call failed, throw the error thrown in the previous `call`
                revert(0x00, 0x04)
            }

            // Store `amountOut` returned by the previous call to `withdraw()`
            amountOut := mload(0x00)

            if lt(amountOut, minAmountOut) {
                // Throw the `InsufficientAssets` error
                mstore(0x00, 0x96d80433)
                revert(0x1c, 0x04)
            }

            // Store `wrappedToken`'s `withdraw()` function selector:
            // `bytes4(keccak256("withdraw(uint256)"))`
            mstore(0x00, 0x2e1a7d4d)
            mstore(0x20, amountOut) // append the `amountOut` argument

            // Withdraw from wrapped token
            if iszero(
                call(
                    gas(), // Remaining amount of gas
                    cachedWrappedToken, // Address of `vault`
                    0, // `msg.value`
                    0x1c, // byte offset in memory where calldata starts
                    0x24, // size of the calldata to copy
                    0x00, // byte offset in memory to store the return data
                    0x20 // size of the return data
                )
            ) {
                // If call failed, throw the error thrown in the previous `call`
                revert(0x00, 0x04)
            }

            // Transfer native token back to user
            if iszero(call(gas(), recipient, amountOut, 0x00, 0x00, 0x00, 0x00)) {
                // If call failed, throw the `FailedNativeTransfer()` error
                mstore(0x00, 0x3c3f4130)
                revert(0x1c, 0x04)
            }

            mstore(0x60, 0) // Restore the zero slot
            mstore(0x40, m) // Restore the free memory pointer
        }
    }

    ////////////////////////////////////////////////////////////////
    ///                 Helper  functions                        ///
    ////////////////////////////////////////////////////////////////
    /// @dev helper function to perform ERC20 mas approvals to vaults
    function _approveMax(address _vault, address _token) internal {
        (bool s, bytes memory data) =
            _token.staticcall(abi.encodeWithSignature("allowance(address,address)", address(this), _vault));
        if (!s) revert();
        uint256 _allowance = abi.decode(data, (uint256));
        if (_allowance == 0) {
            _token.safeApprove(_vault, type(uint256).max);
        }
    }

    ////////////////////////////////////////////////////////////////
    ///                 RECEIVE()  function                      ///
    ////////////////////////////////////////////////////////////////

    /// @notice Receive function to accept native transfers
    /// @dev Note only the chain's wrapped token will be able to perform native token transfers
    /// to this contract
    receive() external payable {
        // Cache `wrappedToken` due to assembly immutable access restrictions
        address cachedWrappedToken = address(wrappedToken);

        assembly {
            // Check if caller is not the `wrappedToken`
            if iszero(eq(caller(), cachedWrappedToken)) {
                // Throw the `ReceiveNotAllowed()` error
                mstore(0x00, 0xcb263c3f)
                revert(0x1c, 0x04)
            }
        }
    }
}
