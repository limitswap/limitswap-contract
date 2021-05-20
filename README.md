# LimitswapPair

测试前端： http://limitswap.belew.tech/

（on Heco chain）

## updates

### update 202005-2

添加了治理代币合约LimitswapToken以及矿池合约LimitswapMine

### update 202005-1

之前tick处未成交-已成交深度简单的用两个uint表示，部分情况下会导致已成交的份额被新入限价挂单稀释。

修改后用userPosition与tickPosition取代了简单的sellShare/buyShare跟踪，已成交的限价份额不可逆。

此外修正了部分bug：工厂合约的getPair自动调整输入token地址的顺序；pair的限价交互把token转移至msg.sender而非sender，以便路由合约解包WETH


## ERC20 interface

- function **name**() public view returns (string memory);
- function **symbol**() public view returns (string memory);
- function **decimals**() public view returns (uint8);
- function **totalSupply**() public view returns (uint256);
- mapping(address => uint256) public **balanceOf**
- mapping(address => mapping(address => uint256)) public **allowance**;
- function **approve**(address spender, uint256 value) external;
- function **transfer**(address to, uint256 value) external;
- function **transferFrom**(address from, address to, uint256 value) external;

## LP Related

- function **claimableReward** (address from, uint256 share) public view returns(uint256 reward0, uint256 reward1);

  *获取LP token对应的reward数量*

  输入：

  from: 持有的LP用户地址

  share: Lp token数量

  返回：

  reward0: token0奖励

  reward1: token1 奖励

- function **reserve0**() public view returns (uint256);

  *获取当前池的reserve0*

- function **reserve1**() public view returns (uint256);

  *获取当前池的reserve1*

- function **mint**(address to) external returns (uint256 share);

  *底层添加流动性函数，不建议直接调用*

- function **burn**(address to) external returns (uint amount0, uint amount1);

  *底层移除流动性函数，不建议直接调用*

- uint160 public **currentSqrtPriceX96**;

  *当前价格的算术平方根乘以2^96*

- uint256 public **liquidity**;

  *当前流动性*

## Limit Order Related

- function **getTotalLimit** () public view returns(uint256 totalLimit0, uint256 totalLimit1);

  *获取所有限价挂单累计的token0/1数量*

- function **currentTick**() public view returns(int24 tick);

  *当前价格刻度*

- function **putLimitOrder**(int24 tick, uint256 amount, bool zeroForToken1) external returns (uint256 share);

  *新建限价单*

  输入：

  tick: 挂单的价格刻度

  amount: 挂单的token数量

  zeroForToken1: 挂单的token是否是token0

- function **cancelLimitOrder**(int24 tick, uint256 share, bool isSellShare) external returns (uint256 token0Out, uint256 token1Out);

  *退出限价单*

  输入：

  tick: 挂单的价格刻度

  share: 需要退出的share数量

  isSellShare: 是否是卖单（挂的是token0）

- function **getLimitTokens** (int24 tick, address user, uint256 share, bool isSellShare) public view returns(uint256 token0, uint256 token1);

  *获取给定价格刻度烧掉一定share可获得的代币*

  输入：

  tick: 挂单的价格刻度

  user: 持有限价单的用户地址

  share: 需要退出的share数量

  isSellShare: 是否是卖单（挂的是token0）

  输出：

  token0: token0数量

  token1: token1数量

- function **getDeep** (int24 tick) public view returns(uint256 token0Deep, uint256 token1Deep);

  *获取给定价格刻度的挂单深度*

- function **buyShare**(address, int24) public view returns(uint256);

  *获取某地址在某价格刻度的买单share*

- function **sellShare**(address, int24) public view returns(uint256);

  *获取某地址在某价格刻度的卖单share*

## Swap

- function **estOutput**(uint256 amountIn, bool zeroForToken0) public view returns (uint256, uint256, uint160);

  *预计兑换产出*

  输入：

  amountIn:输入的代币数量

  zeroForToken0：是token1吗

  输出:

  amountOut:输出代币

  deepBurn:输出有多少来自限价

  newSqrtPriceX96:预计到达的价格

- function **swap**(uint256 amountIn, bool zeroForToken0, address to) public returns (uint256 amountOut, uint160 toSqrtPriceX96);

  *兑换*

  输入：

  amountIn:输入的代币数量

  zeroForToken0：是token1吗

  to:打到哪里


## Utils

- function **amount0ToAmount1**(uint256 amount0, uint160 sqrtPriceX96) public pure returns (uint256 amount1);
- function **amount1ToAmount0**(uint256 amount1, uint160 sqrtPriceX96) public pure returns (uint256 amount0);

## events

- Approval(address indexed owner, address indexed spender, uint256 value);
- Transfer(address indexed from, address indexed to, uint256 value);
- Mint(address indexed miner, uint256 amount0In, uint256 sqrtPriceX96, address to);
- Burn(address indexed miner, uint256 amount0In, uint256 sqrtPriceX96, address to);
- Swap(address indexed from, uint128 token0In, uint128 token1In, uint128 token0Out, uint128 token1Out);
- PutLimit(address indexed from, int24 tick, uint128 buyShare, uint128 sellShare, uint128 token0In, uint128 token1In);
- CancelLimit(address indexed from, int24 tick, uint128 buyShare, uint128 sellShare, uint128 token0Out, uint128 token1Out);

# LimitswapRouter

- function **addLiquidity**(address tokenA,address tokenB,uint256 amountAIn,uint256 amountBIn,uint256 deadline) external ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity);

  *添加流动性，两个代币都是ERC20*

  tokenA:A地址

  tokenB:B地址

  amountAIn:A数量

  amountBIn:B数量

  deadline: 超时时间戳（秒）

- function **addLiquidityETH**(address token, uint256 amountTokenIn, uint256 deadline) external payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) ;

  *添加流动性，一个代币是ETH*

  token:token地址

  amountTokenIn: token数量

  deadline: 超时时间戳（秒）

- function **removeLiquidity**(address tokenA, address tokenB, uint256 share, uint256 deadline) external payable ensure(deadline) returns (uint256 amountA, uint256 amountB);

  *移除流动性*

  如果一个是eth则token是WETH

  tokenA:A地址

  tokenB:B地址

  share:数量

  deadline: 超时时间戳（秒）

- function **swapExactTokensForTokens**(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external ensure(deadline) returns (uint256 amountOut);

  *用token换token*

  amountIn： 输入数量

  amountOutMin：最小输出，否则revert

  path：交易路径

  to：打给谁

  deadline: 超时时间戳（秒）

- function **swapExactETHForTokens**(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external payable ensure(deadline) returns (uint256 amountOut);

  *用ETH换token*

  amountOutMin：最小输出，否则revert

  path：交易路径

  to：打给谁

  deadline: 超时时间戳（秒）

- function **swapExactTokensForETH**(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external payable ensure(deadline) returns (uint256 amountOut);

  *用token换ETH*

  amountIn： 输入数量

  amountOutMin：最小输出，否则revert

  path：交易路径

  to：打给谁

  deadline: 超时时间戳（秒）

- function **getAmountsOut**(uint amountIn, address[] calldata path) public view returns (uint[] memory amounts);

  *预估产出（输出每一步）*

  输入：

  amountIn： 输入数量

  path：交易路径

  输出：

  amounts：每一步的输出

  function **getAmountOut**(uint amountIn, address[] calldata path) public view returns (uint amountOut, uint amountOutNoPriceImpact);

  *预估产出*

  输入：

  amountIn： 输入数量

  path：交易路径

  输出：

  amountOut：输出

  amountOutNoPriceImpact：简单通过每个pair的当前价格换算的数值


## on-chain storage

- function **getLimitOrdersRaw**(address user, uint256 limit, uint256 offset) public view returns(uint256[] memory records);

  *返回给定用户不为零的限价订单*

  输入：

  user: 用户地址

  limit: 搜索条数上限

  offset: 搜索偏移量，从offset搜索到offset+limit

  返回：

  records：用户限价订单记录，每一条为一个uint256，按如下格式解析

  `uint256 record = padding X64 + address(uint160) pair + padding X7 + bool isSellShare + int24(uint24) tick`

  作为参考的链上解析函数：

  ```solidity
  function resovleRecord (uint256 record) internal pure returns(address pair, int24 tick, bool isSellShare) {
      pair = address(record >> 32);
      tick = int24(record);
      isSellShare = (record & (1 << 24)) > 0 ? true : false;
  }
  ```

- function **getLimitOrders**(address user, uint256 limit, uint256 offset) public view returns(uint256[] memory records, uint256[] memory token0Out, uint256[] memory token1Out);

  *返回给定用户不为零的限价订单及对应刻度最大可以拿到的token数量*

  输入：

  user: 用户地址

  limit: 搜索条数上限

  offset: 搜索偏移量，从offset搜索到offset+limit

  返回：

  records：用户限价订单记录，每一条为一个uint256，解析见getLimitOrdersRaw

  token0Out: 可退出的token0数量

  token1Out: 可退出的token1数量

- function **getLPBalance** (address user, uint256 scanLimit, uint256 scanOffset, uint256 resLimit) public view returns(uint256[] memory balances);

  *批量获取LP token的余额*

  输入：

  user: 用户地址

  scanLimit: 搜索条数上限

  scanOffset: 搜索偏移量，搜索factory的getPairs数组从scanOffset搜索到scanOffset+scanLimit

  resLimit：本次最大返回记录条数

  返回：

  balances：LP余额记录，uint256 = uint64 pairId + uint192 balance, 其中pairId是pair在factory的getPairs数组对应的序号，balance是用户余额

  ​

# Deployed

## Rinkeby

### alpha-test

LimiswapTradeCore: 0xe294A70c0b442BB591eeeaE9651A8ca2DA6c6716

LIMITSWAPPAIR: 0x4c24128781E1e1CFd1f801d15666a705f9C80C51

LIMITSWAPFACTORY: 0x2D1C5C9E849B7c4a7Fd4375B595972a9277C2551

weth: 0xDf032Bc4B9dC2782Bb09352007D4C57B75160B15

LIMITSWAPROUTER:

0x0D73Ba4404f19288754E6Fa561a7E286f9C11988

testCoinA:

0x2c70De5b7C7B1375b6CaDCF608137fee47D89E7d

testCoinB:

0x91df34e7c7F0E61E536734A61e08bC3F01bd1922

## HT

TickMath: 0xE46BE58Ca9a9134a85287c8FFc420B2aad3A68Cf

LimiswapTradeCore: 0xd50270D85A4309ee6e4eC10658b510F0aB3b65b4

LIMITSWAPPAIR: 0x8d3dF6d1a0E44edB75ff66f852eEEDe0531a4919

LIMITSWAPFACTORY: 0x6ed5bc36DF8440734f13Bb4870681EDa0621cAe3

weth: 0x5545153CCFcA01fbd7Dd11C0b23ba694D9509A6F (WHT)

LIMITSWAPROUTER: 0x161E030954E926e0B51fFfE7277B978B36f637e1

testCoinA: 0x9c34c7A413Cf83dC4bed793E22bf2B1FEb65f1A4

testCoinB: 0xD7a9b24f756d8207aF6976B36DAF9B46eC5662e1
