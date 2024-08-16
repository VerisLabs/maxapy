// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { BaseFuzzer, console2 } from "./base/BaseFuzzer.t.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { LibPRNG } from "solady/utils/LibPRNG.sol";

contract MaxApyVaultFuzzer is BaseFuzzer {
    using SafeTransferLib for address;
    using LibPRNG for LibPRNG.PRNG;

    IMaxApyVault vault;
    address token;

    bytes4[] funcs;

    constructor(IMaxApyVault _vault, address _token) {
        vault = _vault;
        token = _token;
        funcs.push(this.deposit.selector);
        funcs.push(this.mint.selector);
        funcs.push(this.redeem.selector);
        funcs.push(this.withdraw.selector);
    }

    function deposit(uint256 assets) public createActor {
        assets = bound(assets, 0, vault.maxDeposit(currentActor));
        deal(token, currentActor, assets);
        uint256 expectedShares = vault.previewDeposit(assets);
        vm.startPrank(currentActor);
        token.safeApprove(address(vault), assets);
        if (assets == 0 || expectedShares == 0) vm.expectRevert();
        uint256 actualShares = vault.deposit(assets, currentActor);
        assertEq(actualShares, expectedShares);
        vm.stopPrank();
    }

    function mint(uint256 shares) public createActor {
        shares = bound(shares, 0, vault.maxMint(currentActor));
        uint256 expectedAssets = vault.previewMint(shares);
        deal(token, currentActor, expectedAssets * 2);
        vm.startPrank(currentActor);
        token.safeApprove(address(vault), type(uint256).max);
        if (shares == 0 || expectedAssets == 0 || expectedAssets > token.balanceOf(currentActor)) vm.expectRevert();
        uint256 actualAssets = vault.mint(shares, currentActor);
        assertEq(actualAssets, expectedAssets);
        vm.stopPrank();
    }

    function redeem(LibPRNG.PRNG memory actorSeedRNG, uint256 shares) public useActor(actorSeedRNG.next()) {
        shares = bound(shares, 0, vault.maxRedeem(currentActor));
        uint256 expectedAssets = vault.previewRedeem(shares);
        vm.startPrank(currentActor);
        if (shares == 0 || expectedAssets == 0) vm.expectRevert();
        uint256 actualAssets = vault.redeem(shares, currentActor, currentActor);
        assertGe(actualAssets, expectedAssets);
        vm.stopPrank();
    }

    function withdraw(LibPRNG.PRNG memory actorSeedRNG, uint256 assets) public useActor(actorSeedRNG.next()) {
        assets = bound(assets, 0, vault.maxWithdraw(currentActor));
        if (assets < 0.0001 ether) return;
        uint256 expectedShares = vault.previewWithdraw(assets);
        vm.startPrank(currentActor);
        if (assets == 0 || expectedShares == 0) vm.expectRevert();
        uint256 actualShares = vault.withdraw(assets, currentActor, currentActor);
        assertLe(actualShares, expectedShares);
        vm.stopPrank();
    }

    function rand(
        LibPRNG.PRNG memory actorSeedRNG,
        LibPRNG.PRNG memory functionSeedRNG,
        LibPRNG.PRNG memory argumentsSeedRNG
    )
        public
    {
        bytes4 selector = funcs[functionSeedRNG.next() % funcs.length];
        if (selector == this.deposit.selector) {
            this.deposit(argumentsSeedRNG.next());
        }
        if (selector == this.mint.selector) {
            this.mint(argumentsSeedRNG.next());
        }
        if (selector == this.redeem.selector) {
            this.redeem(actorSeedRNG, argumentsSeedRNG.next());
        }
        if (selector == this.withdraw.selector) {
            this.withdraw(actorSeedRNG, argumentsSeedRNG.next());
        }
    }
}
