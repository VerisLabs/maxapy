// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { BaseTest, IERC20, Vm, console2 } from "../base/BaseTest.t.sol";
import { BaseVaultTest } from "../base/BaseVaultTest.t.sol";
import { MaxApyVault, StrategyData } from "src/MaxApyVault.sol";
import { MaxApyRouter } from "src/MaxApyRouter.sol";
import { IMaxApyRouter } from "src/interfaces/IMaxApyRouter.sol";
import { IMaxApyVault } from "src/interfaces/IMaxApyVault.sol";
import { IWrappedToken } from "src/interfaces/IWrappedToken.sol";

import { MockStrategy } from "../mock/MockStrategy.sol";
import { MockLossyUSDCStrategy } from "../mock/MockLossyUSDCStrategy.sol";
import { MockERC777, IERC1820Registry } from "../mock/MockERC777.sol";
import { ReentrantERC777AttackerDeposit } from "../mock/ReentrantERC777AttackerDeposit.sol";
import { ReentrantERC777AttackerWithdraw } from "../mock/ReentrantERC777AttackerWithdraw.sol";
import { SigUtils } from "../utils/SigUtils.sol";
import { IERC20Permit } from "openzeppelin/token/ERC20/extensions/IERC20Permit.sol";
import { IERC20Metadata } from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import { WETH_MAINNET, USDC_MAINNET, _1_USDC } from "test/helpers/Tokens.sol";
import "src/helpers/AddressBook.sol";

contract MaxApyRouterTest is BaseVaultTest {
    IMaxApyRouter public router;
    SigUtils internal sigUtils;
    uint256 internal bobPrivateKey;

    function setUp() public {
        setupVault("MAINNET", WETH_MAINNET);
        MaxApyRouter _router = new MaxApyRouter(IWrappedToken(WETH_MAINNET));
        router = IMaxApyRouter(address(_router));

        IERC20(WETH_MAINNET).approve(address(router), type(uint256).max);
        vault.approve(address(router), type(uint256).max);

        vm.stopPrank();
        sigUtils = new SigUtils(IERC20Permit(USDC_MAINNET).DOMAIN_SEPARATOR());
        bobPrivateKey = 0xA11CE;
        users.bob = payable(vm.addr(bobPrivateKey));
        vm.startPrank(users.bob);
        vault.approve(address(router), type(uint256).max);

        vm.startPrank(users.eve);
        IERC20(WETH_MAINNET).approve(address(router), type(uint256).max);
        vault.approve(address(router), type(uint256).max);

        vm.startPrank(users.alice);

        vault.grantRoles(users.alice, vault.EMERGENCY_ADMIN_ROLE());

        vm.label(address(WETH_MAINNET), "WETH");
    }

    function testMaxApyRouter__Deposit() public {
        uint256 shares = router.deposit(vault, 10 ether, users.alice, 1e25);
        assertEq(shares, 1e25);
        assertEq(vault.totalDeposits(), 10 ether);
        assertEq(vault.totalSupply(), 1e25);
    }

    function testMaxApyRouter__Deposit_InsufficientShares() public {
        vm.expectRevert(abi.encodeWithSignature("InsufficientShares()"));
        router.deposit(vault, 10 ether, users.alice, 1e25 + 1);
        assertEq(vault.totalDeposits(), 0);
        assertEq(vault.totalSupply(), 0);
    }

    function testMaxApyRouter__Deposit_Native() public {
        uint256 shares = router.depositNative{ value: 10 ether }(vault, users.alice, 1e25);
        assertEq(shares, 1e25);
        assertEq(vault.totalDeposits(), 10 ether);
        assertEq(vault.totalSupply(), 1e25);
    }

    function testMaxApyRouter__Deposit_Native_InsufficientShares() public {
        vm.expectRevert(abi.encodeWithSignature("InsufficientShares()"));
        router.depositNative{ value: 10 ether }(vault, users.alice, 1e25 + 1);
        assertEq(vault.totalDeposits(), 0);
        assertEq(vault.totalSupply(), 0);
    }

    function testMaxApyRouter__Deposit_Permit() public {
        // Deploy the USDC vault
        MaxApyVault maxApyVault = new MaxApyVault(users.alice, USDC_MAINNET, "MaxApyVaultUSDC", "maxUSDCv2", TREASURY);
        IMaxApyVault _vault = IMaxApyVault(address(maxApyVault));
        deal(USDC_MAINNET, users.bob, 1000 * _1_USDC);
        vm.startPrank(users.bob);

        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: users.bob,
            spender: address(router),
            value: 100 * _1_USDC,
            nonce: 0,
            deadline: block.timestamp + 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobPrivateKey, digest);
        uint256 shares = router.depositWithPermit(_vault, permit.value, users.bob, permit.deadline, v, r, s, 1e14);
        assertEq(shares, 1e14);
        assertEq(_vault.totalDeposits(), 100 * _1_USDC);
        assertEq(_vault.totalSupply(), 1e14);
    }

    function testMaxApyRouter__Redeem() public {
        router.deposit(vault, 10 ether, users.alice, 1e25);
        uint256 assets = router.redeem(vault, 1e25, users.alice, 10 ether);
        assertEq(assets, 10 ether);
        assertEq(vault.totalDeposits(), 0);
        assertEq(vault.totalSupply(), 0);
    }

    function testMaxApyRouter__Redeem_InsufficientAssets() public {
        router.deposit(vault, 10 ether, users.alice, 1e25);
        vm.expectRevert(abi.encodeWithSignature("InsufficientAssets()"));
        router.redeem(vault, 1e25, users.alice, 10 ether + 1);
        assertEq(vault.totalDeposits(), 10 ether);
        assertEq(vault.totalSupply(), 1e25);
    }

    function testMaxApyRouter__Redeem_Native() public {
        router.deposit(vault, 10 ether, users.alice, 1e25);
        uint256 assets = router.redeemNative(vault, 1e25, users.alice, 10 ether);
        assertEq(assets, 10 ether);
        assertEq(vault.totalDeposits(), 0);
        assertEq(vault.totalSupply(), 0);
    }

    function testMaxApyRouter__Redeem_Native_InsufficientAssets() public {
        router.deposit(vault, 10 ether, users.alice, 1e25);
        vm.expectRevert(abi.encodeWithSignature("InsufficientAssets()"));
        router.redeemNative(vault, 1e25, users.alice, 10 ether + 1);
        assertEq(vault.totalDeposits(), 10 ether);
        assertEq(vault.totalSupply(), 1e25);
    }
}
