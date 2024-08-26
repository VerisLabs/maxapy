// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { Vm } from "forge-std/Vm.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { IERC20Metadata } from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

contract Utilities is StdCheats {
    address constant HEVM_ADDRESS = address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));
    Vm internal immutable vm = Vm(HEVM_ADDRESS);

    /*//////////////////////////////////////////////////////////////////////////
                                    HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Generates an address by hashing the name, labels the address and funds it with test assets.
    function createUser(string memory name, address[] calldata tokens) external returns (address payable addr) {
        addr = payable(makeAddr(name));
        vm.deal({ account: addr, newBalance: 100_000_000 ether });
        for (uint256 i; i < tokens.length;) {
            deal({ token: tokens[i], to: addr, give: 1000 * 10 ** IERC20Metadata(tokens[i]).decimals() });
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Moves block.number forward by a given number of blocks
    function mineBlocks(uint256 numBlocks) external {
        uint256 targetBlock = block.number + numBlocks;
        vm.roll(targetBlock);
    }
}
