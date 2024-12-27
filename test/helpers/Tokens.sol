// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {
    DAI_MAINNET,
    DAI_POLYGON,
    LUSD_MAINNET,
    USDCE_POLYGON,
    USDC_MAINNET,
    USDC_POLYGON,
    USDT_MAINNET,
    USDT_POLYGON,
    WETH_MAINNET,
    WETH_POLYGON
} from "src/helpers/AddressBook.sol";

uint256 constant _1_USDC = 1e6;
uint256 constant _1_USDCE = 1e6;
uint256 constant _1_USDT = 1e6;
uint256 constant _1_DAI = 1 ether;

function getTokensList(string memory chain) pure returns (address[] memory) {
    if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("MAINNET"))) {
        address[] memory tokens = new address[](5);
        tokens[0] = WETH_MAINNET;
        tokens[1] = USDC_MAINNET;
        tokens[2] = DAI_MAINNET;
        tokens[3] = LUSD_MAINNET;
        tokens[4] = USDT_MAINNET;
        return tokens;
    } else if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("POLYGON"))) {
        address[] memory tokens = new address[](4);
        tokens[0] = USDT_POLYGON;
        tokens[1] = DAI_POLYGON;
        tokens[2] = USDCE_POLYGON;
        tokens[3] = WETH_POLYGON;
        return tokens;
    } else {
        revert("InvalidChain");
    }
}
