// SPDX-License-Identifier: GPL 2.0
pragma solidity >=0.5.0;

interface ILimitswapTradeCore {
    function tradeStartGate(uint256 amountIn, bool buyside, int24 stopTick) external returns (uint256 amountOut, uint256 deepBurned, uint160 sqrtPriceX96);
    function getLimitTokensCode (int24 tick, address user, uint256 share, bool isSellShare) external view returns(uint256 token0Out, uint256 token1Out);
}
