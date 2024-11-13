// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

interface ICommet {

    struct UserBasic {
        int104 principal;
        uint64 baseTrackingIndex;
        uint64 baseTrackingAccrued;
        uint16 assetsIn;
    }

    function userBasic(address user) external view returns (ICommet.UserBasic memory);

    function supply(address asset, uint256 amount) external;
    function withdraw(address asset, uint256 amount) external;

    function getReserves() external view returns (int256);
    function getPrice(address priceFeed) external view returns (uint256);

    function totalSupply() external view returns (uint256);
    function totalBorrow() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function borrowBalanceOf(address account) external view returns (uint256);

    function isSupplyPaused() external view returns (bool);
    function isTransferPaused() external view returns (bool);
    function isWithdrawPaused() external view returns (bool);

    function accrueAccount(address account) external;
    function getSupplyRate(uint256 utilization) external view returns (uint64);

    /// @dev uint64
    function supplyKink() external view returns (uint256);

    function baseTrackingAccrued(address account) external view returns (uint64);
}
