// SPDX-License-Identifier: GPL-2.0
pragma solidity =0.7.6;

import './interfaces/IERC20.sol';

import './libraries/SafeMath.sol';
import './libraries/Math.sol';
import './libraries/TransferHelper.sol';

import './LimitswapToken.sol';


//Famring pool of LimitSwap Token
//Copied and modified from sushi MasterChef
//https://github.com/sushiswap/sushiswap/blob/master/contracts/MasterChef.sol
//no migrate
contract LimitswapMine is Ownable {
    using SafeMath for uint256;
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of Limitswap tokens
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accMinedPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws tokens to a pool. Here's what happens:
        //   1. The pool's `accMinedPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }
    // Info of each pool.
    struct PoolInfo {
        IERC20 depositToken; // Address of token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. SUSHIs to distribute per block.
        uint256 lastRewardBlock; // Last block number that SUSHIs distribution occurs.
        uint256 accMinedPerShare; // Accumulated SUSHIs per share, times 1e12. See below.
    }
    // The LimitSwap TOKEN!
    LimitswapToken public limitswapToken;
    // Limitswap Token mined per block.
    uint256 public minedPerBlock;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when SUSHI mining starts.
    uint256 public startBlock;
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Claim(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    constructor(
        LimitswapToken _limitswapToken,
        uint256 _minedPerBlock,
        uint256 _startBlock
    ) {
        limitswapToken = _limitswapToken;
        minedPerBlock = _minedPerBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new token to the pool. Can only be called by the owner.
    // XXX DO NOT add the same token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IERC20 _depositToken,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock =
            block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                depositToken: _depositToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accMinedPerShare: 0
            })
        );
    }

    // Update the given pool's mining allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Update minedPerBlock which affecting all pools. Can only be called by the owner.
    function setMinedPerBlock(
        uint256 _minedPerBlock,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        minedPerBlock = _minedPerBlock;
    }


    // View function to see pending LimitSwap Tokens on frontend.
    function pendingAmount(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accMinedPerShare = pool.accMinedPerShare;
        uint256 totalDeposit = pool.depositToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && totalDeposit != 0) {
            uint256 minedAmount =
                (block.number.sub(pool.lastRewardBlock))
                    .mul(minedPerBlock)
                    .mul(pool.allocPoint)
                    .div(totalAllocPoint);
            accMinedPerShare = accMinedPerShare.add(
                minedAmount.mul(1e12).div(totalDeposit)
            );
        }
        return user.amount.mul(accMinedPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 totalDeposit = pool.depositToken.balanceOf(address(this));
        if (totalDeposit == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 minedAmount =
            (block.number.sub(pool.lastRewardBlock))
                .mul(minedPerBlock)
                .mul(pool.allocPoint)
                .div(totalAllocPoint);
        limitswapToken.mint(address(this), minedAmount);
        pool.accMinedPerShare = pool.accMinedPerShare.add(
            minedAmount.mul(1e12).div(totalDeposit)
        );
        pool.lastRewardBlock = block.number;
    }

    function _claim(uint256 _pid, address _user) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending =
                user.amount.mul(pool.accMinedPerShare).div(1e12).sub(
                    user.rewardDebt
                );
            safeTokenTransfer(_user, pending);
            emit Claim(_user, _pid, pending);
            //user.rewardDebt = user.rewardDebt.add(pending);
            //rewardDebt not update, should be updated elsewhere
        }
    }

    function depositedAmount(uint256 _pid, address _user) public view returns (uint256 amount) {
        amount = userInfo[_pid][_user].amount;
    }

    // Claim limitswap token.
    function claim(uint256 _pid) public {
        UserInfo storage user = userInfo[_pid][msg.sender];
        _claim(_pid, msg.sender);
        user.rewardDebt = user.amount.mul(poolInfo[_pid].accMinedPerShare).div(1e12);
    }

    // Deposit tokens to mine limitswap token.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        _claim(_pid, msg.sender);
        TransferHelper.safeTransferFrom(
            address(pool.depositToken),
            address(msg.sender),
            address(this),
            _amount
        );
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accMinedPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw tokens, claiming all the rewards
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        _claim(_pid, msg.sender);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accMinedPerShare).div(1e12);
        TransferHelper.safeTransfer(
            address(pool.depositToken),
            address(msg.sender),
            _amount
        );
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        TransferHelper.safeTransfer(
            address(pool.depositToken),
            address(msg.sender),
            user.amount
        );
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe limitswap token transfer function, just in case if rounding error causes pool to not have enough tokens.
    function safeTokenTransfer(address _to, uint256 _amount) internal {
        TransferHelper.safeTransfer(
            address(limitswapToken),
            _to,
            Math.min(_amount, limitswapToken.balanceOf(address(this)))
            );
    }
}
