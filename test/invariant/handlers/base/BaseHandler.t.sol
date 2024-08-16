// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { CommonBase } from "forge-std/Base.sol";
import { Test } from "forge-std/Test.sol";
import { StdUtils } from "forge-std/StdUtils.sol";
import { console2 } from "forge-std/console2.sol";
import { Actors } from "../../../helpers/Actors.sol";

abstract contract BaseHandler is CommonBase, Test, Actors {
    mapping(bytes32 => uint256) public calls;

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    ////////////////////////////////////////////////////////////////
    ///                      HELPERS                             ///
    ////////////////////////////////////////////////////////////////

    function _sub0(uint256 a, uint256 b) internal pure virtual returns (uint256) {
        unchecked {
            return a - b > a ? 0 : a - b;
        }
    }

    function callSummary() public view virtual;

    function getEntryPoints() public view virtual returns (bytes4[] memory);
}
