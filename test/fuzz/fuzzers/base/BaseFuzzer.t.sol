// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { AddressSet, LibAddressSet } from "../../../helpers/AddressSet.sol";
import { CommonBase } from "forge-std/Base.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { StdUtils } from "forge-std/StdUtils.sol";
import { console2 } from "forge-std/console2.sol";

abstract contract BaseFuzzer is CommonBase, StdUtils, StdCheats, StdAssertions {
    using LibAddressSet for AddressSet;

    ////////////////////////////////////////////////////////////////
    ///                      ACTORS CONFIG                       ///
    ////////////////////////////////////////////////////////////////
    AddressSet internal _actors;
    address internal currentActor;

    modifier createActor() {
        currentActor = msg.sender;
        _actors.add(msg.sender);
        _;
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = _actors.rand(actorIndexSeed);
        _;
    }

    ////////////////////////////////////////////////////////////////
    ///                      HELPERS                             ///
    ////////////////////////////////////////////////////////////////
    function forEachActor(function(address) external func) public {
        return _actors.forEach(func);
    }

    function _sub0(uint256 a, uint256 b) internal pure virtual returns (uint256) {
        unchecked {
            return a - b > a ? 0 : a - b;
        }
    }
}
