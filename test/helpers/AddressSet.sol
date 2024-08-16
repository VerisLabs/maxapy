// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

struct AddressSet {
    address[] addrs;
    mapping(address => bool) saved;
    mapping(address => uint256) index;
}

library LibAddressSet {
    function add(AddressSet storage s, address addr) internal {
        if (!s.saved[addr]) {
            uint256 i = count(s);
            s.addrs.push(addr);
            s.saved[addr] = true;
            s.index[addr] = i;
        }
    }

    function remove(AddressSet storage s, address addr) internal {
        if (!contains(s, addr)) revert();
        uint256 _count = count(s);

        uint256 lastIndex = _count - 1;
        uint256 index = s.index[addr];
        address temp = s.addrs[lastIndex];

        s.addrs[index] = temp;
        s.addrs[lastIndex] = addr;
        s.addrs.pop();

        s.saved[addr] = false;
        s.index[temp] = index;
    }

    function contains(AddressSet storage s, address addr) internal view returns (bool) {
        return s.saved[addr];
    }

    function count(AddressSet storage s) internal view returns (uint256) {
        return s.addrs.length;
    }

    function rand(AddressSet storage s, uint256 seed) internal view returns (address) {
        if (s.addrs.length > 0) {
            return s.addrs[seed % s.addrs.length];
        } else {
            return address(0);
        }
    }

    function forEach(AddressSet storage s, function(address) external func) internal {
        for (uint256 i; i < s.addrs.length; ++i) {
            func(s.addrs[i]);
        }
    }

    function reduce(
        AddressSet storage s,
        uint256 acc,
        function(uint256,address) external returns (uint256) func
    )
        internal
        returns (uint256)
    {
        for (uint256 i; i < s.addrs.length; ++i) {
            acc = func(acc, s.addrs[i]);
        }
        return acc;
    }
}
