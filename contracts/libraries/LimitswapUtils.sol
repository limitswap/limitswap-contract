// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
import './FullMath.sol';
import './SafeMath.sol';

library LimitswapUtils {
    using SafeMath for uint256;

    function amount0ToAmount1(uint256 amount0, uint160 sqrtPriceX96) public pure returns (uint256 amount1){
        if (sqrtPriceX96 == 0 || amount0 == 0) return 0;
        amount1 = (((amount0.mul(uint256(sqrtPriceX96)))>>96).mul(uint256(sqrtPriceX96)))>>96;
        if (amount1 > 0) amount1--;
    }

    function amount1ToAmount0(uint256 amount1, uint160 sqrtPriceX96) public pure returns (uint256 amount0){
        if (sqrtPriceX96 == 0 || amount1 == 0) return 0;
        amount0 = FullMath.mulDiv(FullMath.mulDiv(amount1, 1<<96, sqrtPriceX96),1<<96,sqrtPriceX96);
    }
}