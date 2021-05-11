// SPDX-License-Identifier: GPL 2.0
pragma solidity =0.7.6;

interface ILimitswapGate {
    function addressBlockedFromFlashLoan(address _from) external view returns (bool);
    function tokenBlockedFromFlashLoan(address _token) external view returns (bool);
    function feeCollector() external view returns(address);
}
