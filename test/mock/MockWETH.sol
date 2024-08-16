// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ERC20Permit, ERC20 } from "openzeppelin/token/ERC20/extensions/ERC20Permit.sol";

contract MockWETH is ERC20Permit {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) ERC20Permit(name) { }

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        (bool s,) = msg.sender.call{ value: amount }("");
        require(s);
    }
}
