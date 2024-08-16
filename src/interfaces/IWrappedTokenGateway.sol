// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

interface IWrappedTokenGateway {
    function depositNative(address recipient) external payable returns (uint256);

    function withdrawNative(uint256 shares, address recipient, uint256 maxLoss) external returns (uint256);

    function wrappedToken() external view returns (address);

    function vault() external view returns (address);
}
