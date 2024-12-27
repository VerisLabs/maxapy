// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

import "./IStrategy.sol";
import "openzeppelin/interfaces/IERC20.sol";

interface IBeefyVault is IERC20 {
    function deposit(uint256) external;
    function depositAll() external;
    function withdraw(uint256) external;
    function withdrawAll() external;
    function getPricePerFullShare() external view returns (uint256);
    function upgradeStrat() external;
    function balance() external view returns (uint256);
    function want() external view returns (IERC20);
    // function strategy() external view returns (IStrategy);
}
