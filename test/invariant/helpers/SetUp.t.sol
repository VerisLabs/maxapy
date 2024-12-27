// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { IStrategyHandler } from "../../interfaces/IStrategyHandler.sol";
import { IStrategyWrapper } from "../../interfaces/IStrategyWrapper.sol";
import { MaxApyVault, MaxApyVaultHandler, MockERC20 } from "../handlers/MaxApyVaultHandler.t.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { Test } from "forge-std/Test.sol";

contract SetUp is StdInvariant, Test {
    MaxApyVaultHandler vaultHandler;
    IStrategyHandler strategyHandler;
    MaxApyVault vault;
    MockERC20 token;

    function _setUpToken() internal {
        token = new MockERC20("MockERC20", "MERC", 6);
        vm.label(address(token), "WETH");
    }

    function _setUpVault() internal {
        vault = new MaxApyVault(address(this), address(token), "MaxApyVault", "max", address(1));
        vaultHandler = new MaxApyVaultHandler(vault, token);
        targetContract(address(vaultHandler));
        bytes4[] memory selectors = vaultHandler.getEntryPoints();
        targetSelector(FuzzSelector({ addr: address(vaultHandler), selectors: selectors }));
        vm.label(address(vault), "VAULT");
        vm.label(address(vaultHandler), "MVH");
    }

    function _setUpStrategy(IStrategyWrapper _strategy, IStrategyHandler _strategyHandler) internal {
        vault.addStrategy(address(_strategy), 6000, type(uint256).max, 0, 200);
        _strategy.grantRoles(address(_strategyHandler), _strategy.KEEPER_ROLE());
        _strategy.grantRoles(address(_strategyHandler), _strategy.VAULT_ROLE());
        _strategy.setAutopilot(true);
        bytes4[] memory strategySelectors = _strategyHandler.getEntryPoints();
        targetSelector(FuzzSelector({ addr: address(_strategyHandler), selectors: strategySelectors }));
        excludeSender(address(vault));
        excludeSender(address(_strategy));
        strategyHandler = _strategyHandler;
    }
}
