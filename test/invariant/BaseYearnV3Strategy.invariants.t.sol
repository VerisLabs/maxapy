// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import { BaseYearnV3StrategyHandler, BaseYearnV3StrategyWrapper } from "./handlers/BaseYearnV3StrategyHandler.t.sol";

import { MaxApyVaultHandler, MaxApyVault, ERC4626 } from "./handlers/MaxApyVaultHandler.t.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { Test } from "forge-std/Test.sol";
import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import { MockYVaultV3 } from "../mock/MockYVaultV3.sol";
import { SetUp } from "./helpers/SetUp.t.sol";
import { IStrategyHandler } from "../interfaces/IStrategyHandler.sol";
import { IStrategyWrapper } from "../interfaces/IStrategyWrapper.sol";

contract BaseYearnV3StrategyInvariants is SetUp {
    function setUp() public {
        _setUpToken();
        _setUpVault();

        ProxyAdmin _proxyAdmin = new ProxyAdmin(address(this));
        BaseYearnV3StrategyWrapper _implementation = new BaseYearnV3StrategyWrapper();

        MockYVaultV3 _underlyingYvault = new MockYVaultV3(address(token), "Yearn Vault", "YV", true, 0);

        address[] memory keepers = new address[](1);
        keepers[0] = address(this);

        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(_implementation),
            address(_proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Yearn WETH Strategy")),
                address(this),
                _underlyingYvault
            )
        );

        BaseYearnV3StrategyWrapper _strategy = BaseYearnV3StrategyWrapper(address(_proxy));
        vaultHandler = new MaxApyVaultHandler(vault, token);
        BaseYearnV3StrategyHandler _strategyHandler =
            new BaseYearnV3StrategyHandler(vault, _strategy, token, ERC4626(_underlyingYvault));

        _setUpStrategy(IStrategyWrapper(address(_strategy)), IStrategyHandler(address(_strategyHandler)));

        bytes4[] memory vaultSelectors = vaultHandler.getEntryPoints();

        targetSelector(FuzzSelector({ addr: address(vaultHandler), selectors: vaultSelectors }));

        excludeSender(address(_underlyingYvault));

        vm.label(address(strategyHandler), "BYH");
        vm.label(address(_strategy), "BaseYearnV3Strategy");
    }

    function invariantBaseYearnV3Strategy__VaultAccounting() public {
        vaultHandler.INVARIANT_A_SHARE_PREVIEWS();
        vaultHandler.INVARIANT_B_ASSET_PREVIEWS();
    }

    function invariantBaseYearnV3Strategy__AssetEstimation() public {
        strategyHandler.INVARIANT_A_ESTIMATED_TOTAL_ASSETS();
    }

    function invariantBaseYearnV3Strategy__CallSummary() public view {
        vaultHandler.callSummary();
        strategyHandler.callSummary();
    }
}
