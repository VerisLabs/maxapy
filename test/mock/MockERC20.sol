// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "solady/tokens/ERC20.sol";

contract MockERC20 is ERC20 {
    string _name;
    string _symbol;
    uint8 _decimals;

    constructor(string memory _name_, string memory _symbol_, uint8 _decimals_) {
        _name = _name_;
        _symbol = _symbol_;
        _decimals = _decimals_;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}
