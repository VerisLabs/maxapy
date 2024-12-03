// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { BaseFuzzer, console2 } from "./base/BaseFuzzer.t.sol";

import { LibPRNG } from "solady/utils/LibPRNG.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";

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
        console2.log("###   ~ file: MaxApyVaultFuzzer.t.sol:30 ~ deposit ~ assets:", assets);

        deal(token, currentActor, assets);
        uint256 expectedShares = vault.previewDeposit(assets);
        console2.log("###   ~ file: MaxApyVaultFuzzer.t.sol:34 ~ deposit ~ expectedShares:", expectedShares);

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
        console2.log("###   ~ file: MaxApyVaultFuzzer.t.sol:54 ~ redeem ~ shares:", shares);

        uint256 expectedAssets = vault.previewRedeem(shares);
        console2.log("###   ~ file: MaxApyVaultFuzzer.t.sol:57 ~ redeem ~ expectedAssets:", expectedAssets);

        console2.log(
            "###   ~ file: MaxApyVaultFuzzer.t.sol:70 ~ redeem ~ vault.convertToAssets(shares):",
            vault.convertToAssets(shares)
        );

        vm.startPrank(currentActor);
        console2.log("SHARES:::::COMP:", shares);
        console2.log("EXPECTED:::::COMP:", expectedAssets);
        if (shares == 0 || expectedAssets == 0) vm.expectRevert();
        uint256 actualAssets = vault.redeem(shares, currentActor, currentActor);
        console2.log("###   ~ file: MaxApyVaultFuzzer.t.sol:68 ~ redeem ~ actualAssets:", actualAssets);

        assertGe(actualAssets, expectedAssets);
        vm.stopPrank();
    }

    function withdraw(LibPRNG.PRNG memory actorSeedRNG, uint256 assets) public useActor(actorSeedRNG.next()) {
        assets = bound(assets, 0, vault.maxWithdraw(currentActor));
        console2.log("###   ~ file: MaxApyVaultFuzzer.t.sol:64 ~ withdraw ~ assets:", assets);

        if (assets < 0.0001 ether || assets > 250 ether) return;
        uint256 expectedShares = vault.previewWithdraw(assets);
        vm.startPrank(currentActor);
        if (assets == 0 || expectedShares == 0) vm.expectRevert();
        uint256 actualShares = vault.withdraw(assets, currentActor, currentActor);
        console2.log("###   ~ file: MaxApyVaultFuzzer.t.sol:71 ~ withdraw ~ actualShares:", actualShares);

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
