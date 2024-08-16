// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {
    BaseYearnV2StrategyHandler,
    BaseYearnV2StrategyWrapper,
    MockERC20
} from "./handlers/BaseYearnV2StrategyHandler.t.sol";
import { MaxApyVaultHandler, MaxApyVault } from "./handlers/MaxApyVaultHandler.t.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { Test } from "forge-std/Test.sol";
import { ProxyAdmin } from "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import { MockYVaultV2 } from "../mock/MockYVaultV2.sol";
import { SetUp } from "./helpers/SetUp.t.sol";
import { IStrategyHandler } from "../interfaces/IStrategyHandler.sol";
import { IStrategyWrapper } from "../interfaces/IStrategyWrapper.sol";

contract BaseYearnV2StrategyInvariants is SetUp {
    function setUp() public {
        _setUpToken();
        _setUpVault();

        ProxyAdmin _proxyAdmin = new ProxyAdmin(address(this));
        BaseYearnV2StrategyWrapper _implementation = new BaseYearnV2StrategyWrapper();

        MockYVaultV2 _underlyingYvault = new MockYVaultV2(address(token), "Yearn Vault", "YV");

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

        BaseYearnV2StrategyWrapper _strategy = BaseYearnV2StrategyWrapper(address(_proxy));
        vaultHandler = new MaxApyVaultHandler(vault, token);
        BaseYearnV2StrategyHandler _strategyHandler = new BaseYearnV2StrategyHandler(vault, _strategy, token);

        _setUpStrategy(IStrategyWrapper(address(_strategy)), IStrategyHandler(address(_strategyHandler)));

        bytes4[] memory vaultSelectors = vaultHandler.getEntryPoints();

        targetSelector(FuzzSelector({ addr: address(vaultHandler), selectors: vaultSelectors }));

        bytes4[] memory strategySelectors = _strategyHandler.getEntryPoints();
        targetSelector(FuzzSelector({ addr: address(_strategyHandler), selectors: strategySelectors }));

        excludeSender(address(_underlyingYvault));

        vm.label(address(_strategy), "BaseYearnV2Strategy");
        vm.label(address(_strategyHandler), "BYH");
    }

    function invariantBaseYearnV2Strategy__VaultAccounting() public {
        vaultHandler.INVARIANT_A_SHARE_PREVIEWS();
        vaultHandler.INVARIANT_B_ASSET_PREVIEWS();
    }

    function invariantBaseYearnV2Strategy__AssetEstimation() public {
        strategyHandler.INVARIANT_A_ESTIMATED_TOTAL_ASSETS();
    }

    function invariantBaseYearnV2Strategy__CallSummary() public view {
        vaultHandler.callSummary();
        strategyHandler.callSummary();
    }
}
