// SPDX-License-Identifier: GPL-2.0
pragma solidity =0.7.6;

import './interfaces/IERC20.sol';
import './libraries/Math.sol';
import './libraries/TickMath.sol';
import './libraries/TickBitmap.sol';
import './libraries/SafeCast.sol';
import './libraries/SafeMath.sol';
import './libraries/FullMath.sol';
import './libraries/SqrtPriceMath.sol';
import './libraries/TransferHelper.sol';
import './LimitswapStorage.sol';

contract LimitswapTradeCore is LimitswapStorage{
    using SafeMath for uint256;
    using SafeCast for uint256;
    using TickBitmap for mapping(int16 => uint256);

    function amount0ToAmount1(uint256 amount0, uint160 sqrtPriceX96) public pure returns (uint256 amount1){
        if (sqrtPriceX96 == 0 || amount0 == 0) return 0;
        amount1 = (((amount0.mul(uint256(sqrtPriceX96)))>>96).mul(uint256(sqrtPriceX96)))>>96;
        if (amount1 > 0) amount1--;
    }

    function amount1ToAmount0(uint256 amount1, uint160 sqrtPriceX96) public pure returns (uint256 amount0){
        if (sqrtPriceX96 == 0 || amount1 == 0) return 0;
        amount0 = FullMath.mulDiv(FullMath.mulDiv(amount1, 1<<96, sqrtPriceX96),1<<96,sqrtPriceX96);
    }

    function getLimitTokensCode (int24 tick, address user, uint256 share, bool isSellShare) public view returns(uint256 token0Out, uint256 token1Out) {
        UserPosition memory _position = userPosition[isSellShare?1:0][user][tick];
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        uint256 amountOut;
        uint256 amountIn;
        if (isExploited(tick, isSellShare?0:1) || tickPosition[isSellShare?1:0][tick].clearanceCount > _position.lastEntry) {
            //has been totally sold
            amountOut = isSellShare ?
                amount0ToAmount1(_position.tokenOriginalInput, sqrtPriceX96) :
                amount1ToAmount0(_position.tokenOriginalInput, sqrtPriceX96);
        } else {
            amountOut = FullMath.mulDiv(_position.userShare, tickPosition[isSellShare?1:0][tick].dealtPerShareX96, 1<<96);
            amountOut = amountOut > _position.tokenOutputWriteOff ? amountOut.sub(_position.tokenOutputWriteOff) : 0;
            amountIn = _position.tokenOriginalInput.sub(
                    isSellShare ? amount1ToAmount0(amountOut, sqrtPriceX96) : amount0ToAmount1(amountOut, sqrtPriceX96)
                );
        }
        share = Math.min(share, _position.userShare);
        if (_position.userShare == 0) return (0, 0);
        amountIn  = FullMath.mulDiv(share, amountIn,  _position.userShare);
        amountOut = FullMath.mulDiv(share, amountOut, _position.userShare);
        (token0Out, token1Out) = isSellShare ? (amountIn, amountOut) : (amountOut, amountIn);
    }

    function isExploitedGate (int24 tick, uint buyside) public view returns(bool) {
        return isExploited(tick, buyside);
    }

    function isExploited (int24 tick, uint buyside) internal view returns(bool) {
        (int8 wordHigh, uint8 wordLow, int16 word, uint8 posInWord) = TickMath.resolvePos(tick);
        if (TickMath.getBit(wordHighExploited[buyside], wordHighMap(wordHigh))) return true;
        else if (TickMath.getBit(wordLowExploited[buyside][wordHigh], wordLow)) return true;
        else if (TickMath.getBit(tickExploited[buyside][word], posInWord)) return true;
        else return false;
    }

    function wordHighMap(int8 wordHigh) internal pure returns (uint8 wordHighPos){
        wordHighPos = uint8(int256(wordHigh) + 127);
    }

    function tradeToTick (StepState memory stepState)
         internal view returns(bool success, uint256 amountOut, uint256 curveDeep)  {
        uint160 nextSqrtPriceX96 = TickMath.getSqrtRatioAtTick(stepState.nextTick); //to save gas
        //buyside = 1 -> curveDeep in Y
        curveDeep = stepState.buyside?SqrtPriceMath.getAmount1Delta(stepState.sqrtPriceX96, nextSqrtPriceX96, liquidity.toUint128(), true):SqrtPriceMath.getAmount0Delta(stepState.sqrtPriceX96, nextSqrtPriceX96, liquidity.toUint128(), true);
        if (stepState.amountIn > stepState.limitDeepPriced + curveDeep) {
            stepState.amountIn = stepState.amountIn - (stepState.limitDeepPriced + curveDeep);
            //buyside = 1 -> curveOut in X, limitDeep in X
            uint256 curveOut = stepState.buyside?SqrtPriceMath.getAmount0Delta(stepState.sqrtPriceX96, nextSqrtPriceX96, liquidity.toUint128(), false):SqrtPriceMath.getAmount1Delta(stepState.sqrtPriceX96, nextSqrtPriceX96, liquidity.toUint128(), false);
            amountOut = curveOut + stepState.limitDeep;
            success = true;
        }
    }

    function tradeAllRemainingByCurve (FinderState memory finderState) internal view returns(FinderState memory)  {
        uint160 sqrtPriceX96 = finderState.sqrtPriceX96;
        finderState.sqrtPriceX96 = SqrtPriceMath.getNextSqrtPriceFromInput(finderState.sqrtPriceX96, liquidity.toUint128(),
             finderState.amountIn, !finderState.buyside);
        finderState.curTick = TickMath.getTickAtSqrtRatio(finderState.sqrtPriceX96);
        if (finderState.stopTick != 8388607 && finderState.stopTick != -8388607) {
            if ((finderState.buyside && finderState.curTick > finderState.stopTick) || (!finderState.buyside && finderState.curTick < finderState.stopTick)) {
                finderState.sqrtPriceX96 = TickMath.getSqrtRatioAtTick(finderState.stopTick);
                finderState.amountIn -= finderState.buyside?SqrtPriceMath.getAmount1Delta(sqrtPriceX96, finderState.sqrtPriceX96,
             liquidity.toUint128(), true):SqrtPriceMath.getAmount0Delta(sqrtPriceX96, finderState.sqrtPriceX96,
              liquidity.toUint128(), true);
                finderState.curTick = finderState.stopTick;
            } else {
                finderState.amountIn = 0;
            }
        } else {
            finderState.amountIn = 0;
        }
        finderState.amountOut += finderState.buyside?SqrtPriceMath.getAmount0Delta(sqrtPriceX96, finderState.sqrtPriceX96,
             liquidity.toUint128(), false):SqrtPriceMath.getAmount1Delta(sqrtPriceX96, finderState.sqrtPriceX96,
              liquidity.toUint128(), false);
        return finderState;
    }

    function findNextWordHigh (FinderState memory finderState) internal view returns(FinderState memory, bool)   {
            //make sure price is exactly at curTick
            //make sure curTick is the end tick in the end word in wordLow
            //make sure curTick has no avaible deep
            //when returns toTick may have deep
        if (finderState.stopTick == finderState.curTick) return (finderState, false);
        (int8 wordHigh, , , ) = TickMath.resolvePos(finderState.curTick);
        if (((wordHigh + 1 >= MAX_WORDHIGH) && finderState.buyside) || ((wordHigh - 1 <= MIN_WORDHIGH) && !finderState.buyside)) {
            //there will never be initalized tick beyond MAX_WORGHIGH
            //getTickAtSqrtRatio will check that toSqrtPriceX96 will not exceed [-MIN_SQRT_RATIO, MAX_SQRT_RATIO)
            // outputState = tradeAllRemainingByCurve(finderState);
            // outputState.amountIn = 0;
            // outputState.curTick = TickMath.getTickAtSqrtRatio(outputState.sqrtPriceX96);
            // return outputState;
            //UPDATE: word high NOT allowed to excceed MAX_WORDHIGH & MIN_WORDHIGH
            //IN order to prevent overflow
            finderState.amountIn = 0;
            return (finderState, false);
        }else{
            int24 nextTick = finderState.buyside? (TickMath.nextWordHigh(finderState.curTick, finderState.buyside) + 16383) : (TickMath.nextWordHigh(finderState.curTick, finderState.buyside) - 16383);
            int8 nextWordHigh = finderState.buyside? (wordHigh+1) : (wordHigh-1);
            uint256 limitDeep = TickMath.getBit(wordHighExploited[finderState.buyside?1:0], wordHighMap(nextWordHigh))?0:DeepWordHigh[finderState.buyside?0:1][nextWordHigh];
            uint256 deepPriced = uint128(limitDeep);
            limitDeep = limitDeep >> 128;
            //uint256 deepPriced = TickMath.getBit(wordHighExploited[finderState.buyside?1:0], wordHighMap(nextWordHigh))?0:DeepWordHighPriced[finderState.buyside?0:1][nextWordHigh];
            (bool success, uint256 output, uint256 curveDeep) = tradeToTick(StepState(finderState.amountIn, 0, finderState.sqrtPriceX96, nextTick, limitDeep, deepPriced, finderState.buyside));
            if (success && (finderState.buyside? finderState.stopTick >= nextTick : finderState.stopTick <= nextTick)) {
                    //cross the entire wordhigh
                    //when buyside = 1, limitDeep in X, deepPriced in Y, deepBurned in Y, amountIn in Y, curveDeep in Y, output in X
                    //when buyside = 0, limitDeep in Y, deepPriced in X, deepBurned in X, amountIn in X, curveDeep in X, output in Y
                    finderState.amountIn -= (deepPriced + curveDeep);
                    finderState.amountOut += output;
                    finderState.deepBurned += deepPriced;
                    finderState.sqrtPriceX96 = TickMath.getSqrtRatioAtTick(nextTick);
                    finderState.curTick = nextTick;
                    return (finderState, true);
            }else{
                //target price is at the next wordhigh
                //try to move to the start tick of start word in the next wordhigh
                nextTick = TickMath.nextWordHigh(finderState.curTick, finderState.buyside);
                (success, output, curveDeep) = tradeToTick(StepState(finderState.amountIn, 0, finderState.sqrtPriceX96, nextTick, 0, 0, finderState.buyside));
                if (success && (limitDeep > 0)){
                        finderState.amountIn -= curveDeep;
                        finderState.amountOut += output;
                        finderState.sqrtPriceX96 = TickMath.getSqrtRatioAtTick(nextTick);
                        finderState.curTick = nextTick;
                        return (finderState, false);
                    } else {
                        finderState = tradeAllRemainingByCurve(finderState);
                        return (finderState, false);
                    }
            }
        }
    }
    //bool continue
    function findNextWordLow (FinderState memory finderState)  internal view returns(FinderState memory, bool)   {
            //make sure price is exactly at curTick
            //make sure curTick is the end tick in word
            //make sure curTick has no avaible deep
            //when returns toTick may have deep
        if (finderState.stopTick == finderState.curTick) return (finderState, false);
        if (finderState.amountIn == 0) return (finderState, false);
        (int8 wordHigh, uint8 wordLow, int16 word, ) = TickMath.resolvePos(finderState.curTick);
        if ((finderState.buyside && wordLow == 63) || (!finderState.buyside && wordLow ==0)){
            //at end of wordLow
            bool toContinue = true;
            while (toContinue) {
                (finderState, toContinue) = findNextWordHigh(finderState);
            }
            return (finderState, true);
        }else{
            //find next wordLow within the wordHigh
            //try to move to the leftmost tick of the next word
            wordLow = finderState.buyside? (wordLow+1) : (wordLow-1);
            word = finderState.buyside? (word+1) : (word-1);
            int24 nextTick = finderState.buyside? (TickMath.nextWordLow(finderState.curTick, finderState.buyside) + 255) : (TickMath.nextWordLow(finderState.curTick, finderState.buyside) - 255);
            uint256 limitDeep = TickMath.getBit(wordLowExploited[finderState.buyside?1:0][wordHigh], wordLow)?0:DeepWordLow[finderState.buyside?0:1][word];
            uint256 deepPriced = uint128(limitDeep);
            limitDeep = limitDeep >> 128;
            //uint256 deepPriced = TickMath.getBit(wordLowExploited[finderState.buyside?1:0][wordHigh], nextWordLow)?0:DeepWordLowPriced[finderState.buyside?0:1][nextWord];
            (bool success, uint256 output, uint256 curveDeep) = tradeToTick(StepState(finderState.amountIn, 0, finderState.sqrtPriceX96, nextTick, limitDeep, deepPriced, finderState.buyside));
            if (success && (finderState.buyside? finderState.stopTick >= nextTick : finderState.stopTick <= nextTick)) {
                //cross the entire wordlow
                //when buyside = 1, limitDeep in X, deepPriced in Y, deepBurned in Y, amountIn in Y, curveDeep in Y, output in X
                //when buyside = 0, limitDeep in Y, deepPriced in X, deepBurned in X, amountIn in X, curveDeep in X, output in Y
                TickMath.getBit(wordLowExploited[finderState.buyside?1:0][wordHigh], wordLow);
                finderState.amountIn -= (deepPriced + curveDeep);
                finderState.amountOut += output;
                finderState.deepBurned += deepPriced;
                finderState.sqrtPriceX96 = TickMath.getSqrtRatioAtTick(nextTick);
                finderState.curTick = nextTick;
                return (finderState, true);
            } else {
                //target price is at the next word
                //try to move to the start tick in the next word
                nextTick = TickMath.nextWordLow(finderState.curTick, finderState.buyside);
                (success, output, curveDeep) = tradeToTick(StepState(finderState.amountIn, 0, finderState.sqrtPriceX96, nextTick, 0, 0, finderState.buyside));
                if (success && (limitDeep > 0)){
                    finderState.amountIn -= curveDeep;
                    finderState.amountOut += output;
                    finderState.sqrtPriceX96 = TickMath.getSqrtRatioAtTick(nextTick);
                    finderState.curTick = nextTick;
                    return (finderState, false);
                } else {
                    finderState = tradeAllRemainingByCurve(finderState);
                    return (finderState, false);
                }
            }
        }
    }

    function tradeInWord (FinderState memory finderState) internal view returns(FinderState memory, tickDeep memory)  {
            //make sure price is exactly at curTick
        uint256 amountIn = finderState.amountIn;
        if (finderState.stopTick == finderState.curTick) return (finderState, Tick[finderState.curTick]);
        if (finderState.amountIn == 0) return (finderState, Tick[finderState.curTick]);
        //first try to use deep at curTick
        if (!isExploited(finderState.curTick, finderState.buyside?1:0)){
            //returned tickInfo may be fakeTick, but it will never be the final return value of this func since amountIn always > 0
            tickDeep memory tickInfo;
            (finderState, tickInfo) = tradeAtTick(finderState);
            //when buyside = 1, deepBurned in Y, amountIn in Y, amountOut in X
            //when buyside = 0, deepBurned in X, amountIn in X, amountOut in Y
            if (finderState.amountIn == 0){
                //all amount in (_amountIn) has been executed
                return (finderState, tickInfo);
                //remember to write tickInfo to Tick[curTick]
            } else {
                finderState.deepBurned += (amountIn - finderState.amountIn);
            }
        }
        if ((finderState.buyside && finderState.curTick % 256 == 255) || (!finderState.buyside && finderState.curTick % 256 == 0)){
            //at the leftmost or rightmost of the word
            bool toContinue = true;
            while (toContinue){
                (finderState, toContinue) = findNextWordLow(finderState);
            }
            return tradeInWord(finderState);
        }
        else {
            //search next tick within the word
            (int24 nextTick,) = tickBitmap.nextInitializedTickWithinOneWord(finderState.buyside?finderState.curTick:finderState.curTick-1, 1, !finderState.buyside);
            if ((finderState.buyside && nextTick > finderState.stopTick) || (!finderState.buyside && nextTick < finderState.stopTick)) {
                nextTick = finderState.stopTick;
            }
            (bool success, uint256 output, uint256 curveDeep)
                = tradeToTick(StepState(finderState.amountIn, 0, finderState.sqrtPriceX96, nextTick, 0, 0, finderState.buyside));
            if (success) {
                //move to next tick
                finderState.amountIn -= curveDeep;
                finderState.amountOut += output;
                finderState.sqrtPriceX96 = TickMath.getSqrtRatioAtTick(nextTick);
                finderState.curTick = nextTick;
                return tradeInWord(finderState);
            } else {
                finderState = tradeAllRemainingByCurve(finderState);
                finderState.amountIn = 0;
                finderState.curTick = TickMath.getTickAtSqrtRatio(finderState.sqrtPriceX96);
                return (finderState, Tick[nextTick]);
            }
        }
    }

    function tradeAtTick (FinderState memory finderState) internal view returns(FinderState memory, tickDeep memory)  {
        if (isExploited(finderState.curTick, finderState.buyside?1:0)) return (finderState, tickDeep(0,0,0,0));
        tickDeep memory tickInfo = Tick[finderState.curTick];
        if (finderState.buyside && tickInfo.sell > 0){
            uint256 amount0 = amount1ToAmount0(finderState.amountIn, finderState.sqrtPriceX96);
            if (tickInfo.sell >= amount0){
                tickInfo.sell -= amount0.toUint128();
                tickInfo.sold += finderState.amountIn.toUint128();
                finderState.amountIn = 0;
                finderState.amountOut = finderState.amountOut.add(amount0);
            } else {
                uint256 amount1 = amount0ToAmount1(tickInfo.sell, finderState.sqrtPriceX96);
                finderState.amountIn = finderState.amountIn.sub(amount1);
                if (finderState.amountIn > 0) finderState.amountIn --; //rounding down
                finderState.amountOut = finderState.amountOut.add(tickInfo.sell);
                tickInfo.sold += amount1.toUint128();
                tickInfo.sell = 0;
            }
        }else if (!finderState.buyside && tickInfo.buy > 0){
            if(amount1ToAmount0(tickInfo.buy, finderState.sqrtPriceX96) >= finderState.amountIn){
                uint256 amount1 = amount0ToAmount1(finderState.amountIn, finderState.sqrtPriceX96);
                tickInfo.buy -= amount1.toUint128();
                if (tickInfo.buy > 0) tickInfo.buy --; //rounding down
                tickInfo.bought += finderState.amountIn.toUint128();
                finderState.amountIn = 0;
                finderState.amountOut = finderState.amountOut.add(amount1);
            } else {
                uint256 amount0 = amount1ToAmount0(tickInfo.buy, finderState.sqrtPriceX96);
                finderState.amountIn = finderState.amountIn.sub(amount0);
                if (finderState.amountIn > 0) finderState.amountIn --; //rounding down
                finderState.amountOut = finderState.amountOut.add(tickInfo.buy);
                tickInfo.bought += amount0.toUint128();
                tickInfo.buy = 0;
            }
        }
        return (finderState, tickInfo);
    }

    function unExploitedTick (int24 tick, uint256 buyside) public {
        (int8 wordHigh, uint8 wordLow, int16 word, uint8 posInWord) = TickMath.resolvePos(tick);
        if (TickMath.getBit(wordHighExploited[buyside], wordHighMap(wordHigh))) {
            //entire wordHigh has been expolited
            wordHighExploited[buyside] = TickMath.setSingle(wordHighExploited[buyside], wordHighMap(wordHigh), false);
            wordLowExploited[buyside][wordHigh] = TickMath.setSingle(uint256(-1), wordLow, false);
            tickExploited[buyside][word] = TickMath.setSingle(uint256(-1), posInWord, false);
            DeepWordHigh[buyside][wordHigh] = 0;
            //DeepWordHighPriced[buyside][wordHigh] = 0;
        }
        else if (TickMath.getBit(wordLowExploited[buyside][wordHigh], wordLow)) {
            //entire word has been expolited
            wordLowExploited[buyside][wordHigh] = TickMath.setSingle(wordLowExploited[buyside][wordHigh], wordLow, false);
            tickExploited[buyside][word] = TickMath.setSingle(uint256(-1), posInWord, false);
            DeepWordHigh[buyside][wordHigh] -= DeepWordLow[buyside][word];
            //DeepWordHighPriced[buyside][wordHigh] -= DeepWordLowPriced[buyside][word];
            DeepWordLow[buyside][word] = 0;
            //DeepWordLowPriced[buyside][word] = 0;
        }
        else if (TickMath.getBit(tickExploited[buyside][word], posInWord)) {
            tickExploited[buyside][word] = TickMath.setSingle(tickExploited[buyside][word], posInWord, false);
            uint256 deepBurned = buyside>0 ?  Tick[tick].buy : Tick[tick].sell;
            uint256 deepPriced = buyside>0 ? amount1ToAmount0(deepBurned, TickMath.getSqrtRatioAtTick(tick)) : amount0ToAmount1(deepBurned, TickMath.getSqrtRatioAtTick(tick));
            DeepWordHigh[buyside][wordHigh] -= ((deepBurned<<128) + deepPriced);
            DeepWordLow[buyside][wordHigh] -= ((deepBurned<<128) + deepPriced);
            // DeepWordHigh[buyside][wordHigh] -= deepBurned;
            // DeepWordHighPriced[buyside][wordHigh] -= deepPriced;
            // DeepWordLow[buyside][word] -= deepBurned;
            // DeepWordLowPriced[buyside][word] -= deepPriced;
        }
    }
    //mark every tick between fromTick to toTick (including these two) to exploited
    function rangeExecLimitOrder (int24 fromTick, int24 toTick, uint buyside) internal {
        require (toTick >= fromTick);
        (int8 fromWordHigh, uint8 fromWordLow, int16 fromWord, uint8 fromPosInWord) = TickMath.resolvePos(fromTick);
        (int8 toWordHigh, uint8 toWordLow, , uint8 toPosInWord) = TickMath.resolvePos(toTick);
        if (toWordHigh > fromWordHigh) {
            rangeExecLimitOrder(fromTick, TickMath.nextWordHigh(fromTick, true) - 1, buyside);
            if (toWordHigh > fromWordHigh + 1) {
                wordHighExploited[buyside] = TickMath.setRange(wordHighExploited[buyside], wordHighMap(fromWordHigh + 1), wordHighMap(toWordHigh - 1), true);
            }
            rangeExecLimitOrder(TickMath.nextWordHigh(toTick, false) + 1, toTick, buyside);
        }
        else if (toWordLow > fromWordLow){
            rangeExecLimitOrder(fromTick, TickMath.nextWordLow(fromTick, true) - 1, buyside);
            if (toWordLow > fromWordLow + 1) {
                wordLowExploited[buyside][fromWordHigh] = TickMath.setRange(wordLowExploited[buyside][fromWordHigh], fromWordLow + 1, toWordLow - 1, true);
            }
            rangeExecLimitOrder(TickMath.nextWordLow(toTick, false) + 1, toTick, buyside);
        }
        else{
            //fromWordHigh==toWordHigh, fromWordLow==toWordLow
            tickExploited[buyside][fromWord] = TickMath.setRange(tickExploited[buyside][fromWord], fromPosInWord, toPosInWord, true);
        }
    }

    function reserve0() public view returns (uint256){
        return FullMath.mulDivRoundingUp(liquidity, 1<<96, currentSqrtPriceX96);
    }

    function reserve1() public view returns (uint256){
        return FullMath.mulDivRoundingUp(liquidity, currentSqrtPriceX96, 1<<96);
    }


    function tradeStartGate(uint256 amountIn, bool buyside, int24 stopTick) public view returns(uint256 amountOut, uint256 deepBurned, uint160 sqrtPriceX96){
        int24 fromTick = TickMath.getTickAtSqrtRatio(currentSqrtPriceX96);
        FinderState memory finderState;
        finderState.amountIn = amountIn;
        finderState.sqrtPriceX96 = currentSqrtPriceX96;
        finderState.buyside = buyside;
        finderState.stopTick = stopTick;
        finderState.curTick = fromTick;
        //finderState = tradeAllRemainingByCurve(finderState);
        (finderState, , )=tradeStart(finderState);
        return (finderState.amountOut.mul(997).div(1000), finderState.deepBurned, finderState.sqrtPriceX96);
    }

    function tradeStart(FinderState memory finderState) internal view returns (FinderState memory, tickDeep memory, bool){
        if(finderState.amountIn == 0) return (finderState, tickDeep(0,0,0,0), false);
        if (TickMath.getSqrtRatioAtTick(finderState.curTick) != finderState.sqrtPriceX96){
            //first try to move to the closet tick
            int24 nextTick = finderState.buyside ? finderState.curTick + 1 : finderState.curTick;
            (bool success, uint256 output, uint256 curveDeep)
                = tradeToTick(StepState(finderState.amountIn, 0, currentSqrtPriceX96, nextTick, 0, 0, finderState.buyside));
            if (success) {
                //move to next tick
                finderState.amountIn -= curveDeep;
                finderState.amountOut += output;
                finderState.sqrtPriceX96 = TickMath.getSqrtRatioAtTick(nextTick);
            } else {
                //still stuck at [fromTick, fromTick+1)
                finderState = tradeAllRemainingByCurve(finderState);
                finderState.amountIn = 0;
                return (finderState, tickDeep(0,0,0,0), false);
            }
        }
        tickDeep memory tickInfo;
        (finderState, tickInfo)=tradeInWord(finderState);
        return (finderState, tickInfo, true);
    }


    function trade(uint256 amountIn, bool buyside, int24 stopTick) public returns (uint256 amountRemain, uint256 amountOut, uint160 sqrtPriceX96){
        if(amountIn == 0) return (0, 0, currentSqrtPriceX96);
        int24 fromTick = TickMath.getTickAtSqrtRatio(currentSqrtPriceX96);
        sqrtPriceX96 = currentSqrtPriceX96;
        FinderState memory finderState;
        finderState.amountIn = amountIn;
        finderState.sqrtPriceX96 = currentSqrtPriceX96;
        finderState.buyside = buyside;
        finderState.stopTick = stopTick;
        finderState.curTick = fromTick;
        tickDeep memory tickInfo;
        bool deepNeedUpdated;
        (finderState, tickInfo, deepNeedUpdated)=tradeStart(finderState);
        //update deep of the final tick if price happen to stop at it.
        if(TickMath.getSqrtRatioAtTick(finderState.curTick) == finderState.sqrtPriceX96 && deepNeedUpdated){
            updateDeep(finderState.curTick, tickInfo, finderState.sqrtPriceX96, 0, 0);
        }
        //update exploit markers [fromTick, toTick)
        //not including toTick as price may stuck at toTick
        if (buyside){
            //toTick >= fromTick as price increases
            if (finderState.curTick > fromTick) rangeExecLimitOrder(fromTick, finderState.curTick - 1, 0);
        } else {
            //toTick <= fromTick as price decreases
            if (finderState.curTick < fromTick) rangeExecLimitOrder(finderState.curTick + 1, fromTick, 1);
        }
        //update global tracers
        currentSqrtPriceX96 = finderState.sqrtPriceX96;
        //when buyside = 1, deepBurned in Y, amountIn in Y, amountOut in X, for user: Y->X, for pool: Y up X down
        //when buyside = 0, deepBurned in X, amountIn in X, amountOut in Y, for user: X->Y, for pool: X up Y down
        amountOut = buyside ? SqrtPriceMath.getAmount0Delta(sqrtPriceX96, finderState.sqrtPriceX96, liquidity.toUint128(), true)
            : SqrtPriceMath.getAmount1Delta(sqrtPriceX96, finderState.sqrtPriceX96, liquidity.toUint128(), true); //output by curve
        //finderState.amountOut will always be less than amountOut due to serveral rounding down in the iteration
        if (finderState.amountOut > amountOut){
            amountOut = finderState.amountOut - amountOut;
            if (amountOut < tolerant) amountOut = 0;
        } else {
            if (finderState.amountOut + tolerant > amountOut){
                amountOut = 0;
            } else {
                revert('tolerant exceed');
            }
        }
        if (finderState.deepBurned > 0){
            if (buyside) {//buy token0 with token1 will burn sell deep marked by token0
                //update totalLimit0
                totalLimit = (totalLimit>>128).sub(amountOut) < tolerant ? uint128(totalLimit) : totalLimit.sub(amountOut << 128);
                //liquidity unchanged
            }else{//buy token0 for token1 will burn buy deep marked by token1
                //update totalLimit1
                totalLimit = uint256(uint128(totalLimit)).sub(amountOut) < tolerant ? (totalLimit>>128)<<128 : totalLimit.sub(amountOut.toUint128());
                //liquidity unchanged
            }
        }
        return (finderState.amountIn, finderState.amountOut, finderState.sqrtPriceX96);
    }
    //totalLimit0&1 is only used for display, so it may have a little tolerant for better look
    uint256 constant tolerant = 1000;

    function updateDeepGate (int24 tick, uint128 buy, uint128 bought, uint128 sell, uint128 sold, uint160 sqrtPriceX96, int256 newDeep0, int256 newDeep1) public {
        updateDeep(tick, tickDeep(buy, bought, sell, sold), sqrtPriceX96, newDeep0, newDeep1);
    }

    function clearTickPosition (int24 tick, uint256 isSellShare) private {
        tickPosition[isSellShare][tick].totalShare = 0;
        tickPosition[isSellShare][tick].dealtPerShareX96 = 0;
        tickPosition[isSellShare][tick].clearanceCount += 1;
    }

    function dealAtTickPosition (int24 tick, uint256 isSellShare, uint256 dealOutput) private {
        if (dealOutput > 0) {
            require(tickPosition[isSellShare][tick].totalShare > 0, 'DEEPERROR');
            tickPosition[isSellShare][tick].dealtPerShareX96 = tickPosition[isSellShare][tick].dealtPerShareX96.add(
                FullMath.mulDiv(dealOutput, 1<<96, tickPosition[isSellShare][tick].totalShare)
                );
        }
    }


    function updateDeep(int24 tick, tickDeep memory tickInfo, uint160 sqrtPriceX96, int256 newDeep0, int256 newDeep1) internal {
        (int8 wordHigh,, int16 word,) = TickMath.resolvePos(tick);
        //uint128+uint128 may overflow, check elsewhere
        if (isExploited(tick, 0)){//has been totally bought
            //set tickInfo
            tickInfo.sold += amount0ToAmount1(tickInfo.sell, sqrtPriceX96).toUint128();
            tickInfo.sell = 0;
            //set tickPosition
            clearTickPosition(tick, 1);
            //unExploitedTick
            unExploitedTick(tick, 0);
        }
        else if (Tick[tick].bought < tickInfo.bought){
            dealAtTickPosition(tick, 0, tickInfo.bought - Tick[tick].bought);
        }
        if (isExploited(tick, 1)){//has been totally sold
            //set tickInfo
            tickInfo.bought += amount1ToAmount0(tickInfo.buy, sqrtPriceX96).toUint128();
            tickInfo.buy = 0;
            //set tickPosition
            clearTickPosition(tick, 0);
            //unExploitedTick
            unExploitedTick(tick, 1);
        }
        else if (Tick[tick].sold < tickInfo.sold){
            dealAtTickPosition(tick, 1, tickInfo.sold - Tick[tick].sold);
        }
        Tick[tick] = tickInfo;
        uint buyside;
        uint256 totalLimitNew = totalLimit;
        if (newDeep1 > 0){
            uint256 newDeepPriced = amount1ToAmount0(uint256(newDeep1), sqrtPriceX96);
            if (newDeepPriced>0) newDeepPriced --;//rounding down
            buyside = 1;
            DeepWordHigh[buyside][wordHigh] += ((uint256(newDeep1) << 128) + newDeepPriced);
            DeepWordLow[buyside][word] += ((uint256(newDeep1) << 128) + newDeepPriced);
            totalLimitNew += uint256(newDeep1);
        }
        if (newDeep1 < 0){
            uint256 newDeepPriced = amount1ToAmount0(uint256(-newDeep1), sqrtPriceX96);
            if (newDeepPriced>0) newDeepPriced --;//rounding down
            buyside = 1;
            DeepWordHigh[buyside][wordHigh] -= ((uint256(-newDeep1) << 128) + newDeepPriced);
            DeepWordLow[buyside][word] -= ((uint256(-newDeep1) << 128) + newDeepPriced);
            totalLimitNew -= uint256(-newDeep1);
        }
        if (newDeep0 > 0){
            uint256 newDeepPriced = amount0ToAmount1(uint256(newDeep0), sqrtPriceX96);
            buyside = 0;
            DeepWordHigh[buyside][wordHigh] += ((uint256(newDeep0) << 128) + newDeepPriced);
            DeepWordLow[buyside][word] += ((uint256(newDeep0) << 128) + newDeepPriced);
            totalLimitNew += (uint256(newDeep0)<<128);
        }
        if (newDeep0 < 0){
            uint256 newDeepPriced = amount0ToAmount1(uint256(-newDeep0), sqrtPriceX96);
            buyside = 0;
            DeepWordHigh[buyside][wordHigh] -= ((uint256(-newDeep0) << 128) + newDeepPriced);
            DeepWordLow[buyside][word] -= ((uint256(-newDeep0) << 128) + newDeepPriced);
            totalLimitNew -= (uint256(-newDeep0)<<128);
        }
        if (totalLimitNew != totalLimit) totalLimit = totalLimitNew;
        if (tickInfo.buy == 0 && tickInfo.sell == 0){
            tickBitmap.setTick(tick, false);
        } else {
            tickBitmap.setTick(tick, true);
        }
    }

}
