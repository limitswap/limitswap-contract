// SPDX-License-Identifier: GPL 2.0
pragma solidity =0.7.6;

interface ILimitswapFlashLoanCallback {
    function flashLoanCallback(uint256 fee0, uint256 fee1, bytes calldata data) external;
}
