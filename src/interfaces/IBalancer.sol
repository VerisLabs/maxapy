// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

struct SingleSwap {
    bytes32 poolId;
    SwapKind kind;
    IAsset assetIn;
    IAsset assetOut;
    uint256 amount;
    bytes userData;
}

struct JoinPoolRequest {
    IAsset[] assets;
    uint256[] maxAmountsIn;
    bytes userData;
    bool fromInternalBalance;
}

struct ExitPoolRequest {
    IAsset[] assets;
    uint256[] minAmountsOut;
    bytes userData;
    bool toInternalBalance;
}

struct FundManagement {
    address sender;
    bool fromInternalBalance;
    address payable recipient;
    bool toInternalBalance;
}

enum SwapKind {
    GIVEN_IN,
    GIVEN_OUT
}

enum JoinKind {
    INIT,
    EXACT_TOKENS_IN_FOR_BPT_OUT,
    TOKEN_IN_FOR_EXACT_BPT_OUT
}

enum ExitKind {
    EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
    EXACT_BPT_IN_FOR_TOKENS_OUT,
    BPT_IN_FOR_EXACT_TOKENS_OUT
}

interface IAsset { }

interface IBalancerVault {
    function swap(
        SingleSwap memory singleSwap,
        FundManagement memory funds,
        uint256 limit,
        uint256 deadline
    )
        external
        returns (uint256 amountCalculated);
    function joinPool(bytes32 poolId, address sender, address recipient, JoinPoolRequest memory request) external;

    function exitPool(bytes32 poolId, address sender, address recipient, ExitPoolRequest memory request) external;

    function getPoolTokens(bytes32 poolId)
        external
        view
        returns (address[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock);
}

interface IBalancerStablePool {
    function getRate() external view returns (uint256);
}

interface IBalancerQueries {
    function querySwap(SingleSwap memory singleSwap, FundManagement memory funds) external view returns (uint256);

    function queryJoin(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    )
        external
        view
        returns (uint256 bptOut, uint256[] memory amountsIn);

    function queryExit(
        bytes32 poolId,
        address sender,
        address recipient,
        ExitPoolRequest memory request
    )
        external
        view
        returns (uint256 bptIn, uint256[] memory amountsOut);
}
