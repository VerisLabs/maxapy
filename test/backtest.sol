// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import "src/helpers/AddressBook.sol";
import { IBeefyVault } from "src/interfaces/IBeefyVault.sol";
import { BaseTest, IERC20, Vm, console2 } from "./base/BaseTest.t.sol";

// 1. Get our strategy
// 2. Know what value (share price) we need from strategy
// 3. Log the evolution of share price

contract Backtester is BaseTest {
    IBeefyVault beefyVault = IBeefyVault(BEEFY_MAI_USDCE_POLYGON);

    function setUp() public {
        super._setUp("POLYGON");
        vm.rollFork(57_987_112); //62_790_188
    }

    function testBeefyMaiUSDCe_Backtest() public {
        uint256 initialBn = block.number;
        uint256 bn;
        for (uint256 i = 0; i < 120; i++) {
            console2.log(bn, beefyVault.getPricePerFullShare());
            super._setUp("POLYGON");
            bn = initialBn + 20_000;
            vm.rollFork(bn); // approx 0.5d
            initialBn = bn;
        }
    }
}
