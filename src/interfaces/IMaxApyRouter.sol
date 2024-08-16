// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";

interface IMaxApyRouter {
    function deposit(
        IMaxApyVault vault,
        uint256 amount,
        address recipient,
        uint256 minSharesOut
    )
        external
        payable
        returns (uint256);

    function depositNative(
        IMaxApyVault vault,
        address recipient,
        uint256 minSharesOut
    )
        external
        payable
        returns (uint256);

    function redeem(
        IMaxApyVault vault,
        uint256 shares,
        address recipient,
        uint256 minAmountOut
    )
        external
        returns (uint256);

    function redeemNative(
        IMaxApyVault vault,
        uint256 shares,
        address recipient,
        uint256 minAmountOut
    )
        external
        returns (uint256);

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
        returns (uint256 sharesOut);
}
