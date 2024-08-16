// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import { MaxApyHarvester } from "../../src/periphery/MaxApyHarvester.sol";

contract MaxApyHarvesterDeployment is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address admin = vm.envAddress("ADMIN_ADDRESS");
        address[] memory keepers = new address[](1);
        keepers[0] = vm.envAddress("KEEPER1_ADDRESS"); // harvester address

        address[] memory allocators = new address[](1);
        allocators[0] = vm.envAddress("ALLOCATOR_ADDRESS"); // allocator address

        MaxApyHarvester harvester = new MaxApyHarvester(admin, keepers, allocators);

        console.log("MaxApyHarvester deployed at:", address(harvester));

        vm.stopBroadcast();

        // Verify the contract
        if (block.chainid == 137) { // Polygon Mainnet
            verifyContract(address(harvester), abi.encode(admin, keepers, allocators));
        }
    }

    function verifyContract(address contractAddress, bytes memory) internal {
        string[] memory cmds = new string[](4);
        cmds[0] = "forge";
        cmds[1] = "verify-contract";
        cmds[2] = vm.toString(contractAddress);
        cmds[3] = "MaxApyHarvester";

        bytes memory result = vm.ffi(cmds);
        console.log(string(result));
    }
}
