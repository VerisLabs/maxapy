// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { AddressSet, LibAddressSet } from "./AddressSet.sol";

abstract contract Actors {
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

    function reduceActors(
        uint256 acc,
        function(uint256,address) external returns (uint256) func
    )
        public
        returns (uint256)
    {
        return _actors.reduce(acc, func);
    }

    function actors() public view returns (address[] memory) {
        return _actors.addrs;
    }
}
