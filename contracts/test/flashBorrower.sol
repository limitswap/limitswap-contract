// SPDX-License-Identifier: GPL 2.0
pragma solidity =0.7.6;

import '../interfaces/IERC20.sol';
import '../interfaces/ILimitswapPair.sol';
import '../interfaces/ILimitswapFlashLoanCallback.sol';

import './testCoin.sol';

contract flashBorrower is ILimitswapFlashLoanCallback {
    address testCoin0;
    address testCoin1;
    
    constructor(address _testCoinA, address _testCoinB) {
        testCoin0 = _testCoinA < _testCoinB ? _testCoinA : _testCoinB;
        testCoin1 = _testCoinA < _testCoinB ? _testCoinB : _testCoinA;
    }

    function flashLoanCallback(uint256 fee0, uint256 fee1, bytes calldata data) external override {
        data;
        TestCoin(testCoin0).mint(msg.sender, fee0);
        TestCoin(testCoin1).mint(msg.sender, fee1);
        TestCoin(testCoin0).transfer(msg.sender, TestCoin(testCoin0).balanceOf(address(this)));
        TestCoin(testCoin1).transfer(msg.sender, TestCoin(testCoin1).balanceOf(address(this)));
    }

    function testFlashLoan (address pair, uint256 amount0, uint256 amount1) public {
        require(ILimitswapPair(pair).token0() == testCoin0);
        require(ILimitswapPair(pair).token1() == testCoin1);
        bytes memory b = new bytes(200);
        ILimitswapPair(pair).flashLoan(address(this), amount0, amount1, b);
    }
    
}
