// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { IERC777 } from "./MockERC777.sol";

import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";

contract ReentrantERC777AttackerWithdraw {
    IMaxApyVault public vault;

    uint256 counter;

    function setVault(IMaxApyVault _vault) public {
        vault = _vault;
    }

    function attack(uint256 amount) public {
        vault.redeem(amount, address(this), address(this));
    }

    function tokensReceived(address, address from, address, uint256 amount, bytes calldata, bytes calldata) external {
        if (from != address(0)) {
            vault.redeem(amount, address(this), address(this));
        }

        unchecked {
            ++counter;
        }
    }
}
