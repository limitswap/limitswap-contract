// SPDX-License-Identifier: GPL-2.0
pragma solidity =0.7.6;

interface ILimitswapMine {
    function poolInfo(uint256 _pid) external view returns (address depositToken, uint256 allocPoint, uint256 lastRewardBlock, uint256 accMinedPerShare);
    function poolLength() external view returns (uint256);
    function minedPerBlock() external view returns (uint256);
    function depositedAmount(uint256 _pid, address _user) external view returns (uint256 _deposited);
    function pendingAmount(uint256 _pid, address _user) external view returns (uint256 _pending);
    function claim(uint256 _pid) external;
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function emergencyWithdraw(uint256 _pid) external;
    function updatePool(uint256 _pid) external;
    function massUpdatePools() external;
}
