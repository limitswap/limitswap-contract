// SPDX-License-Identifier: GPL 2.0
pragma solidity =0.7.6;

import '../libraries/TickMath.sol';

contract libTest  {
    function getTickAtSqrtRatio(uint160 sqrtPriceX96) public pure returns (int24 tick) {
        return TickMath.getTickAtSqrtRatio(sqrtPriceX96);
    }
}
