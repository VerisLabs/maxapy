// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { BaseFuzzer, console2, LibAddressSet, AddressSet } from "./base/BaseFuzzer.t.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IStrategyWrapper } from "../../interfaces/IStrategyWrapper.sol";
import { LibPRNG } from "solady/utils/LibPRNG.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

contract StrategyFuzzer is BaseFuzzer {
    using SafeTransferLib for address;
    using LibAddressSet for AddressSet;
    using LibPRNG for LibPRNG.PRNG;

    AddressSet strats;
    IMaxApyVault vault;
    address token;
    bytes4[] funcs;

    modifier returnIfNoStrats() {
        if (strats.count() == 0) return;
        _;
    }

    constructor(address[] memory _strats, IMaxApyVault _vault, address _token) {
        for (uint256 i = 0; i < _strats.length; i++) {
            strats.add(_strats[i]);
        }
        vault = _vault;
        token = _token;
        funcs.push(this.harvest.selector);
        funcs.push(this.exitStrategy.selector);
        funcs.push(this.gain.selector);
        funcs.push(this.loss.selector);
    }

    function harvest(LibPRNG.PRNG memory strategySeedRNG) public returnIfNoStrats {
        address strat = strats.rand(strategySeedRNG.next());
        try IStrategyWrapper(strat).harvest(0, 0, address(0), block.timestamp) {
            skip(100);
        } catch (bytes memory e) {
            e;
        }
    }

    function exitStrategy(LibPRNG.PRNG memory strategySeedRNG) public returnIfNoStrats {
        address strat = strats.rand(strategySeedRNG.next());
        vault.exitStrategy(strat);
        strats.remove(strat);
    }

    function gain(LibPRNG.PRNG memory strategySeedRNG, uint256 amount) public returnIfNoStrats {
        address strat = strats.rand(strategySeedRNG.next());
        amount = bound(amount, 0, 1_000_000 ether);
        if (amount == 0) return;
        deal(token, strat, amount);
    }

    function loss(LibPRNG.PRNG memory strategySeedRNG, uint256 amount) public returnIfNoStrats {
        address strat = strats.rand(strategySeedRNG.next());
        amount = bound(amount, 0, IStrategyWrapper(strat).underlyingAsset().balanceOf(strat));
        if (amount == 0) return;
        IStrategyWrapper(strat).triggerLoss(amount);
    }

    function rand(
        LibPRNG.PRNG memory functionSeedRNG,
        LibPRNG.PRNG memory strategySeedRNG,
        LibPRNG.PRNG memory argumentsSeedRNG
    )
        public
    {
        bytes4 selector = funcs[functionSeedRNG.next() % funcs.length];
        if (selector == this.harvest.selector) {
            this.harvest(strategySeedRNG);
        }
        if (selector == this.exitStrategy.selector) {
            this.exitStrategy(strategySeedRNG);
        }
        if (selector == this.gain.selector) {
            this.gain(strategySeedRNG, argumentsSeedRNG.next());
        }
        if (selector == this.loss.selector) {
            this.loss(strategySeedRNG, argumentsSeedRNG.next());
        }
    }

    function pickRandomStrategy(LibPRNG.PRNG memory strategySeedRNG) public view returns (address) {
        return strats.rand(strategySeedRNG.next());
    }
}
