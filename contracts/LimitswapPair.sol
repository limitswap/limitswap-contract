// SPDX-License-Identifier: GPL-2.0
pragma solidity =0.7.6;

import './interfaces/IERC20.sol';
import './interfaces/ILimitswapGate.sol';
import './interfaces/ILimitswapTradeCore.sol';
import './interfaces/ILimitswapFlashLoanCallback.sol';

import './libraries/Math.sol';
import './libraries/TickMath.sol';
import './libraries/SafeCast.sol';
import './libraries/SafeMath.sol';
import './libraries/FullMath.sol';
import './libraries/TickBitmap.sol';
import './libraries/SqrtPriceMath.sol';
import './libraries/TransferHelper.sol';

import './LimitswapStorage.sol';

interface ILimitswapCaller {
    function sender() external returns (address);
}

abstract contract LimitSwapERC20 is LimitswapStorage{
    using SafeMath for uint256;
    using SafeCast for uint256;

    function name() public view virtual returns (string memory);
    function symbol() public view virtual returns (string memory);
    uint8 public constant decimals = 18;
    uint256  public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    mapping(address => uint256) public writeOffReward0PerTokenX96;
    mapping(address => uint256) public writeOffReward1PerTokenX96;

    uint256 public reward0PerTokenX96;
    uint256 public reward1PerTokenX96;

    bool unlocked;
    modifier lock() {
        require(unlocked, 'LOK');
        unlocked = false;
        _;
        unlocked = true;
    }


    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    //before transfer: from: writeoff: w1, balance: t1; to: writeoff: w2, balance: t2;
    //transfer t
    //after transfer: from: writeoff: w1, balance: t1-t; to: writeoff: (w2 * t2 + w1 * t) / (t2 + t)
    function _calWriteOffRewardPerToken(uint256 writeOffFromX96, uint256 writeOffToBeforeX96, uint256 toBalanceBefore, uint256 toBalanceAdd)
        private pure returns (uint256 writeOffToNewX96){
        writeOffToNewX96 = (writeOffToBeforeX96.mul(toBalanceBefore)).add(writeOffFromX96.mul(toBalanceAdd))
            .div(toBalanceBefore.add(toBalanceAdd));
    }

    function _reward (uint256 reward0, uint256 reward1) internal {
        address _feeCollector = ILimitswapGate(gate).feeCollector();
        if (_feeCollector == address(0)){//reward to users
            if (totalSupply > 0) {
                if (reward0>0) reward0PerTokenX96 = reward0PerTokenX96.add((reward0<<96).div(totalSupply));
                if (reward1>0) reward1PerTokenX96 = reward1PerTokenX96.add((reward1<<96).div(totalSupply));
            }
        } else {
            TransferHelper.safeTransfer(token0, _feeCollector, reward0);
            TransferHelper.safeTransfer(token1, _feeCollector, reward1);
        }
    }

    function claimableReward (address from, uint256 share) public view returns(uint256 reward0, uint256 reward1) {
        //require(share <= balanceOf[from]);
        reward0 = FullMath.mulDiv(share, reward0PerTokenX96.sub(writeOffReward0PerTokenX96[from]), 1<<96);
        reward1 = FullMath.mulDiv(share, reward0PerTokenX96.sub(writeOffReward0PerTokenX96[from]), 1<<96);
    }


    function _mint(address to, uint256 value) internal {
        if(value==0) return;
        totalSupply = totalSupply.add(value);
        uint256 oldBalanceTo = balanceOf[to];
        balanceOf[to] = balanceOf[to].add(value);
        writeOffReward0PerTokenX96[to] = _calWriteOffRewardPerToken(reward0PerTokenX96, writeOffReward0PerTokenX96[to], oldBalanceTo, value);
        writeOffReward1PerTokenX96[to] = _calWriteOffRewardPerToken(reward1PerTokenX96, writeOffReward1PerTokenX96[to], oldBalanceTo, value);
        emit Transfer(address(0), to, value);
    }

    //reward: (rewardPerToken - writeOffRewardPerToken) * burnAmount
    function _burn(address from, uint256 value) internal returns(uint256 reward0, uint256 reward1) {
        balanceOf[from] = balanceOf[from].sub(value);
        totalSupply = totalSupply.sub(value);
        emit Transfer(from, address(0), value);
        reward0 = ((reward0PerTokenX96.sub(writeOffReward0PerTokenX96[from])).mul(value))>>96;
        reward1 = ((reward1PerTokenX96.sub(writeOffReward1PerTokenX96[from])).mul(value))>>96;
    }


    function _transfer(address from, address to, uint256 value) private {
        uint256 oldBalanceTo = balanceOf[to];
        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = oldBalanceTo.add(value);
        writeOffReward0PerTokenX96[to] = _calWriteOffRewardPerToken(writeOffReward0PerTokenX96[from], writeOffReward0PerTokenX96[to], oldBalanceTo, value);
        writeOffReward1PerTokenX96[to] = _calWriteOffRewardPerToken(writeOffReward1PerTokenX96[from], writeOffReward1PerTokenX96[to], oldBalanceTo, value);
        emit Transfer(from, to, value);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        value.toUint128(); //prevent overflow
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        if (allowance[from][msg.sender] != uint256(-1)) {
            allowance[from][msg.sender] = allowance[from][msg.sender].sub(value);
        }
        _transfer(from, to, value);
        return true;
    }
}


contract LimitswapPair is LimitSwapERC20{
    using SafeMath for uint256;
    using SafeCast for uint256;
    using TickBitmap for mapping(int16 => uint256);

    address public immutable tradeCore;
    uint256 public lastBalance0;
    uint256 public lastBalance1;

    function initTokenAddress (address _token0, address _token1) public {
        require(token0 == address(0));
        token0 = _token0;
        token1 = _token1;
        unlocked = true;
    }


    constructor(address _tradeCore) {
        tradeCore = _tradeCore;
    }

    function name() public view override returns (string memory) {
        return string(abi.encodePacked('LimitSwap LP Token: ',IERC20(token0).name(),'/',IERC20(token1).name()));
    }

    function symbol() public view override returns (string memory) {
        return name();
    }

    function amount0ToAmount1(uint256 amount0, uint160 sqrtPriceX96) public pure returns (uint256 amount1){
        if (sqrtPriceX96 == 0 || amount0 == 0) return 0;
        amount1 = (((amount0.mul(uint256(sqrtPriceX96)))>>96).mul(uint256(sqrtPriceX96)))>>96;
        if (amount1 > 0) amount1--;
    }

    function amount1ToAmount0(uint256 amount1, uint160 sqrtPriceX96) public pure returns (uint256 amount0){
        if (sqrtPriceX96 == 0 || amount1 == 0) return 0;
        amount0 = FullMath.mulDiv(FullMath.mulDiv(amount1, 1<<96, sqrtPriceX96),1<<96,sqrtPriceX96);
    }

    /// @dev Get the pool's balance of token0
    /// @dev This function is gas optimized to avoid a redundant extcodesize check in addition to the returndatasize
    /// check
    function balance0() private view returns (uint256) {
        (bool success, bytes memory data) =
            token0.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)));
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }

    /// @dev Get the pool's balance of token1
    /// @dev This function is gas optimized to avoid a redundant extcodesize check in addition to the returndatasize
    /// check
    function balance1() private view returns (uint256) {
        (bool success, bytes memory data) =
            token1.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)));
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }

    function LP2Tokens (uint256 LPamount) public view returns (uint256 amount0, uint256 amount1) {
        LPamount = Math.min(totalSupply, LPamount);
        if (totalSupply == 0) return (0, 0);
        uint256 _reserve0 = reserve0();
        amount0 = FullMath.mulDiv(LPamount, _reserve0, totalSupply);
        if ( _reserve0 == amount0) amount0 --; //always keep at least 1 to maintain liquidity
        amount1 = amount0ToAmount1(amount0, currentSqrtPriceX96);
        if (reserve1() == amount1) amount1 --; //always keep at least 1 to maintain liquidity
    }


    function reserve0() public view returns (uint256){
        return FullMath.mulDivRoundingUp(liquidity, 1<<96, currentSqrtPriceX96);
    }

    function reserve1() public view returns (uint256){
        return FullMath.mulDivRoundingUp(liquidity, currentSqrtPriceX96, 1<<96);
    }

    event Mint(address indexed miner, uint256 amount0In, uint256 sqrtPriceX96, address to);
    event Burn(address indexed miner, uint256 amount0In, uint256 sqrtPriceX96, address to);

    function getTotalLimit () public view returns(uint256 totalLimit0, uint256 totalLimit1) {
        totalLimit0 = totalLimit >> 128;
        totalLimit1 = uint128(totalLimit);
    }


    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) lock external returns (uint256 share) {
        uint256 amount0In = balance0().sub(lastBalance0);
        uint256 amount1In = balance1().sub(lastBalance1);
        amount0In.toUint128();
        amount1In.toUint128();
        uint256 _reserve0;
        if (currentSqrtPriceX96 == 0){ //initiate start price
            liquidity = Math.sqrt(amount1In.mul(amount0In));
            currentSqrtPriceX96 = (FullMath.mulDiv(liquidity, 1<<96, amount0In)).toUint160();
        } else {
            //check input
            uint256 amount1InShouldBe = amount0ToAmount1(amount0In, currentSqrtPriceX96);
            if (amount1In < amount1InShouldBe) {
                uint256 _amount0In = amount1ToAmount0(amount1InShouldBe, currentSqrtPriceX96);
                _reward(amount0In - _amount0In, 0);
                amount0In = _amount0In;
            }
            if (amount1In > amount1InShouldBe){
                _reward(0, amount1In - amount1InShouldBe);
            }
            //update liquidity
            _reserve0 = reserve0();
            liquidity = FullMath.mulDiv(_reserve0.add(amount0In), currentSqrtPriceX96, 1<<96);
        }
        if (totalSupply == 0){
            share = FullMath.mulDiv(amount0In, currentSqrtPriceX96, 1<<96);
        } else {
            share = FullMath.mulDiv(amount0In, totalSupply, _reserve0);
        }
        _mint(to, share);
        //emit event
        emit Mint(msg.sender, amount0In, currentSqrtPriceX96, to);
        //update balance tracers
        lastBalance0 = balance0();
        lastBalance1 = balance1();
    }


    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) lock external returns (uint amount0, uint amount1){
        uint256 share = balanceOf[address(this)];
        (amount0, amount1) = LP2Tokens(share);
        liquidity = FullMath.mulDiv(reserve0().sub(amount0), currentSqrtPriceX96, 1<<96);
        if (liquidity == 0) liquidity = 1; //always keep at least 1 to maintain liquidity
        //add reward
        amount0 = amount0.add(FullMath.mulDiv(share, reward0PerTokenX96.sub(writeOffReward0PerTokenX96[address(this)]), 1<<96));
        amount1 = amount1.add(FullMath.mulDiv(share, reward1PerTokenX96.sub(writeOffReward1PerTokenX96[address(this)]), 1<<96));
        //transfer tokens
        TransferHelper.safeTransfer(token0, to, Math.min(amount0, balance0()));
        TransferHelper.safeTransfer(token1, to, Math.min(amount1, balance1()));
        _burn(address(this), share);
        //update liquidity
        emit Burn(msg.sender, amount0, currentSqrtPriceX96, to);
        //update balance tracers
        lastBalance0 = balance0();
        lastBalance1 = balance1();
    }

    function wordHighMap(int8 wordHigh) internal pure returns (uint8 wordHighPos){
        wordHighPos = uint8(int256(wordHigh) + 127);
    }

    function isExploited (int24 tick, uint buyside) public view returns(bool) {
        (int8 wordHigh, uint8 wordLow, int16 word, uint8 posInWord) = TickMath.resolvePos(tick);
        if (TickMath.getBit(wordHighExploited[buyside], wordHighMap(wordHigh))) return true;
        else if (TickMath.getBit(wordLowExploited[buyside][wordHigh], wordLow)) return true;
        else if (TickMath.getBit(tickExploited[buyside][word], posInWord)) return true;
        else return false;
    }

    function updateDeep(int24 tick, tickDeep memory tickInfo, uint160 sqrtPriceX96, int256 newDeep0, int256 newDeep1) private {
        // bytes4(keccak256(bytes('updateDeepGate(int24,uint128,uint128,uint128,uint128,uint160,int256,int256)')));
        (bool success,bytes memory result) = tradeCore.delegatecall(abi.encodeWithSelector(0xf46c855e,
             tick, tickInfo.buy, tickInfo.bought, tickInfo.sell, tickInfo.sold, sqrtPriceX96, newDeep0, newDeep1));
        require(success, string(result));
    }

    function transferTokens (address to, uint256 token0Out, uint256 token1Out, bool feeOn) internal returns(uint256 fee0, uint256 fee1){
        if (feeOn) {
            uint256 actualToken0Out = token0Out == 0 ? 0 : token0Out.mul(997).div(1000);
            uint256 actualToken1Out = token1Out == 0 ? 0 : token1Out.mul(997).div(1000);
            fee0 = token0Out - actualToken0Out;
            fee1 = token1Out - actualToken1Out;
            token0Out = actualToken0Out;
            token1Out = actualToken1Out;
        }
        if (token0Out > 0) {
            TransferHelper.safeTransfer(token0, to, Math.min(token0Out, balance0()));
        }
        if (token1Out > 0) {
            TransferHelper.safeTransfer(token1, to, Math.min(token1Out, balance1()));
        }
    }

    function currentTick() public view returns(int24 tick) {
        tick = TickMath.getTickAtSqrtRatio(currentSqrtPriceX96);
    }

    event Swap(address indexed from, uint128 token0In, uint128 token1In, uint128 token0Out, uint128 token1Out, uint160 newPriceX96);
    event PutLimit(address indexed from, int24 tick, uint128 buyShare, uint128 sellShare, uint128 token0In, uint128 token1In);
    event CancelLimit(address indexed from, int24 tick, uint128 buyShare, uint128 sellShare, uint128 token0Out, uint128 token1Out);

    function trade(uint256 amountIn, bool buyside, int24 stopTick) internal returns (uint256 amountRemain, uint256 amountOut, uint160 sqrtPriceX96){
        // bytes4(keccak256(bytes('trade(uint256,bool,int24)')));
        (bool success,bytes memory result) = tradeCore.delegatecall(abi.encodeWithSelector(0x571a4c72, amountIn, buyside, stopTick));
        require(success, string (result));
        return abi.decode(result, (uint256,uint256,uint160));
    }

    //transfer output from dealt limit orders after exploition of the tick
    function claimDealtLimitPosition(address user, int24 tick, bool isSellShare, address to) internal {
        //assume that the tick is unexploited
        //must be called axfter unexploiting tick
        UserPosition memory _position = userPosition[isSellShare?1:0][user][tick];
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        if (_position.tokenOriginalInput > 0) {
            if (!isSellShare) {  //!zeroForToken1, buy -> token1, bought -> token0
                uint256 amountOut = amount1ToAmount0(_position.tokenOriginalInput, sqrtPriceX96);
                Tick[tick].bought = uint256(Tick[tick].bought).sub(amountOut).toUint128();
                TransferHelper.safeTransfer(token0, to, amountOut);
            } else {    //zeroForToken1, sell -> token0, sold -> token1
                uint256 amountOut = amount0ToAmount1(_position.tokenOriginalInput, sqrtPriceX96);
                Tick[tick].sold = uint256(Tick[tick].sold).sub(amountOut).toUint128();
                TransferHelper.safeTransfer(token1, to, amountOut);
            }
            delete userPosition[isSellShare?1:0][user][tick];
        }
    }

    //zeroForToken1 a.k.a buyside
    //buyside is for the taker, buyside = 1 -> add sell deep with token0, vice visa
    function putLimitOrder(int24 tick, uint256 amount, bool zeroForToken1) lock external returns (uint256 share){
        require(currentSqrtPriceX96 > 0);
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        updateDeep(tick, Tick[tick], sqrtPriceX96, 0, 0);
        //check input
        amount.toUint128();//prevent overflow
        if (zeroForToken1) {
            //token0 as input -> sell deep
            if(lastBalance0.add(amount) > balance0()){
                TransferHelper.safeTransferFrom(token0, msg.sender, address(this), amount);
            }
        } else {
            //token1 as input -> buy deep
            if(lastBalance1.add(amount) > balance1()){
                TransferHelper.safeTransferFrom(token1, msg.sender, address(this), amount);
            }
        }
        address sender = msg.sender;
        uint256 autoSwaped;
        assembly { autoSwaped := extcodesize(sender) } //reuse autoSwaped for size to lower stack depth
        if(autoSwaped > 0){
            sender = ILimitswapCaller(sender).sender();
        }
        autoSwaped = 0;//end of reusing
        uint256 originAmount = amount;
        if ((zeroForToken1 && (tick < currentTick())) || (!zeroForToken1 && (tick > currentTick()))){
            //sell with price lower than current price or buy with price higher than current price
            //try to move to the current tick via swap
            (amount, autoSwaped, ) = trade(amount, !zeroForToken1, tick);
        }
        if (amount > 0) {
            uint256 deepBurned;
            uint256 deepPriced;
            tickDeep memory tickInfo = Tick[tick]; //cached for gas saving
            if (zeroForToken1){
                //new sell deep with amount0 = amount
                //first try to take limit buy order at tick
                if(!isExploited(tick, 1) && tickInfo.buy > 0){
                    deepBurned = Math.min(tickInfo.buy, amount0ToAmount1(amount, sqrtPriceX96)); //in token1
                    deepPriced = amount1ToAmount0(deepBurned, sqrtPriceX96);
                    tickInfo.buy -= deepBurned.toUint128();
                    tickInfo.bought += deepPriced.toUint128();
                    amount = amount.sub(deepBurned);
                    if (amount > 0) amount --; //rounding down
                    autoSwaped = autoSwaped.add(deepBurned); //in token1
                }
                //open limit sell deep at tick with amount
                tickInfo.sell += amount.toUint128();
                //update deep, limit0 up, limit1 down
                updateDeep(tick, tickInfo, sqrtPriceX96, amount.toInt256(), -deepBurned.toInt256());
            } else {
                //new buy deep with amount1 = amount
                //first try to take limit sell order at tick
                if(!isExploited(tick, 0) && tickInfo.sell > 0){
                    deepBurned = Math.min(tickInfo.sell, amount1ToAmount0(amount, sqrtPriceX96)); //in token0
                    deepPriced = amount0ToAmount1(deepBurned, sqrtPriceX96);
                    tickInfo.sell -= deepBurned.toUint128();
                    tickInfo.sold += deepPriced.toUint128();
                    amount = amount.sub(deepBurned);
                    if (amount > 0) amount --; //rounding down
                    autoSwaped = autoSwaped.add(deepBurned); //in token0
                }
                //open limit buy deep at tick with amount
                tickInfo.buy += amount.toUint128();
                //update deep, limit0 down, limit1 up
                updateDeep(tick, tickInfo, sqrtPriceX96, -deepBurned.toInt256(), amount.toInt256());
            }
            //calculate share
            //updateDeep() will make sure tick is not exploited
            //tickPosition has been cleared
            //delta_sellShare = token1In / sell_old * totalSellShare_old, where sell_old = sell_new + token1In
            if (tickPosition[zeroForToken1?1:0][tick].totalShare == 0) {
                share = 1e9;
            } else {
                require(uint256(tickInfo.sell)!=amount,'DIVERROR');
                share = FullMath.mulDiv(
                        amount,
                        tickPosition[zeroForToken1?1:0][tick].totalShare,
                        uint256(tickInfo.sell).sub(amount)
                    );
            }
            tickPosition[zeroForToken1?1:0][tick].totalShare=tickPosition[zeroForToken1?1:0][tick].totalShare.add(share);
            if (tickPosition[zeroForToken1?1:0][tick].clearanceCount > userPosition[zeroForToken1?1:0][sender][tick].lastEntry){
                //user share has been cleared
                //transfer to msg.sender for further process
                claimDealtLimitPosition(sender, tick, zeroForToken1, msg.sender);
                delete userPosition[zeroForToken1?1:0][sender][tick];
            }
            //add share to user position
            userPosition[zeroForToken1?1:0][sender][tick].userShare = userPosition[zeroForToken1?1:0][sender][tick].userShare.add(share);
            userPosition[zeroForToken1?1:0][sender][tick].tokenOutputWriteOff = FullMath.mulDiv(tickPosition[zeroForToken1?1:0][tick].dealtPerShareX96,
                amount, 1<<96);
            userPosition[zeroForToken1?1:0][sender][tick].tokenOriginalInput = userPosition[zeroForToken1?1:0][sender][tick].tokenOriginalInput.add(amount);
            userPosition[zeroForToken1?1:0][sender][tick].lastEntry = tickPosition[zeroForToken1?1:0][tick].clearanceCount;
        }
        if (autoSwaped > 0) {
            //send autoSwaped to user
            uint256 token0Out = zeroForToken1 ? 0 : autoSwaped;
            uint256 token1Out = zeroForToken1 ? autoSwaped : 0;
            //transfer asset
            //transfer to msg.sender for further process
            (uint256 fee0, uint256 fee1) = transferTokens(msg.sender, token0Out, token1Out, true);
            //distribute fee0, fee1
            _reward(fee0, fee1);
            //produce log
            emit Swap(sender,
                    zeroForToken1?(originAmount-amount).toUint128():0,
                    zeroForToken1?0:(originAmount-amount).toUint128(),
                    (token0Out-fee0).toUint128(),
                    (token1Out-fee1).toUint128(),
                    currentSqrtPriceX96
                    );
        }
        //produce log
        emit PutLimit(sender,
                tick,
                zeroForToken1?0:share.toUint128(),
                zeroForToken1?share.toUint128():0,
                zeroForToken1?amount.toUint128():0,
                zeroForToken1?0:amount.toUint128()
                );
        //update balance tracers
        lastBalance0 = balance0();
        lastBalance1 = balance1();
    }

    function cancelLimitOrder(int24 tick, uint256 share, bool isSellShare) lock external returns (uint256 token0Out, uint256 token1Out){
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        //handle with exploiting
        updateDeep(tick, Tick[tick], sqrtPriceX96, 0, 0);
        tickDeep memory tickInfo = Tick[tick];
        address sender = msg.sender;
        uint256 size;
        assembly { size := extcodesize(sender) }
        if(size > 0){
            sender = ILimitswapCaller(sender).sender();
        }
        //get outputs
        (token0Out, token1Out) = getLimitTokens(tick, sender, share, isSellShare);
        //check input
        UserPosition memory _position = userPosition[isSellShare?1:0][sender][tick];
        share = Math.min(share, _position.userShare);
        if (_position.userShare == 0) return (0,0);
        uint256 newShare = _position.userShare.sub(share);
        _position.tokenOriginalInput = FullMath.mulDiv(newShare, _position.tokenOriginalInput, _position.userShare);
        _position.tokenOutputWriteOff = FullMath.mulDiv(newShare, _position.tokenOutputWriteOff, _position.userShare);
        _position.userShare = newShare;  //update userShare here will cause reverting. WHY???
        userPosition[isSellShare?1:0][sender][tick] = _position;
        if (isSellShare) {
            tickInfo.sell -= token0Out.toUint128();
            tickInfo.sold -= token1Out.toUint128();
            updateDeep(tick, tickInfo, sqrtPriceX96, -token0Out.toInt256(), 0);
        } else {
            tickInfo.bought -= token0Out.toUint128();
            tickInfo.buy -= token1Out.toUint128();
            updateDeep(tick, tickInfo, sqrtPriceX96, 0, -token1Out.toInt256());
        }
        if (isSellShare && token1Out >0){
            _reward(0, token1Out.mul(3).div(1000));
            token1Out = token1Out.sub(token1Out.mul(3).div(1000));
        }
        if (!isSellShare && token0Out >0){
            _reward(token0Out.mul(3).div(1000), 0);
            token0Out = token0Out.sub(token0Out.mul(3).div(1000));
        }
        //no fee will be charged to cancel limit orders
        //transfer to msg.sender for further process
        transferTokens(msg.sender, token0Out, token1Out, false);
        //produce log
        emit CancelLimit(sender,
                tick,
                isSellShare?0:share.toUint128(),
                isSellShare?share.toUint128():0,
                token0Out.toUint128(),
                token1Out.toUint128()
                );
        //update balance tracers
        lastBalance0 = balance0();
        lastBalance1 = balance1();
    }

    function buyShare(address user, int24 tick) public view returns(uint256 share) {
        share = userPosition[0][user][tick].userShare;
    }

    function sellShare(address user, int24 tick) public view returns(uint256 share) {
        share = userPosition[1][user][tick].userShare;
    }

    function getLimitTokens (int24 tick, address user, uint256 share, bool isSellShare) public view returns(uint256, uint256) {
        (, bytes memory data) = address(this).staticcall(
        //(, bytes memory data) = address(tradeCore).delegatecall(
            abi.encodeWithSelector(
                ILimitswapTradeCore(tradeCore).getLimitTokensCode.selector,
                tick,
                user,
                share,
                isSellShare
            ));
        return abi.decode(data, (uint256,uint256));
    }

    function getDeep (int24 tick) public view returns(uint256 token0Deep, uint256 token1Deep)  {
        if (!isExploited(tick, 0)) token0Deep =  Tick[tick].sell;
        if (!isExploited(tick, 1)) token1Deep =  Tick[tick].buy;
    }


    function swap(uint256 amountIn, bool zeroForToken0, address to) lock external returns (uint256 amountOut, uint160 toSqrtPriceX96){
        require(currentSqrtPriceX96 > 0);
        amountIn.toUint128();//prevent overflow
        //check input
        if (zeroForToken0) {
            //token1 as input
            require(lastBalance1.add(amountIn) <= balance1());
        } else {
            //token0 as input
            require(lastBalance0.add(amountIn) <= balance0());
        }
        //trade until amountIn -> 0
        (, amountOut, toSqrtPriceX96) = trade(amountIn, zeroForToken0, zeroForToken0 ? int24(8388607) : int24(-8388607));
        uint256 token0Out = zeroForToken0 ? amountOut : 0;
        uint256 token1Out = zeroForToken0 ? 0 : amountOut;
        //transfer asset
        (uint256 fee0, uint256 fee1) = transferTokens(to, token0Out, token1Out, true);
        //distribute fee0, fee1
        _reward(fee0, fee1);
        //produce log
        emit Swap(msg.sender,
            zeroForToken0?0:amountIn.toUint128(),
            zeroForToken0?amountIn.toUint128():0,
            (token0Out-fee0).toUint128(),
            (token1Out-fee1).toUint128(),
            currentSqrtPriceX96
            );
        amountOut = fee0 > 0 ? amountOut - fee0 : amountOut - fee1;
        //update balance tracers
        lastBalance0 = balance0();
        lastBalance1 = balance1();
    }

    function flashLoan(address recipient, uint256 amount0, uint256 amount1, bytes calldata data) lock external{
        uint256 fee0 = FullMath.mulDivRoundingUp(amount0, 3, 1000);//0.3 % fee
        uint256 fee1 = FullMath.mulDivRoundingUp(amount1, 3, 1000);//0.3 % fee
        uint256 balance0Before = balance0();
        uint256 balance1Before = balance1();
        require(!ILimitswapGate(gate).addressBlockedFromFlashLoan(msg.sender));
        if(amount0 > 0) {
            require(!ILimitswapGate(gate).tokenBlockedFromFlashLoan(token0));
            TransferHelper.safeTransfer(token0, recipient, amount0);
        }
        if(amount1 > 0) {
            require(!ILimitswapGate(gate).tokenBlockedFromFlashLoan(token1));
            TransferHelper.safeTransfer(token1, recipient, amount1);
        }

        ILimitswapFlashLoanCallback(msg.sender).flashLoanCallback(fee0, fee1, data);

        uint256 balance0After = balance0();
        uint256 balance1After = balance1();

        require(balance0Before.add(fee0) <= balance0After);
        require(balance1Before.add(fee1) <= balance1After);

        _reward(balance0After.sub(balance0Before), balance1After.sub(balance1Before));

        //update balance tracers
        lastBalance0 = balance0();
        lastBalance1 = balance1();
    }

    function estOutput(uint256 amountIn, bool zeroForToken0) public view returns (uint256, uint256, uint160){
        (bool success, bytes memory data) = address(this).staticcall(
            abi.encodeWithSelector(
                ILimitswapTradeCore(tradeCore).tradeStartGate.selector,
                amountIn,
                zeroForToken0,
                zeroForToken0 ? int24(8388607) : int24(-8388607)
            ));
        assembly {
            switch success
                // delegatecall returns 0 on error.
                case 0 { revert(add(data, 32), returndatasize()) }
                default { return(add(data, 32), returndatasize()) }
        }
    }

    fallback () external {
        require(msg.sender == address(this));

        (bool success, bytes memory data) = address(ILimitswapTradeCore(tradeCore)).delegatecall(msg.data);
        assembly {
            switch success
                // delegatecall returns 0 on error.
                case 0 { revert(add(data, 32), returndatasize()) }
                default { return(add(data, 32), returndatasize()) }
        }
    }


}
