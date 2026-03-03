// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title VarInt
 * @notice Library for encoding and decoding Neo's variable-length integer format
 * @dev Neo's VarInt format:
 *   - 0-252: Direct byte value (1 byte)
 *   - 253-65535: 0xFD + 2-byte little-endian uint16 (3 bytes)
 *   - 65536-4294967295: 0xFE + 4-byte little-endian uint32 (5 bytes)
 *   - 4294967296+: 0xFF + 8-byte little-endian uint64 (9 bytes)
 */
library VarInt {
    error VarIntTooLarge();
    error InvalidVarIntEncoding();

    /**
     * @notice Encodes a uint256 value into Neo's VarInt format
     * @param value The value to encode
     * @return encoded The encoded bytes
     */
    function encodeVarInt(uint256 value) internal pure returns (bytes memory encoded) {
        if (value < 0xFD) {
            // Direct encoding: 1 byte
            encoded = new bytes(1);
            assembly {
                mstore8(add(encoded, 0x20), value)
            }
        } else if (value <= 0xFFFF) {
            // 0xFD prefix + 2-byte little-endian uint16
            encoded = new bytes(3);
            assembly {
                let ptr := add(encoded, 0x20)
                mstore8(ptr, 0xFD)
                mstore8(add(ptr, 1), and(value, 0xFF))
                mstore8(add(ptr, 2), and(shr(8, value), 0xFF))
            }
        } else if (value <= 0xFFFFFFFF) {
            // 0xFE prefix + 4-byte little-endian uint32
            encoded = new bytes(5);
            assembly {
                let ptr := add(encoded, 0x20)
                mstore8(ptr, 0xFE)
                mstore8(add(ptr, 1), and(value, 0xFF))
                mstore8(add(ptr, 2), and(shr(8, value), 0xFF))
                mstore8(add(ptr, 3), and(shr(16, value), 0xFF))
                mstore8(add(ptr, 4), and(shr(24, value), 0xFF))
            }
        } else if (value <= type(uint64).max) {
            // 0xFF prefix + 8-byte little-endian uint64
            encoded = new bytes(9);
            assembly {
                let ptr := add(encoded, 0x20)
                mstore8(ptr, 0xFF)
                mstore8(add(ptr, 1), and(value, 0xFF))
                mstore8(add(ptr, 2), and(shr(8, value), 0xFF))
                mstore8(add(ptr, 3), and(shr(16, value), 0xFF))
                mstore8(add(ptr, 4), and(shr(24, value), 0xFF))
                mstore8(add(ptr, 5), and(shr(32, value), 0xFF))
                mstore8(add(ptr, 6), and(shr(40, value), 0xFF))
                mstore8(add(ptr, 7), and(shr(48, value), 0xFF))
                mstore8(add(ptr, 8), and(shr(56, value), 0xFF))
            }
        } else {
            revert VarIntTooLarge();
        }
    }

    /**
     * @notice Decodes a VarInt from bytes starting at the given offset
     * @param data The bytes to decode from
     * @param offset The starting offset
     * @return value The decoded value
     * @return newOffset The new offset after reading the VarInt
     */
    function decodeVarInt(
        bytes memory data,
        uint256 offset
    ) internal pure returns (uint256 value, uint256 newOffset) {
        if (offset >= data.length) {
            revert InvalidVarIntEncoding();
        }

        // Load a single 32-byte word and extract all needed bytes from it
        uint256 firstByte;
        uint256 word;
        assembly {
            word := mload(add(add(data, 0x20), offset))
            firstByte := byte(0, word)
        }

        if (firstByte < 0xFD) {
            // Direct encoding
            value = firstByte;
            newOffset = offset + 1;
        } else if (firstByte == 0xFD) {
            // 2-byte little-endian uint16
            if (offset + 3 > data.length) {
                revert InvalidVarIntEncoding();
            }
            assembly {
                value := or(byte(1, word), shl(8, byte(2, word)))
            }
            newOffset = offset + 3;
        } else if (firstByte == 0xFE) {
            // 4-byte little-endian uint32
            if (offset + 5 > data.length) {
                revert InvalidVarIntEncoding();
            }
            assembly {
                value := or(
                    or(byte(1, word), shl(8, byte(2, word))),
                    or(shl(16, byte(3, word)), shl(24, byte(4, word)))
                )
            }
            newOffset = offset + 5;
        } else {
            // 0xFF: 8-byte little-endian uint64
            if (offset + 9 > data.length) {
                revert InvalidVarIntEncoding();
            }
            assembly {
                value := or(
                    or(
                        or(byte(1, word), shl(8, byte(2, word))),
                        or(shl(16, byte(3, word)), shl(24, byte(4, word)))
                    ),
                    or(
                        or(shl(32, byte(5, word)), shl(40, byte(6, word))),
                        or(shl(48, byte(7, word)), shl(56, byte(8, word)))
                    )
                )
            }
            newOffset = offset + 9;
        }
    }
}
