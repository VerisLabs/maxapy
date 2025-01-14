// src/swaps/coordinator/SwapManager.sol
// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

// import {ISwapManager} from "./interfaces/ISwapManager.sol";
import {CommonSwapLib} from "./lib/CommonSwapLib.sol";
import {UniswapV3SwapLib} from "./lib/UniswapV3SwapLib.sol";
import {CurveSwapLib} from "./lib/CurveSwapLib.sol";
import {ITokenSwapRoutingOracle, SwapRoute} from "./interfaces/ITokenSwapRoutingOracle.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {console2} from "forge-std/console2.sol";

contract SwapManager is OwnableRoles {
    error InvalidSwapRoute();
    error SourceNotRegistered();

    uint256 public constant ADMIN_ROLE = _ROLE_0;

    ITokenSwapRoutingOracle public immutable oracle;

    constructor(address _oracle, address _admin) {
        oracle = ITokenSwapRoutingOracle(_oracle);
        _initializeOwner(_admin);
        _grantRoles(_admin, ADMIN_ROLE);
    }

    modifier onlyAdmin() {
        _checkRoles(ADMIN_ROLE);
        _;
    }

    function executeSwap(
        address fromToken,
        address toToken,
        uint256 amountIn,
        address recipient
    ) external returns (uint256) {
        // Get routes from oracle
        SwapRoute[] memory routes = oracle.getPath(
            oracle.getPathKey(fromToken, toToken)
        );

        if (routes.length == 0) revert InvalidSwapRoute();

        uint256 remainingAmount = amountIn;
        uint256 totalOutput = 0;

        // Execute swaps according to proportion
        for (uint256 i = 0; i < routes.length; i++) {
            SwapRoute memory route = routes[i];

            // Calculate amount for this route
            uint256 routeAmount = (amountIn * route.proportionBps) / 10000;
            console2.log("###   ~ file: SwapManager.sol:53 ~ )externalreturns ~ routeAmount:", routeAmount);

            if (i == routes.length - 1) {
                routeAmount = remainingAmount;
            }

            // Create params for this route
            CommonSwapLib.SwapParams memory swapParams = CommonSwapLib
                .SwapParams({
                    fromToken: fromToken,
                    toToken: toToken,
                    amountIn: routeAmount,
                    minAmountOut: 0,        // TODO calc min o/p amt
                    deadline: block.timestamp,
                    recipient: recipient
                });

            // Execute swap based on source
            uint256 amountOut;
            if (route.source == bytes32("Uniswap_V3")) {
                amountOut = UniswapV3SwapLib.executeSwap(swapParams);
            } else if (route.source == bytes32("Curve")) {
                amountOut = CurveSwapLib.executeSwap(swapParams);
            } else {
                revert SourceNotRegistered();
            }

            totalOutput += amountOut;
            remainingAmount -= routeAmount;
        }

        return totalOutput;
    }
}
