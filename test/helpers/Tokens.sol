// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {
    WETH_MAINNET,
    USDC_MAINNET,
    DAI_MAINNET,
    LUSD_MAINNET,
    USDT_MAINNET,
    USDT_POLYGON,
    DAI_POLYGON,
    USDCE_POLYGON,
    USDC_POLYGON
} from "src/helpers/AddressBook.sol";

uint256 constant _1_USDC = 1e6;
uint256 constant _1_USDT = _1_USDC;
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
        address[] memory tokens = new address[](3);
        tokens[0] = USDT_POLYGON;
        tokens[1] = DAI_POLYGON;
        tokens[2] = USDCE_POLYGON;
        return tokens;
    } else {
        revert("InvalidChain");
    }
}
