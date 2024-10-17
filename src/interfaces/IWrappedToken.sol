// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

interface IWrappedToken {
    function approve(address, uint256) external;

    function deposit() external payable;

    function transfer(address to, uint256 value) external returns (bool);

    function withdraw(uint256) external;
}
