// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

library Constants {
    uint8 internal constant RESOLUTION = 96;
    uint256 internal constant Q96 = 0x1000000000000000000000000;
    uint256 internal constant Q128 = 0x100000000000000000000000000000000;
    // fee value in hundredths of a bip, i.e. 1e-6
    uint16 internal constant BASE_FEE = 100;
    int24 internal constant TICK_SPACING = 60;

    // max(uint128) / ( (MAX_TICK - MIN_TICK) / TICK_SPACING )
    uint128 internal constant MAX_LIQUIDITY_PER_TICK = 11_505_743_598_341_114_571_880_798_222_544_994;

    uint32 internal constant MAX_LIQUIDITY_COOLDOWN = 1 days;
    uint8 internal constant MAX_COMMUNITY_FEE = 250;
    uint256 internal constant COMMUNITY_FEE_DENOMINATOR = 1000;
}
