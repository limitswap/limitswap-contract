// SPDX-License-Identifier: GPL-2.0
pragma solidity =0.7.6;

import './libraries/SafeMath.sol';
import './interfaces/ILimitswapFactory.sol';
import './interfaces/ILimitswapPair.sol';
import './interfaces/IERC20.sol';
import './libraries/BitMath.sol';
import './libraries/TransferHelper.sol';
import './libraries/StructuredLinkedList.sol';

//import './libraries/TickFinder.sol';

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint256 value) external returns (bool);
    function withdraw(uint) external;
}

//Router is only for add/remove liquidity and swap
//put/cancel limit order should direct interplay with the pair contract
contract LimitswapRouter {
    using SafeMath for uint256;
    using StructuredLinkedList for StructuredLinkedList.List;

    address public immutable factory;
    address public immutable WETH;

    constructor (address _factory, address _WETH) {
        factory = _factory;
        WETH = _WETH;
    }

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, 'LimitswapRouter: EXPIRED');
        _;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) internal returns (uint256 remainedA, uint256 remainedB, address pair) {
        // create the pair if it doesn't exist yet
        require(amountA == uint128(amountA) && amountB == uint128(amountB), 'LimitswapRouter: TOO_MUCH_INPUT');
        pair = ILimitswapFactory(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) {
            pair = ILimitswapFactory(factory).createPair(tokenA, tokenB);
        }
        if (ILimitswapPair(pair).liquidity() > 0) {
            uint160 currentSqrtPriceX96 = ILimitswapPair(pair).currentSqrtPriceX96();
            uint256 amountBDesired = tokenA < tokenB ?
                ILimitswapPair(pair).amount0ToAmount1(amountA, currentSqrtPriceX96):
                ILimitswapPair(pair).amount1ToAmount0(amountA, currentSqrtPriceX96);
            if (amountB < amountBDesired){
                uint256 amountADesired = tokenA < tokenB ?
                    ILimitswapPair(pair).amount1ToAmount0(amountB, currentSqrtPriceX96):
                    ILimitswapPair(pair).amount0ToAmount1(amountB, currentSqrtPriceX96);
                remainedA = amountA.sub(amountADesired);
            } else {
                remainedB = amountB.sub(amountBDesired);
            }
        }
        //alert when extreme price comes
        require( amountA!=remainedA && amountA!=remainedA, 'EXTREME PRICE');
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountAIn,
        uint256 amountBIn,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (uint256 remainedA, uint256 remainedB, address pair) = _addLiquidity(tokenA, tokenB, amountAIn, amountBIn);
        amountA = amountAIn.sub(remainedA);
        amountB = amountBIn.sub(remainedB);
        require(amountA >= amountAMin && amountB >= amountBMin, 'LimitswapRouter: SLIP ALERT');
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = ILimitswapPair(pair).mint(to);
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenIn,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        (uint256 remainedToken, uint256 remainedETH, address pair) = _addLiquidity(token, WETH, amountTokenIn, msg.value);
        amountToken = amountTokenIn.sub(remainedToken);
        amountETH = msg.value.sub(remainedETH);
        require(amountToken >= amountTokenMin && amountETH >= amountETHMin, 'LimitswapRouter: SLIP ALERT');
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = ILimitswapPair(pair).mint(to);
        // refund dust eth, if any
        if (remainedETH > 0) TransferHelper.safeTransferETH(msg.sender, remainedETH);
    }
//update 2021.5.14:  line 113 tokenA -> tokenB
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 share,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        (tokenA, tokenB) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        address pair = ILimitswapFactory(factory).getPair(tokenA, tokenB);
        TransferHelper.safeTransferFrom(pair, msg.sender, pair, share);
        uint256 balanceA = IERC20(tokenA).balanceOf(address(this));
        uint256 balanceB = IERC20(tokenB).balanceOf(address(this));
        ILimitswapPair(pair).burn(address(this));
        amountA = IERC20(tokenA).balanceOf(address(this)).sub(balanceA);
        amountB = IERC20(tokenB).balanceOf(address(this)).sub(balanceB);
        require(amountA >= amountAMin && amountB >= amountBMin, 'LimitswapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        transferExtraTokens(tokenA, tokenB, balanceA, balanceB, to);
    }

    function transferExtraTokens(address tokenA, address tokenB, uint256 balanceA, uint256 balanceB, address to) private {
        //without checking token order
        //must make sure tokenA < tokenB before calling
        uint256 amountA = IERC20(tokenA).balanceOf(address(this)).sub(balanceA);
        uint256 amountB = IERC20(tokenB).balanceOf(address(this)).sub(balanceB);
        if (tokenA == WETH) {
            IWETH(WETH).withdraw(amountA);
            TransferHelper.safeTransferETH(to, amountA);
        } else {
            TransferHelper.safeTransfer(tokenA, to, amountA);
        }
        if (tokenB == WETH) {
            IWETH(WETH).withdraw(amountB);
            TransferHelper.safeTransferETH(to, amountB);
        } else {
            TransferHelper.safeTransfer(tokenB, to, amountB);
        }
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint256 amountIn, address[] memory path, address _to) internal returns(uint256) {
        address to;
        bool zeroForToken0;
        for (uint i; i < path.length - 1; i++) {
            zeroForToken0 = path[i] < path[i + 1] ? false : true;
            to = i < path.length - 2 ? ILimitswapFactory(factory).getPair(path[i + 1], path[i + 2]) : _to;
            (amountIn,) = ILimitswapPair(ILimitswapFactory(factory).getPair(path[i], path[i + 1])).swap(amountIn, zeroForToken0, to);
        }
        return amountIn;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountOut) {
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, ILimitswapFactory(factory).getPair(path[0], path[1]), amountIn
        );
        amountOut = _swap(amountIn, path, to);
        require(amountOut >= amountOutMin, 'LimitswapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
    }
    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        ensure(deadline)
        returns (uint256 amountOut)
    {
        require(path[0] == WETH, 'LimitswapRouter: INVALID_PATH');
        IWETH(WETH).deposit{value: msg.value}();
        assert(IWETH(WETH).transfer(ILimitswapFactory(factory).getPair(path[0], path[1]), msg.value));
        amountOut = _swap(msg.value, path, to);
        require(amountOut >= amountOutMin, 'LimitswapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
    }

    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        ensure(deadline)
        returns (uint256 amountOut)
    {
        require(path[path.length - 1] == WETH, 'LimitswapRouter: INVALID_PATH');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, ILimitswapFactory(factory).getPair(path[0], path[1]), amountIn
        );
        amountOut = _swap(amountIn, path, address(this));
        require(amountOut >= amountOutMin, 'LimitswapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

    function getAmountsOut(uint amountIn, address[] calldata path) public view returns (uint[] memory amounts) {
        require(path.length >= 2, 'LimitswapRouter: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            address pair = ILimitswapFactory(factory).getPair(path[i], path[i+1]);
            (amountIn,,) = ILimitswapPair(pair).estOutput(amountIn, path[i] < path[i+1] ? false : true);
            amounts[i + 1] = amountIn;
        }
    }

    function getAmountOut(uint amountIn, address[] calldata path) public view returns (uint amountOut, uint amountOutNoPriceImpact) {
        require(path.length >= 2, 'LimitswapRouter: INVALID_PATH');
        amountOut = amountIn;
        amountOutNoPriceImpact = amountIn;
        for (uint i; i < path.length - 1; i++) {
            address pair = ILimitswapFactory(factory).getPair(path[i], path[i+1]);
            (amountOut,,) = ILimitswapPair(pair).estOutput(amountOut, path[i] < path[i+1] ? false : true);
            if (path[i] < path[i+1]){//input is token0
                amountOutNoPriceImpact = ILimitswapPair(pair).amount0ToAmount1(amountOutNoPriceImpact, ILimitswapPair(pair).currentSqrtPriceX96());
            } else {//input is token1
                amountOutNoPriceImpact = ILimitswapPair(pair).amount1ToAmount0(amountOutNoPriceImpact, ILimitswapPair(pair).currentSqrtPriceX96());
            }
        }
    }

    address public sender;
    mapping (address => StructuredLinkedList.List) limitOrders;

    //record of limit order
    //uint256 = padding X64 + address(uint160) pair + padding X7 + bool isSellShare + int24 tick
    //256 = 64 + 160 + 7 + 1 + 24
    function packRecord (address pair, int24 tick, bool isSellShare) internal pure returns(uint256 record) {
        record += uint256(uint24(tick));
        if (isSellShare) record += (1 << 24);
        record += (uint256(pair) << 32);
    }

    function resovleRecord (uint256 record) internal pure returns(address pair, int24 tick, bool isSellShare) {
        pair = address(record >> 32);
        tick = int24(record);
        isSellShare = (record & (1 << 24)) > 0 ? true : false;
    }


    function putLimitOrder (address pair, address tokenIn, uint256 amountIn, int24 tick) external returns(uint256 share) {
        address tokenA = ILimitswapPair(pair).token0();
        address tokenB = ILimitswapPair(pair).token1();
        require(tokenA == tokenIn || tokenB == tokenIn, 'TOKENERROR');
        uint256 balanceA = IERC20(tokenA).balanceOf(address(this));
        uint256 balanceB = IERC20(tokenB).balanceOf(address(this));
        TransferHelper.safeTransferFrom(
            tokenIn, msg.sender, pair, amountIn
        );
        bool isSellShare = tokenIn == ILimitswapPair(pair).token0()? true : false;
        sender = msg.sender;
        share = ILimitswapPair(pair).putLimitOrder(tick, amountIn, isSellShare);
        delete sender;
        limitOrders[msg.sender].pushFront(packRecord(pair, tick, isSellShare));
        transferExtraTokens(tokenA, tokenB, balanceA, balanceB, msg.sender);
    }

    function cancelLimitOrder (address pair, int24 tick, uint256 share, bool isSellShare) external returns(uint256 token0Out, uint256 token1Out) {
        address tokenA = ILimitswapPair(pair).token0();
        address tokenB = ILimitswapPair(pair).token1();
        uint256 balanceA = IERC20(tokenA).balanceOf(address(this));
        uint256 balanceB = IERC20(tokenB).balanceOf(address(this));
        uint256 totalUserShare;
        if (isSellShare) {
            totalUserShare = ILimitswapPair(pair).sellShare(msg.sender, tick);
        } else {
            totalUserShare = ILimitswapPair(pair).buyShare(msg.sender, tick);
        }
        if (share > totalUserShare) share = totalUserShare;
        sender = msg.sender;
        (token0Out, token1Out) = ILimitswapPair(pair).cancelLimitOrder(tick, share, isSellShare);
        delete sender;
        if(share == totalUserShare){
            limitOrders[msg.sender].remove(packRecord(pair, tick, isSellShare));
        }
        transferExtraTokens(tokenA, tokenB, balanceA, balanceB, msg.sender);
    }
//add: 2021.5.13
    function putLimitOrderETH (address pair, int24 tick) external payable returns (uint256 share) {
        address tokenA = ILimitswapPair(pair).token0();
        address tokenB = ILimitswapPair(pair).token1();
        require(tokenA == WETH || tokenB == WETH, 'TOKENERROR');
        uint256 balanceA = IERC20(tokenA).balanceOf(address(this));
        uint256 balanceB = IERC20(tokenB).balanceOf(address(this));
        IWETH(WETH).deposit{value: msg.value}();
        assert(IWETH(WETH).transfer(pair, msg.value));
        bool isSellShare = WETH == ILimitswapPair(pair).token0()? true : false;
        sender = msg.sender;
        share = ILimitswapPair(pair).putLimitOrder(tick, msg.value, isSellShare);
        delete sender;
        limitOrders[msg.sender].pushFront(packRecord(pair, tick, isSellShare));
        transferExtraTokens(tokenA, tokenB, balanceA, balanceB, msg.sender);
    }

    function getLimitOrdersRaw(address user, uint256 limit, uint256 offset) public view returns(uint256[] memory records){
        records = new uint[](limit);
        uint256 cursor;
        bool toContinue = true;
        for(uint i; (i < offset) && toContinue && (cursor > 0 || i == 0); i++){
            (toContinue, cursor) = limitOrders[user].getNextNode(cursor);
        }
        for(uint i; (i < limit) && toContinue && (cursor > 0 || i == 0); i++){
            (toContinue, cursor) = limitOrders[user].getNextNode(cursor);
            if(toContinue) records[i] = cursor;
        }
    }
//update 2021.5.14: positions(token0Out+token1Out) -> token0Out, token1Out
    function getLimitOrders(address user, uint256 limit, uint256 offset) public view
        returns(uint256[] memory records, uint256[] memory token0Out, uint256[] memory token1Out){
        records = getLimitOrdersRaw(user, limit, offset);
        token0Out = new uint256[](limit);
        token1Out = new uint256[](limit);
        uint256 position;
        for (uint i; i < limit; i++){
            if (records[i] > 0) {
                (address pair, int24 tick, bool isSellShare) = resovleRecord(records[i]);
                if (isSellShare){
                    position = ILimitswapPair(pair).sellShare(user, tick);
                } else {
                    position = ILimitswapPair(pair).buyShare(user, tick);
                }
                (token0Out[i], token1Out[i]) = ILimitswapPair(pair).getLimitTokens(tick, user, position, isSellShare);
                //positions[i] = (token0Out<<128) + (token1Out&uint128(-1));
            }
        }
    }

    //return value: uint256 = uint64 pairId + uint192 balance
    function getLPBalance (address user, uint256 scanLimit, uint256 scanOffset, uint256 resLimit) public view returns(uint256[] memory balances) {
        balances = new uint256[](resLimit);
        uint256 length = ILimitswapFactory(factory).allPairsLength();
        scanLimit = scanLimit + scanOffset > length ? length : scanLimit + scanOffset;
        length = 0;//reuse length as the length of balances
        for (uint i=scanOffset; i<scanLimit && length<resLimit; i++){
            uint256 balance = IERC20(ILimitswapFactory(factory).allPairs(i)).balanceOf(user);
            if (balance > 0){
                balances[length] = (i << 192) + balance;
                length ++;
            }
        }
    }

    function getPairInfo (address tokenA, address tokenB) public view
        returns(int24 currentTick, uint160 currentSqrtPriceX96, address pair, uint256 reserve0,
        uint256 reserve1, uint256 totalLimit0, uint256 totalLimit1) {
        (tokenA, tokenB) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        pair = ILimitswapFactory(factory).getPair(tokenA, tokenB);
        if (pair != address(0)){
            currentTick = ILimitswapPair(pair).currentTick();
            currentSqrtPriceX96 = ILimitswapPair(pair).currentSqrtPriceX96();
            reserve0 = ILimitswapPair(pair).reserve0();
            reserve1 = ILimitswapPair(pair).reserve1();
            (totalLimit0, totalLimit1) = ILimitswapPair(pair).getTotalLimit();
        }
    }




}
