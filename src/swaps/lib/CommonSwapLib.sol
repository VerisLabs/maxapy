// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

library CommonSwapLib {

    using SafeTransferLib for address;

    error InvalidToken();
    error InvalidAmount();
    error DeadlineExpired();
    error InvalidRecipient();
    
    struct SwapParams {
        address fromToken;
        address toToken;
        uint256 amountIn;
        uint256 minAmountOut;
        uint256 deadline;
        address recipient;
    }

    function validateSwapParams(SwapParams memory params) internal view {
        if(params.fromToken == address(0) || params.toToken == address(0)) {
            revert InvalidToken();
        }

        if(params.amountIn == 0) {
            revert InvalidAmount();
        }

        if(params.deadline > block.timestamp) {
            revert DeadlineExpired();
        }

        if(params.recipient == address(0)) {
            revert InvalidRecipient();
        }
    }

    function safeApprove(
        address token,
        address spender,
        uint256 amount
    ) internal {
        token.safeApprove(spender, amount);
    }

}