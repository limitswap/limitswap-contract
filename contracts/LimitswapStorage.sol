// SPDX-License-Identifier: GPL-2.0
pragma solidity =0.7.6;


/**
 * The LimitswapStorage contract contains some storage.
 */
contract LimitswapStorage {
    address implementation;
    address gate;
    uint160 public currentSqrtPriceX96;
    uint256 public liquidity;
    uint256 totalLimit; //uint128 totalLimit0 + uint128 totalLimit1

    //[2]-buyside   rangeBuy(during sell, P(x) decrease) -> 0, rangeSell(during buy, P(x) increase) -> 1
    uint256 [2] wordHighExploited;
    mapping (int8 => uint256) [2] wordLowExploited;
    mapping (int16 => uint256) [2] tickExploited;

    mapping(int24 => tickDeep) Tick;
    mapping(address => mapping(int24 => uint256)) public buyShare;
    mapping(address => mapping(int24 => uint256)) public sellShare;
    //[2]-buyside   0 -> buy deep (Y), 1 -> sell deep (X)
    //buyside = 1:  amountIn in Y, deepBurned in Y
    //buyside = 0:  amountIn in X, deepBurned in X 
    //uint256 = uint128 deep + uint128 deeppriced
    mapping(int8 => uint256) [2] DeepWordHigh;
    mapping(int16 => uint256) [2] DeepWordLow;
    // mapping(int8 => uint256) [2] DeepWordHighPriced;
    // mapping(int16 => uint256) [2] DeepWordLowPriced;

    
    mapping(int16 => uint256) public tickBitmap;

    //mapping(address => mapping(int16 => uint256)) public buyShareWordMark;
    //mapping(address => mapping(int16 => uint256)) public sellShareWordMark;

    address public token0; //token X
    address public token1; //token Y
    
    int8 constant MAX_WORDHIGH = 63;
    int8 constant MIN_WORDHIGH = -63;

    struct FinderState {
        uint256 amountIn;
        uint256 amountOut;
        uint256 deepBurned;
        uint160 sqrtPriceX96; //toSqrtPriceX96
        int24 curTick;  //toTick
        bool buyside;
        int24 stopTick;       
    }

    struct tickDeep {
        uint128 buy;
        uint128 bought;
        uint128 sell;
        uint128 sold;
    }

    struct StepState {
        uint256 amountIn;
        uint256 amountOut;
        uint160 sqrtPriceX96;
        int24 nextTick;
        uint256 limitDeep;
        uint256 limitDeepPriced;
        bool buyside;
    }
}
