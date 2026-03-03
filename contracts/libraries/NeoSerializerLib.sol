// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./VarInt.sol";
import "./NeoTypes.sol";

/**
 * @title NeoSerializerLib
 * @notice Library for Neo's StdLib Serialize and Deserialize methods
 * @dev Can be used directly in contracts via `using NeoSerializerLib for ...` or `NeoSerializerLib.functionName()`
 *      Gas-optimized with assembly for bulk memory operations and inlined constants.
 */
library NeoSerializerLib {
    using VarInt for uint256;

    error InvalidData();
    error UnsupportedType();
    error DeserializationError(string reason);
    error DataTooLarge();

    // Maximum size limits to prevent DoS
    uint256 internal constant MAX_ITEM_SIZE = 1024 * 1024; // 1MB
    uint256 internal constant MAX_STACK_SIZE = 1024;

    // CallFlags constants (matching Neo's CallFlags enum)
    // These are bit flags that can be combined using bitwise OR
    uint256 public constant CALL_FLAGS_NONE = 0;
    uint256 public constant CALL_FLAGS_READ_STATES = 1;
    uint256 public constant CALL_FLAGS_WRITE_STATES = 2;
    uint256 public constant CALL_FLAGS_ALLOW_CALL = 4;
    uint256 public constant CALL_FLAGS_ALLOW_NOTIFY = 8;
    // Common combinations
    uint256 public constant CALL_FLAGS_STATES = 3; // ReadStates | WriteStates
    uint256 public constant CALL_FLAGS_READ_ONLY = 5; // ReadStates | AllowCall
    uint256 public constant CALL_FLAGS_ALL = 15; // All flags (ReadStates | WriteStates | AllowCall | AllowNotify)

    // =========================================================================
    //                          SERIALIZATION
    // =========================================================================

    /**
     * @notice Serializes a boolean value
     * @param value The boolean to serialize
     * @return The serialized bytes
     */
    function serialize(bool value) internal pure returns (bytes memory) {
        bytes memory result = new bytes(2);
        result[0] = NeoTypes.TYPE_BOOLEAN;
        result[1] = value ? bytes1(0x01) : bytes1(0x00);
        return result;
    }

    /**
     * @notice Serializes an integer value (uint256)
     * @param value The integer to serialize
     * @return The serialized bytes
     * @dev Optimized: zero intermediate allocations. VarInt is inlined (always 1 byte
     *      for integer byte counts ≤ 33), and little-endian conversion is done in assembly.
     */
    function serialize(uint256 value) internal pure returns (bytes memory) {
        if (value == 0) {
            // Neo: BigInteger.IsZero → empty bytes → type (0x21) + varint(0)
            bytes memory zeroResult = new bytes(2);
            zeroResult[0] = NeoTypes.TYPE_INTEGER;
            // zeroResult[1] is already 0x00 (VarInt length = 0)
            return zeroResult;
        }

        // Count bytes needed
        uint256 temp = value;
        uint256 byteCount;
        unchecked {
            while (temp > 0) {
                byteCount++;
                temp >>= 8;
            }
        }

        // Check if sign extension needed (MSB >= 0x80 needs 0x00 to stay positive in two's complement)
        uint256 msb;
        unchecked {
            msb = (value >> ((byteCount - 1) * 8)) & 0xFF;
        }
        uint256 totalBytes = msb >= 0x80 ? byteCount + 1 : byteCount;

        // totalBytes ≤ 33 (32 bytes for uint256 + 1 sign extension), so VarInt is always 1 byte
        bytes memory result = new bytes(2 + totalBytes);

        assembly {
            let ptr := add(result, 0x20)
            // TYPE_INTEGER = 0x21
            mstore8(ptr, 0x21)
            // VarInt length (always < 0xFD, so 1 byte)
            mstore8(add(ptr, 1), totalBytes)

            // Write little-endian bytes directly
            let val := value
            let writePtr := add(ptr, 2)
            for { let j := 0 } lt(j, byteCount) { j := add(j, 1) } {
                mstore8(add(writePtr, j), and(val, 0xff))
                val := shr(8, val)
            }
            // Sign extension byte (0x00) is already zero from allocation
        }

        return result;
    }

    /**
     * @notice Serializes a byte array (ByteString)
     * @param value The byte array to serialize
     * @return The serialized bytes
     */
    function serialize(bytes memory value) internal pure returns (bytes memory) {
        return _serializeTypedBytes(NeoTypes.TYPE_BYTESTRING, value);
    }

    /**
     * @notice Serializes a string (as ByteString with UTF-8 encoding)
     * @param value The string to serialize
     * @return The serialized bytes
     */
    function serialize(string memory value) internal pure returns (bytes memory) {
        return _serializeTypedBytes(NeoTypes.TYPE_BYTESTRING, bytes(value));
    }

    /**
     * @notice Serializes an array of integers
     * @param value The array to serialize
     * @return The serialized bytes
     */
    function serialize(uint256[] memory value) internal pure returns (bytes memory) {
        bytes[] memory serializedItems = new bytes[](value.length);
        unchecked {
            for (uint256 i = 0; i < value.length; ++i) {
                serializedItems[i] = serialize(value[i]);
            }
        }
        return serializeArray(serializedItems);
    }

    /**
     * @notice Serializes an array of byte arrays
     * @param value The array to serialize
     * @return The serialized bytes
     */
    function serialize(bytes[] memory value) internal pure returns (bytes memory) {
        bytes[] memory serializedItems = new bytes[](value.length);
        unchecked {
            for (uint256 i = 0; i < value.length; ++i) {
                serializedItems[i] = serialize(value[i]);
            }
        }
        return serializeArray(serializedItems);
    }

    /**
     * @notice Serializes a Neo Hash160 (UInt160) as a ByteString with reversed byte order
     * @param value The 20-byte hash in big-endian (display format, e.g. 0xef4073...)
     * @return The serialized bytes (ByteString type 0x28, 20 bytes in little-endian)
     * @dev Optimized: single allocation + assembly byte reversal (no intermediate buffer).
     *      Neo's UInt160.Parse() reverses hex string bytes to little-endian internal storage.
     *      When serialized via StdLib.Serialize, the little-endian bytes are written.
     */
    function serializeHash160(bytes20 value) internal pure returns (bytes memory) {
        // Total: type (0x28) + varint(20=0x14) + 20 reversed bytes = 22 bytes
        bytes memory result = new bytes(22);
        assembly {
            let ptr := add(result, 0x20)
            // TYPE_BYTESTRING = 0x28
            mstore8(ptr, 0x28)
            // VarInt(20) = 0x14
            mstore8(add(ptr, 1), 0x14)

            // Reverse 20 bytes: result[2+i] = value[19-i]
            // bytes20 is left-aligned in a 32-byte word
            let writePtr := add(ptr, 2)
            for { let i := 0 } lt(i, 20) { i := add(i, 1) } {
                mstore8(add(writePtr, i), byte(sub(19, i), value))
            }
        }
        return result;
    }

    /**
     * @notice Serializes an address as a Neo Hash160 (UInt160) ByteString
     * @param value The address to serialize
     * @return The serialized bytes (ByteString type 0x28, 20 bytes in little-endian)
     * @dev Convenience overload for address type. Converts address to bytes20 and serializes.
     */
    function serializeHash160(address value) internal pure returns (bytes memory) {
        return serializeHash160(bytes20(value));
    }

    /**
     * @notice Serializes a byte array as Buffer (type 0x30)
     * @param value The byte array to serialize
     * @return The serialized bytes
     * @dev In Neo, ContractParamType.ByteArray maps to StackItemType.Buffer (0x30),
     *      which is a mutable byte array. Format is identical to ByteString but with
     *      type byte 0x30 instead of 0x28.
     */
    function serializeBuffer(bytes memory value) internal pure returns (bytes memory) {
        return _serializeTypedBytes(NeoTypes.TYPE_BUFFER, value);
    }

    /**
     * @notice Serializes a contract call for Neo blockchain
     * @param target The contract hash (Hash160/UInt160 - 20 bytes, big-endian display format)
     * @param method The method name to call
     * @param callFlags The call flags (bit flags: None=0, ReadStates=1, WriteStates=2, AllowCall=4, AllowNotify=8)
     * @param args Array of already-serialized arguments
     * @return The serialized contract call bytes
     * @dev Format: Array(4)[ Hash160(target), String(method), Integer(callFlags), Array(args) ]
     *      Matches Neo StdLib.Serialize for [Hash160, String, Integer, Array] structure.
     *      The target is reversed to little-endian (matching Neo's UInt160 internal storage).
     *      The args parameter expects each element to already be serialized
     *      (e.g. via serialize(uint256), serializeHash160(), serializeBuffer(), etc.)
     */
    function serializeCall(
        bytes20 target,
        string memory method,
        uint256 callFlags,
        bytes[] memory args
    ) internal pure returns (bytes memory) {
        // 1. Serialize target (Hash160 → ByteString with reversed bytes, matching Neo UInt160)
        bytes memory serializedTarget = serializeHash160(target);

        // 2. Serialize method name (as ByteString)
        bytes memory serializedMethod = serialize(method);

        // 3. Serialize call flags (as Integer)
        bytes memory serializedCallFlags = serialize(callFlags);

        // 4. Wrap args in a Neo Array — args are already serialized items,
        //    so use serializeArray() directly (NOT serialize(bytes[]) which
        //    would re-wrap each arg as ByteString)
        bytes memory serializedArgs = serializeArray(args);

        // 5. Combine into outer Array — these are all already serialized,
        //    so again use serializeArray() directly
        bytes[] memory callArray = new bytes[](4);
        callArray[0] = serializedTarget;
        callArray[1] = serializedMethod;
        callArray[2] = serializedCallFlags;
        callArray[3] = serializedArgs;

        return serializeArray(callArray);
    }

    /**
     * @notice Serializes a contract call for Neo blockchain (address overload)
     * @param target The contract address (converted to Hash160/UInt160)
     * @param method The method name to call
     * @param callFlags The call flags
     * @param args Array of already-serialized arguments
     * @return The serialized contract call bytes
     * @dev Convenience overload for address type. Converts address to bytes20 and serializes.
     */
    function serializeCall(
        address target,
        string memory method,
        uint256 callFlags,
        bytes[] memory args
    ) internal pure returns (bytes memory) {
        return serializeCall(bytes20(target), method, callFlags, args);
    }

    /**
     * @notice Serializes an array of already-serialized items
     * @param items Array of serialized items
     * @return The serialized array bytes
     * @dev Optimized: uses assembly word-copy for each item instead of byte-by-byte.
     */
    function serializeArray(bytes[] memory items) internal pure returns (bytes memory) {
        uint256 count = items.length;

        // Calculate total data size
        uint256 totalDataSize;
        unchecked {
            for (uint256 i = 0; i < count; ++i) {
                totalDataSize += items[i].length;
            }
        }

        bytes memory result;
        uint256 offset;

        if (count < 0xFD) {
            // Fast path: 1-byte VarInt for count (covers most cases)
            result = new bytes(2 + totalDataSize);
            result[0] = NeoTypes.TYPE_ARRAY;
            assembly {
                mstore8(add(add(result, 0x20), 1), count)
            }
            offset = 2;
        } else {
            // General case: multi-byte VarInt
            bytes memory countEncoded = VarInt.encodeVarInt(count);
            uint256 viLen = countEncoded.length;
            result = new bytes(1 + viLen + totalDataSize);
            result[0] = NeoTypes.TYPE_ARRAY;
            _copyBytes(result, 1, countEncoded, 0, viLen);
            offset = 1 + viLen;
        }

        // Write items in forward order using word-sized copies
        unchecked {
            for (uint256 i = 0; i < count; ++i) {
                bytes memory item = items[i];
                uint256 itemLen = item.length;
                if (itemLen > 0) {
                    _copyBytes(result, offset, item, 0, itemLen);
                }
                offset += itemLen;
            }
        }

        return result;
    }

    // =========================================================================
    //                     APPEND ARG (GAS-EFFICIENT PATTERN)
    // =========================================================================

    /**
     * @notice Appends a serialized argument to an existing serialized call
     * @param serializedCall The existing serialized call (output of serializeCall)
     * @param serializedArg The new argument to append (must already be serialized)
     * @return result The modified serialized call with the new argument appended
     * @dev Gas-efficient pattern: serialize the call off-chain (free), then on-chain
     *      only append additional arguments. This avoids paying gas for the full
     *      serialization.
     *
     *      How it works:
     *        A serializeCall output is always: Array(4)[ target, method, flags, Array(N)[args...] ]
     *        This function navigates to the inner args Array, increments its count by 1,
     *        and appends the new serialized arg at the end.
     *
     *      The entire function is inlined in assembly for minimal gas overhead.
     *      Navigation uses inline VarInt decoding — no function calls.
     *
     *      Constraints:
     *        - The inner args array count must be < 252 (single-byte VarInt).
     *          This covers all practical use cases.
     *        - serializedArg must be a properly serialized item (e.g. from serialize(),
     *          serializeHash160(), etc.)
     *
     *      Example:
     *        // Off-chain: serialize the call with known args (free)
     *        bytes memory base = serializeCall(target, method, flags, [arg1, arg2, ...]);
     *        // On-chain: only pay gas to append the nonce
     *        bytes memory withNonce = appendArgToCall(base, serialize(nonce));
     */
    function appendArgToCall(
        bytes memory serializedCall,
        bytes memory serializedArg
    ) internal pure returns (bytes memory result) {
        assembly {
            let srcPtr := add(serializedCall, 0x20)
            let existingLen := mload(serializedCall)
            let argLen := mload(serializedArg)

            // Validate: byte[0] = 0x40 (Array), byte[1] = 0x04 (count = 4)
            // Both bytes are in the first loaded word
            let firstByte := byte(0, mload(srcPtr))
            let secondByte := byte(1, mload(srcPtr))
            if or(iszero(eq(firstByte, 0x40)), iszero(eq(secondByte, 0x04))) {
                // revert DeserializationError("Invalid call")
                mstore(0x00, 0x08c379a000000000000000000000000000000000000000000000000000000000)
                mstore(0x04, 0x20)
                mstore(0x24, 12)
                mstore(0x44, "Invalid call")
                revert(0x00, 0x64)
            }

            // Navigate: skip 3 items (target, method, flags) starting at offset 2
            // All 3 are variable-length types (ByteString/Integer): type + VarInt(len) + len bytes
            let offset := 2
            for { let i := 0 } lt(i, 3) { i := add(i, 1) } {
                // Skip type byte
                offset := add(offset, 1)
                // Inline VarInt decode: read first byte of length
                let lenByte := byte(0, mload(add(srcPtr, offset)))
                switch lt(lenByte, 0xFD)
                case 1 {
                    // Single-byte VarInt: length = lenByte
                    offset := add(add(offset, 1), lenByte)
                }
                default {
                    // 3-byte VarInt (0xFD prefix): length = 2 LE bytes
                    let lo := byte(0, mload(add(srcPtr, add(offset, 1))))
                    let hi := byte(0, mload(add(srcPtr, add(offset, 2))))
                    offset := add(add(offset, 3), add(lo, shl(8, hi)))
                }
            }

            // Validate inner array: byte at offset must be 0x40 (Array)
            if iszero(eq(byte(0, mload(add(srcPtr, offset))), 0x40)) {
                mstore(0x00, 0x08c379a000000000000000000000000000000000000000000000000000000000)
                mstore(0x04, 0x20)
                mstore(0x24, 12)
                mstore(0x44, "Invalid call")
                revert(0x00, 0x64)
            }

            // The inner array count byte is at offset+1
            let innerCountOffset := add(offset, 1)
            let innerCount := byte(0, mload(add(srcPtr, innerCountOffset)))

            // Allocate result: existingLen + argLen
            let totalLen := add(existingLen, argLen)
            result := mload(0x40)
            mstore(result, totalLen)
            let resultPtr := add(result, 0x20)
            // Update free memory pointer (32-byte aligned)
            mstore(0x40, add(resultPtr, and(add(totalLen, 31), not(31))))

            // Copy existing data using 32-byte word copies
            for { let i := 0 } lt(i, existingLen) { i := add(i, 0x20) } {
                mstore(add(resultPtr, i), mload(add(srcPtr, i)))
            }

            // Increment inner array count in the result
            mstore8(add(resultPtr, innerCountOffset), add(innerCount, 1))

            // Copy serialized arg at the end
            let argSrc := add(serializedArg, 0x20)
            let argDest := add(resultPtr, existingLen)
            for { let i := 0 } lt(i, argLen) { i := add(i, 0x20) } {
                mstore(add(argDest, i), mload(add(argSrc, i)))
            }
        }
    }

    /**
     * @notice Appends a serialized argument to an existing serialized call (fast path)
     * @param serializedCall The existing serialized call (output of serializeCall)
     * @param innerArrayCountOffset The byte offset of the inner array's count byte.
     *        Compute this off-chain when you first serialize the call — it's the position
     *        of the VarInt count byte right after the inner Array type marker (0x40).
     * @param serializedArg The new argument to append (must already be serialized)
     * @return result The modified serialized call with the new argument appended
     * @dev Maximum gas efficiency: no navigation at all. Just memcpy + 1 byte increment.
     *      The caller provides the pre-computed offset, eliminating all parsing overhead.
     *
     *      To find innerArrayCountOffset off-chain (JS/TS):
     *        const serialized = serializeCall(target, method, flags, args);
     *        // Walk the bytes: skip outer Array header (2 bytes), skip 3 items, skip inner Array type byte
     *        // Or simply: innerArrayCountOffset = serialized.length - innerArgsBytes.length - 1
     *        // (where innerArgsBytes is the concatenation of all serialized args)
     *
     *      Example:
     *        bytes memory base = serializeCall(target, method, flags, knownArgs);
     *        // innerArrayCountOffset computed off-chain and stored as a constant
     *        uint256 constant OFFSET = 45; // example
     *        bytes memory full = appendArgToCall(base, OFFSET, serialize(nonce));
     */
    function appendArgToCall(
        bytes memory serializedCall,
        uint256 innerArrayCountOffset,
        bytes memory serializedArg
    ) internal pure returns (bytes memory result) {
        assembly {
            let srcPtr := add(serializedCall, 0x20)
            let existingLen := mload(serializedCall)
            let argLen := mload(serializedArg)

            // Read current inner array count
            let innerCount := byte(0, mload(add(srcPtr, innerArrayCountOffset)))

            // Allocate result
            let totalLen := add(existingLen, argLen)
            result := mload(0x40)
            mstore(result, totalLen)
            let resultPtr := add(result, 0x20)
            mstore(0x40, add(resultPtr, and(add(totalLen, 31), not(31))))

            // Copy existing data
            for { let i := 0 } lt(i, existingLen) { i := add(i, 0x20) } {
                mstore(add(resultPtr, i), mload(add(srcPtr, i)))
            }

            // Increment inner array count
            mstore8(add(resultPtr, innerArrayCountOffset), add(innerCount, 1))

            // Copy serialized arg at end
            let argSrc := add(serializedArg, 0x20)
            let argDest := add(resultPtr, existingLen)
            for { let i := 0 } lt(i, argLen) { i := add(i, 0x20) } {
                mstore(add(argDest, i), mload(add(argSrc, i)))
            }
        }
    }

    // =========================================================================
    //                  REPLACE LAST ARG (EVEN MORE GAS-EFFICIENT)
    // =========================================================================

    /**
     * @notice Replaces the last argument in a serialized call with a new value
     * @param serializedCall The existing serialized call (output of serializeCall)
     * @param oldArgSerializedLength The serialized byte length of the old last arg
     *        (i.e. the placeholder). Since the placeholder is serialized off-chain,
     *        its length is known. For example, serialize(0) = 2 bytes (0x21, 0x00).
     * @param newSerializedArg The replacement argument (must already be serialized)
     * @return result The modified serialized call with the last arg replaced
     * @dev The most gas-efficient on-chain mutation: serialize the entire call off-chain
     *      with a placeholder for the last arg, then on-chain just chop it off and
     *      append the real value. No inner-item navigation needed.
     *
     *      Since the last arg is always the last thing in the byte array:
     *        prefixLen = serializedCall.length - oldArgSerializedLength
     *        result = prefix + newSerializedArg
     *
     *      Same navigation cost as appendArgToCall (skip 3 outer items only).
     *
     *      Example:
     *        // Off-chain: serialize with nonce = 0 (placeholder)
     *        bytes memory base = serializeCall(target, method, flags, [arg1, ..., serialize(0)]);
     *        // On-chain: replace the placeholder (2 bytes) with the real nonce
     *        bytes memory real = replaceLastArg(base, 2, serialize(actualNonce));
     */
    function replaceLastArg(
        bytes memory serializedCall,
        uint256 oldArgSerializedLength,
        bytes memory newSerializedArg
    ) internal pure returns (bytes memory result) {
        assembly {
            let srcPtr := add(serializedCall, 0x20)
            let existingLen := mload(serializedCall)
            let argLen := mload(newSerializedArg)

            // prefixLen = everything before the old last arg
            let prefixLen := sub(existingLen, oldArgSerializedLength)
            let totalLen := add(prefixLen, argLen)

            // Allocate result
            result := mload(0x40)
            mstore(result, totalLen)
            let resultPtr := add(result, 0x20)
            mstore(0x40, add(resultPtr, and(add(totalLen, 31), not(31))))

            // Copy prefix (everything before the old last arg)
            for { let i := 0 } lt(i, prefixLen) { i := add(i, 0x20) } {
                mstore(add(resultPtr, i), mload(add(srcPtr, i)))
            }

            // Copy new arg
            let argSrc := add(newSerializedArg, 0x20)
            let argDest := add(resultPtr, prefixLen)
            for { let i := 0 } lt(i, argLen) { i := add(i, 0x20) } {
                mstore(add(argDest, i), mload(add(argSrc, i)))
            }
        }
    }

    // =========================================================================
    //                          DESERIALIZATION
    // =========================================================================

    /**
     * @notice Deserializes a boolean value
     * @param data The serialized bytes
     * @param offset The starting offset
     * @return value The deserialized boolean
     * @return newOffset The offset after reading
     */
    function deserializeBool(
        bytes memory data,
        uint256 offset
    ) internal pure returns (bool value, uint256 newOffset) {
        if (offset + 2 > data.length) {
            revert DeserializationError("Insufficient data for boolean");
        }

        bytes1 typeByte = data[offset];
        if (typeByte != NeoTypes.TYPE_BOOLEAN) {
            revert DeserializationError("Invalid type for boolean");
        }

        bytes1 valueByte = data[offset + 1];
        if (valueByte == 0x00) {
            value = false;
        } else if (valueByte == 0x01) {
            value = true;
        } else {
            revert DeserializationError("Invalid boolean value");
        }

        newOffset = offset + 2;
    }

    /**
     * @notice Deserializes an integer value
     * @param data The serialized bytes
     * @param offset The starting offset
     * @return value The deserialized integer
     * @return newOffset The offset after reading
     * @dev Optimized: uses assembly for little-endian byte reading (avoids bounds-checked array access).
     */
    function deserializeUint256(
        bytes memory data,
        uint256 offset
    ) internal pure returns (uint256 value, uint256 newOffset) {
        if (offset >= data.length) {
            revert DeserializationError("Insufficient data");
        }

        bytes1 typeByte = data[offset];
        if (typeByte != NeoTypes.TYPE_INTEGER) {
            revert DeserializationError("Invalid type for integer");
        }

        unchecked {
            offset++;
        }

        // Read VarInt length
        (uint256 length, uint256 lengthOffset) = VarInt.decodeVarInt(data, offset);
        offset = lengthOffset;

        if (offset + length > data.length) {
            revert DeserializationError("Insufficient data for integer bytes");
        }

        // Read little-endian bytes using assembly (avoids per-byte bounds checking)
        assembly {
            let ptr := add(add(data, 0x20), offset)
            let val := 0
            for { let i := 0 } lt(i, length) { i := add(i, 1) } {
                val := or(val, shl(mul(i, 8), byte(0, mload(add(ptr, i)))))
            }
            value := val
        }

        newOffset = offset + length;
    }

    /**
     * @notice Deserializes a byte array
     * @param data The serialized bytes
     * @param offset The starting offset
     * @return value The deserialized byte array
     * @return newOffset The offset after reading
     * @dev Optimized: uses assembly word-copy instead of byte-by-byte.
     */
    function deserializeBytes(
        bytes memory data,
        uint256 offset
    ) internal pure returns (bytes memory value, uint256 newOffset) {
        if (offset >= data.length) {
            revert DeserializationError("Insufficient data");
        }

        bytes1 typeByte = data[offset];
        if (typeByte != NeoTypes.TYPE_BYTESTRING &&
            typeByte != NeoTypes.TYPE_BUFFER) {
            revert DeserializationError("Invalid type for byte array");
        }

        unchecked {
            offset++;
        }

        // Read VarInt length
        (uint256 length, uint256 lengthOffset) = VarInt.decodeVarInt(data, offset);
        offset = lengthOffset;

        if (offset + length > data.length) {
            revert DeserializationError("Insufficient data for byte array");
        }

        // Read bytes using assembly word-copy
        value = new bytes(length);
        if (length > 0) {
            _copyBytes(value, 0, data, offset, length);
        }

        newOffset = offset + length;
    }

    /**
     * @notice Deserializes an array
     * @param data The serialized bytes
     * @param offset The starting offset
     * @return items Array of serialized item bytes
     * @return newOffset The offset after reading
     */
    function deserializeArray(
        bytes memory data,
        uint256 offset
    ) internal pure returns (bytes[] memory items, uint256 newOffset) {
        if (offset >= data.length) {
            revert DeserializationError("Insufficient data");
        }

        bytes1 typeByte = data[offset];
        if (typeByte != NeoTypes.TYPE_ARRAY &&
            typeByte != NeoTypes.TYPE_STRUCT) {
            revert DeserializationError("Invalid type for array");
        }

        unchecked {
            offset++;
        }

        // Read count
        (uint256 count, uint256 countOffset) = VarInt.decodeVarInt(data, offset);
        offset = countOffset;

        if (count > MAX_STACK_SIZE) {
            revert DeserializationError("Array too large");
        }

        // Deserialize items (stored in forward order, matching Neo's BinarySerializer)
        items = new bytes[](count);
        unchecked {
            for (uint256 i = 0; i < count; ++i) {
                (bytes memory item, uint256 itemOffset) = deserializeItem(data, offset);
                items[i] = item;
                offset = itemOffset;
            }
        }

        newOffset = offset;
    }

    /**
     * @notice Deserializes a single item (any type)
     * @param data The serialized bytes
     * @param offset The starting offset
     * @return item The serialized item bytes (including type byte)
     * @return newOffset The offset after reading
     * @dev Optimized: direct byte comparisons (no fromByte() call), assembly word-copy for data.
     */
    function deserializeItem(
        bytes memory data,
        uint256 offset
    ) internal pure returns (bytes memory item, uint256 newOffset) {
        if (offset >= data.length) {
            revert DeserializationError("Insufficient data");
        }

        bytes1 typeByte = data[offset];

        if (typeByte == NeoTypes.TYPE_ANY) {
            // Null - just the type byte
            item = new bytes(1);
            item[0] = typeByte;
            newOffset = offset + 1;
        } else if (typeByte == NeoTypes.TYPE_BOOLEAN) {
            // Boolean - type + 1 byte
            item = new bytes(2);
            item[0] = data[offset];
            item[1] = data[offset + 1];
            newOffset = offset + 2;
        } else if (typeByte == NeoTypes.TYPE_INTEGER ||
                   typeByte == NeoTypes.TYPE_BYTESTRING ||
                   typeByte == NeoTypes.TYPE_BUFFER) {
            // Variable-length: type + VarInt length + bytes
            uint256 currentOffset;
            unchecked {
                currentOffset = offset + 1;
            }
            (uint256 length, uint256 lengthOffset) = VarInt.decodeVarInt(data, currentOffset);
            currentOffset = lengthOffset;

            if (currentOffset + length > data.length) {
                revert DeserializationError("Insufficient data for variable-length item");
            }

            uint256 totalLength = 1 + (lengthOffset - (offset + 1)) + length;
            item = new bytes(totalLength);

            // Copy bytes using assembly word-copy
            _copyBytes(item, 0, data, offset, totalLength);

            newOffset = offset + totalLength;
        } else if (typeByte == NeoTypes.TYPE_ARRAY ||
                   typeByte == NeoTypes.TYPE_STRUCT) {
            // Array/Struct - need to recursively deserialize
            uint256 startOffset = offset;
            unchecked {
                offset++; // Skip type byte
            }

            (uint256 count, uint256 countOffset) = VarInt.decodeVarInt(data, offset);
            offset = countOffset;

            // Skip all items
            unchecked {
                for (uint256 i = 0; i < count; ++i) {
                    (, uint256 subOffset) = deserializeItem(data, offset);
                    offset = subOffset;
                }
            }

            uint256 totalLength = offset - startOffset;
            item = new bytes(totalLength);
            _copyBytes(item, 0, data, startOffset, totalLength);
            newOffset = offset;
        } else if (typeByte == NeoTypes.TYPE_MAP) {
            // Map - similar to array but with key-value pairs
            uint256 startOffset = offset;
            unchecked {
                offset++; // Skip type byte
            }

            (uint256 count, uint256 countOffset) = VarInt.decodeVarInt(data, offset);
            offset = countOffset;

            // Deserialize all pairs (value, key in reverse order)
            unchecked {
                for (uint256 i = 0; i < count; ++i) {
                    // Value first
                    (, uint256 valueOffset) = deserializeItem(data, offset);
                    offset = valueOffset;
                    // Key second
                    (, uint256 keyOffset) = deserializeItem(data, offset);
                    offset = keyOffset;
                }
            }

            uint256 totalLength = offset - startOffset;
            item = new bytes(totalLength);
            _copyBytes(item, 0, data, startOffset, totalLength);
            newOffset = offset;
        } else {
            revert DeserializationError("Unsupported item type");
        }
    }

    // =========================================================================
    //                          UTILITIES
    // =========================================================================

    /**
     * @notice Converts a uint256 to Neo-compatible two's complement little-endian bytes
     * @param value The value to convert
     * @return result The little-endian byte representation
     * @dev Zero returns empty bytes (matching Neo's BigInteger.IsZero check).
     *      Positive values with the most significant byte >= 0x80 get an extra
     *      0x00 byte appended to prevent two's complement sign confusion.
     *      This matches .NET BigInteger.ToByteArray() behavior used by Neo.
     *      Optimized with assembly for byte extraction.
     */
    function toLittleEndianBytes(uint256 value) internal pure returns (bytes memory result) {
        if (value == 0) {
            // Neo: BigInteger.IsZero ? Array.Empty<byte>()
            return new bytes(0);
        }

        // Find the number of bytes needed
        uint256 temp = value;
        uint256 byteCount;
        unchecked {
            while (temp > 0) {
                byteCount++;
                temp >>= 8;
            }
        }

        // Check if the most significant byte has bit 7 set.
        uint256 msb;
        unchecked {
            msb = (value >> ((byteCount - 1) * 8)) & 0xFF;
        }
        if (msb >= 0x80) {
            unchecked {
                byteCount++;
            }
        }

        result = new bytes(byteCount);
        assembly {
            let ptr := add(result, 0x20)
            let val := value
            // byteCount includes sign extension byte which is 0x00 (already zeroed)
            // Only write the actual data bytes
            let dataBytes := byteCount
            if iszero(lt(msb, 0x80)) {
                dataBytes := sub(byteCount, 1)
            }
            for { let i := 0 } lt(i, dataBytes) { i := add(i, 1) } {
                mstore8(add(ptr, i), and(val, 0xff))
                val := shr(8, val)
            }
        }
    }

    // =========================================================================
    //                    PRIVATE HELPERS (GAS OPTIMIZED)
    // =========================================================================

    /**
     * @dev Copies `length` bytes from `src` (at `srcOffset`) to `dest` (at `destOffset`)
     *      using 32-byte word copies in assembly. Much cheaper than byte-by-byte Solidity loops.
     */
    function _copyBytes(
        bytes memory dest,
        uint256 destOffset,
        bytes memory src,
        uint256 srcOffset,
        uint256 length
    ) private pure {
        assembly {
            let destPtr := add(add(dest, 0x20), destOffset)
            let srcPtr := add(add(src, 0x20), srcOffset)

            // Copy full 32-byte words
            let i := 0
            for { } lt(add(i, 31), length) { i := add(i, 0x20) } {
                mstore(add(destPtr, i), mload(add(srcPtr, i)))
            }

            // Copy remaining partial word (if any)
            let remaining := sub(length, i)
            if remaining {
                let mask := sub(exp(0x100, sub(0x20, remaining)), 1)
                let srcWord := and(mload(add(srcPtr, i)), not(mask))
                let destWord := and(mload(add(destPtr, i)), mask)
                mstore(add(destPtr, i), or(srcWord, destWord))
            }
        }
    }

    /**
     * @dev Shared helper for serializing typed byte data (ByteString 0x28 or Buffer 0x30).
     *      Inlines VarInt encoding for the common case (length < 253) to avoid
     *      an extra function call and allocation. Uses assembly word-copy for the payload.
     */
    function _serializeTypedBytes(bytes1 typeByte, bytes memory value) private pure returns (bytes memory result) {
        uint256 len = value.length;

        if (len < 0xFD) {
            // Fast path: 1-byte VarInt (covers the vast majority of use cases)
            result = new bytes(2 + len);
            assembly {
                let resultPtr := add(result, 0x20)
                // Write type byte (bytes1 is left-aligned, shift right 248 to get uint8 value)
                mstore8(resultPtr, shr(248, typeByte))
                // Write 1-byte VarInt length
                mstore8(add(resultPtr, 1), len)

                // Copy payload data with 32-byte word copies
                let destPtr := add(resultPtr, 2)
                let srcPtr := add(value, 0x20)

                let i := 0
                for { } lt(add(i, 31), len) { i := add(i, 0x20) } {
                    mstore(add(destPtr, i), mload(add(srcPtr, i)))
                }

                // Copy remaining partial word
                let r := sub(len, i)
                if r {
                    let mask := sub(exp(0x100, sub(0x20, r)), 1)
                    mstore(add(destPtr, i), or(
                        and(mload(add(srcPtr, i)), not(mask)),
                        and(mload(add(destPtr, i)), mask)
                    ))
                }
            }
        } else {
            // General case: multi-byte VarInt
            bytes memory lengthEncoded = VarInt.encodeVarInt(len);
            uint256 viLen = lengthEncoded.length;
            result = new bytes(1 + viLen + len);
            result[0] = typeByte;
            _copyBytes(result, 1, lengthEncoded, 0, viLen);
            _copyBytes(result, 1 + viLen, value, 0, len);
        }
    }
}
