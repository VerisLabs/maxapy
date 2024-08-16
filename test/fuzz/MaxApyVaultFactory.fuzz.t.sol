// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { MaxApyVaultFactory } from "src/MaxApyVaultFactory.sol";
import { MockERC20 } from "test/mock/MockERC20.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";

contract MaxApyVaultFactoryFuzzTest is Test {
    event CreateVault(address indexed asset, address vaultAddress);

    MockERC20 asset;
    address treasury = makeAddr("treasury");
    address deployer = makeAddr("deployer");
    address vaultAdmin = makeAddr("vaultAdmin");
    MaxApyVaultFactory public factory;

    function setUp() public {
        factory = new MaxApyVaultFactory(treasury);
        factory.grantRoles(deployer, factory.DEPLOYER_ROLE());
        asset = new MockERC20("Wrapped Ethereum", "WETH", 18);
    }

    function testFuzzMaxApyVaultFactory__Initialization() public {
        assertTrue(factory.hasAnyRole(address(this), factory.ADMIN_ROLE()));
        assertTrue(factory.hasAnyRole(address(this), factory.DEPLOYER_ROLE()));
        assertEq(factory.owner(), address(this));
    }

    function testFuzzMaxApyVaultFactory__DeployDeterministicVault(bytes32 salt) public {
        address computedAddress = factory.computeAddress(salt);
        vm.prank(deployer);
        address deployed = factory.deploy(address(asset), vaultAdmin, salt);
        IMaxApyVault deployedVault = IMaxApyVault(deployed);
        string memory expectedName = "MaxApy-WETH Vault";
        string memory expectedSymbol = "maxWETH";
        assertEq(keccak256(abi.encodePacked(expectedName)), keccak256(abi.encodePacked(deployedVault.name())));
        assertEq(keccak256(abi.encodePacked(expectedSymbol)), keccak256(abi.encodePacked(deployedVault.symbol())));
        assertEq(deployed, computedAddress);
        assertEq(deployedVault.owner(), vaultAdmin);
        assertTrue(deployedVault.hasAnyRole(vaultAdmin, deployedVault.ADMIN_ROLE()));
        assertEq(deployedVault.asset(), address(asset));
    }
}
