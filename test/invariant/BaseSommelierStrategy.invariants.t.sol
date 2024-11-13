// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { IStrategyHandler } from "../interfaces/IStrategyHandler.sol";
import { IStrategyWrapper } from "../interfaces/IStrategyWrapper.sol";
import { MockCellar } from "../mock/MockCellar.sol";
import {
    BaseSommelierStrategyHandler, BaseSommelierStrategyWrapper
} from "./handlers/BaseSommelierStrategyHandler.t.sol";
import { ERC4626, MaxApyVault, MaxApyVaultHandler } from "./handlers/MaxApyVaultHandler.t.sol";
import { SetUp } from "./helpers/SetUp.t.sol";
import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

contract BaseSommelierStrategyInvariants is SetUp {
    function setUp() public {
        _setUpToken();
        _setUpVault();

        ProxyAdmin _proxyAdmin = new ProxyAdmin(address(this));
        BaseSommelierStrategyWrapper _implementation = new BaseSommelierStrategyWrapper();

        MockCellar _underlyingCellar = new MockCellar(address(token), "Sommelier Cellar", "SC", true, 0);

        address[] memory keepers = new address[](1);
        keepers[0] = address(this);

        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(_implementation),
            address(_proxyAdmin),
            abi.encodeWithSignature(
                "initialize(address,address[],bytes32,address,address)",
                address(vault),
                keepers,
                bytes32(abi.encode("MaxApy Some WETH Strategy")),
                address(this),
                _underlyingCellar
            )
        );

        BaseSommelierStrategyWrapper _strategy = BaseSommelierStrategyWrapper(address(_proxy));
        vaultHandler = new MaxApyVaultHandler(vault, token);
        BaseSommelierStrategyHandler _strategyHandler =
            new BaseSommelierStrategyHandler(vault, _strategy, token, ERC4626(_underlyingCellar));

        _setUpStrategy(IStrategyWrapper(address(_strategy)), IStrategyHandler(address(_strategyHandler)));

        bytes4[] memory vaultSelectors = vaultHandler.getEntryPoints();

        targetSelector(FuzzSelector({ addr: address(vaultHandler), selectors: vaultSelectors }));

        excludeSender(address(_underlyingCellar));

        vm.label(address(_strategy), "BaseSommelierStrategy");
        vm.label(address(strategyHandler), "BSH");
    }

    function invariantBaseSommelierStrategy__VaultAccounting() public {
        vaultHandler.INVARIANT_A_SHARE_PREVIEWS();
        vaultHandler.INVARIANT_B_ASSET_PREVIEWS();
    }

    function invariantBaseSommelierStrategy__AssetEstimation() public {
        strategyHandler.INVARIANT_A_ESTIMATED_TOTAL_ASSETS();
    }

    function invariantBaseSommelierStrategy__CallSummary() public view {
        vaultHandler.callSummary();
        strategyHandler.callSummary();
    }
}
