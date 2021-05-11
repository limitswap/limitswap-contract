// SPDX-License-Identifier: GPL-2.0
pragma solidity >=0.5.0;

import './BitMath.sol';

/// @title Packed tick initialized state library
/// @notice Stores a packed mapping of tick index to its initialized state
/// @dev The mapping uses int16 for keys since ticks are represented as int24 and there are 256 (2^8) values per word.
library TickFinder {
    /// @notice Returns the next initialized tick contained in the same word (or adjacent word) as the tick that is either
    /// to the left (less than or equal to) or right (greater than) of the given tick
    /// @param bitmap The bitmap in which to compute the next initialized tick
    /// @param tick The starting tick
    /// @param lte Whether to search for the next initialized tick to the left (less than or equal to the starting tick)
    /// @return next The next initialized or uninitialized tick up to 256 ticks away from the current tick
    /// @return initialized Whether the next tick is initialized, as the function only searches within up to 256 ticks
    function nextInitializedTickWithinOneWord(
        uint256 bitmap,
        int24 tick,
        bool lte
    ) internal pure returns (int24 next, bool initialized) {
      
        if (lte) {
            uint8 bitPos = uint8(tick % 126);
            // all the 1s at or to the right of the current bitPos
            uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
            uint256 masked = bitmap & mask;

            // if there are no initialized ticks to the right of or at the current tick, return rightmost in the word
            initialized = masked != 0;
            // overflow/underflow is possible, but prevented externally by limiting tick
            next = initialized
                ? (tick - int24(bitPos - BitMath.mostSignificantBit(masked))) 
                : (tick - int24(bitPos)) ;
        } else {
            // start from the word of the next tick, since the current tick state doesn't matter
            uint8 bitPos = uint8((tick + 1) % 126);
            // all the 1s at or to the left of the bitPos
            uint256 mask = ~((1 << bitPos) - 1);
            uint256 masked = bitmap & mask;

            // if there are no initialized ticks to the left of the current tick, return leftmost in the word
            initialized = masked != 0;
            // overflow/underflow is possible, but prevented externally by limiting tick
            next = initialized
                ? (tick + 1 + int24(BitMath.leastSignificantBit(masked) - bitPos)) 
                : (tick + 1 + int24(type(uint8).max - bitPos)) ;
        }
    }

    function getBit (uint256 p, uint8 pos) internal pure returns (bool res)  {
        uint256 mask = 1 << pos;
        res = (p & mask) != 0;
    }
}
