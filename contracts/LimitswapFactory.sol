// SPDX-License-Identifier: GPL-2.0
pragma solidity >=0.5.0;

import './interfaces/ILimitswapPair.sol';
import './interfaces/ILimitswapGate.sol';
import './libraries/Ownable.sol';


contract MinialPair  {
    address public implementation;
    address public gate;

  constructor (address _implementation, address _gate) {
    implementation = _implementation;
    gate = _gate;
  }

  /**
  * @dev Fallback function allowing to perform a delegatecall to the given implementation.
  * This function will return whatever the implementation call returns
  */
  fallback () external {
    address _impl = implementation;
    require(_impl != address(0));

    assembly {
      let ptr := mload(0x40)
      calldatacopy(ptr, 0, calldatasize())
      let result := delegatecall(gas(), _impl, ptr, calldatasize(), 0, 0)
      let size := returndatasize()
      returndatacopy(ptr, 0, size)

      switch result
      case 0 { revert(ptr, size) }
      default { return(ptr, size) }
    }
  }
}

abstract contract LimitswapGate is ILimitswapGate, Ownable{
    
    address public override feeCollector;

    mapping (address => bool) public override addressBlockedFromFlashLoan;

    mapping (address => bool) public override tokenBlockedFromFlashLoan;

    function blockAddressFromFlashLoan (address _from, bool _block) public onlyOwner {
        addressBlockedFromFlashLoan[_from] = _block;
    }

    function blockTokenFromFlashLoan (address _token, bool _block) public onlyOwner {
        tokenBlockedFromFlashLoan[_token] = _block;
    }

    function setFeeCollector (address _collector) public onlyOwner {
        feeCollector = _collector;
    }
    
}

contract LimitswapFactory is LimitswapGate {
    mapping(address => mapping(address => address)) pairInfo;

    function getPair (address tokenA, address tokenB) public view returns(address pair) {
        pair = tokenA < tokenB ? pairInfo[tokenA][tokenB] : pairInfo[tokenB][tokenA];
    }
    

    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    address public LimitswapPairCode;

    constructor (address limitswapPairCode) {
        LimitswapPairCode = limitswapPairCode;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, 'Limitswap: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'Limitswap: ZERO_ADDRESS');
        require(pairInfo[token0][token1] == address(0), 'Limitswap: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(MinialPair).creationCode;
        bytecode = abi.encodePacked(bytecode, abi.encode(LimitswapPairCode, address(this)));
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        ILimitswapPair(pair).initTokenAddress(token0, token1);
        pairInfo[token0][token1] = pair;
        pairInfo[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }
}