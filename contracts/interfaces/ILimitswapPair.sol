// SPDX-License-Identifier: GPL 2.0
pragma solidity =0.7.6;

interface ILimitswapPair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function liquidity() external view returns (uint256);
    function lastBalance0() external view returns (uint256);
    function lastBalance1() external view returns (uint256);
    function currentSqrtPriceX96() external view returns (uint160);
    function amount0ToAmount1(uint256 amount0, uint160 sqrtPriceX96) external pure returns (uint256 amount1);
    function amount1ToAmount0(uint256 amount1, uint160 sqrtPriceX96) external pure returns (uint256 amount0);
    function mint(address to) external returns (uint256 share);
    function burn(address to) external returns (uint amount0, uint amount1);
    function putLimitOrder(int24 tick, uint256 amount, bool zeroForToken1) external returns (uint256 share);
    function cancelLimitOrder(int24 tick, uint256 share, bool isSellShare) external returns (uint256 token0Out, uint256 token1Out);
    function swap(uint256 amountIn, bool zeroForToken0, address to) external returns (uint256 amountOut, uint160 toSqrtPriceX96);
    function initTokenAddress(address, address) external;
    function sellShare(address, int24) external view returns (uint256);
    function buyShare(address, int24) external view returns (uint256);
    function getLimitTokens (int24 tick, address user, uint256 share, bool isSellShare) external view returns(uint256 token0Out, uint256 token1Out);
    function getDeep (int24 tick) external view returns(uint256 token0Deep, uint256 token1Deep);
    function estOutput(uint256 amountIn, bool zeroForToken0) external view returns (uint256, uint256, uint160);
    function currentTick() external view returns(int24 tick);
    function reserve0() external view returns (uint256);
    function reserve1() external view returns (uint256);
    function getTotalLimit () external view returns(uint256 totalLimit0, uint256 totalLimit1);
    function flashLoan(address recipient, uint256 amount0, uint256 amount1, bytes calldata data) external;
}
