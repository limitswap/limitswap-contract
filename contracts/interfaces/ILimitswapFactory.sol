// SPDX-License-Identifier: GPL 2.0
pragma solidity =0.7.6;

interface ILimitswapFactory {
    function getPair(address, address) external view returns (address);
    function createPair(address, address) external returns(address);
    function allPairs(uint) external view returns(address);
    function allPairsLength() external view returns (uint);
}
