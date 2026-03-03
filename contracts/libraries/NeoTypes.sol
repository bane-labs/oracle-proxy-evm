// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title NeoTypes
 * @notice Library defining Neo's StackItemType enum and helper functions
 */
library NeoTypes {
    /**
     * @notice Neo StackItemType enum values
     * @dev These match Neo's StackItemType enum exactly
     * Note: Solidity enums are sequential, but Neo uses non-sequential values (0x10, 0x11, 0x12)
     * So we use explicit byte constants instead
     */
    enum StackItemType {
        Any,        // 0x00 - Null value
        Boolean,    // 0x01 - Boolean
        Integer,    // 0x02 - BigInteger
        ByteString, // 0x03 - Byte array
        Buffer,     // 0x04 - Mutable byte array
        Array,      // 0x10 - Array of StackItems (NOT 5!)
        Struct,     // 0x11 - Struct (array with value semantics)
        Map         // 0x12 - Key-value pairs
    }

    // Explicit byte values matching Neo's actual format (from test cases)
    // These are the actual values used in Neo's BinarySerializer
    bytes1 public constant TYPE_ANY = 0x00;
    bytes1 public constant TYPE_BOOLEAN = 0x20;  // 0x20, not 0x01!
    bytes1 public constant TYPE_INTEGER = 0x21;  // 0x21, not 0x02!
    bytes1 public constant TYPE_BYTESTRING = 0x28; // 0x28, not 0x03!
    bytes1 public constant TYPE_BUFFER = 0x30;   // 0x30 (inferred)
    bytes1 public constant TYPE_ARRAY = 0x40;    // 0x40, not 0x10!
    bytes1 public constant TYPE_STRUCT = 0x41;   // 0x41, not 0x11!
    bytes1 public constant TYPE_MAP = 0x48;      // 0x48, not 0x12!

    /**
     * @notice Converts a StackItemType to its byte representation
     * @param itemType The StackItemType to convert
     * @return The byte representation
     */
    function toByte(StackItemType itemType) internal pure returns (bytes1) {
        if (itemType == StackItemType.Any) return TYPE_ANY;
        if (itemType == StackItemType.Boolean) return TYPE_BOOLEAN;
        if (itemType == StackItemType.Integer) return TYPE_INTEGER;
        if (itemType == StackItemType.ByteString) return TYPE_BYTESTRING;
        if (itemType == StackItemType.Buffer) return TYPE_BUFFER;
        if (itemType == StackItemType.Array) return TYPE_ARRAY;
        if (itemType == StackItemType.Struct) return TYPE_STRUCT;
        if (itemType == StackItemType.Map) return TYPE_MAP;
        revert("Invalid StackItemType");
    }

    /**
     * @notice Converts a byte to a StackItemType
     * @param b The byte to convert
     * @return The StackItemType
     */
    function fromByte(bytes1 b) internal pure returns (StackItemType) {
        if (b == TYPE_ANY) return StackItemType.Any;
        if (b == TYPE_BOOLEAN) return StackItemType.Boolean;
        if (b == TYPE_INTEGER) return StackItemType.Integer;
        if (b == TYPE_BYTESTRING) return StackItemType.ByteString;
        if (b == TYPE_BUFFER) return StackItemType.Buffer;
        if (b == TYPE_ARRAY) return StackItemType.Array;
        if (b == TYPE_STRUCT) return StackItemType.Struct;
        if (b == TYPE_MAP) return StackItemType.Map;
        revert("Invalid StackItemType");
    }

    /**
     * @notice Checks if a StackItemType is a container type (Array, Struct, or Map)
     * @param itemType The StackItemType to check
     * @return True if it's a container type
     */
    function isContainer(StackItemType itemType) internal pure returns (bool) {
        return itemType == StackItemType.Array ||
               itemType == StackItemType.Struct ||
               itemType == StackItemType.Map;
    }

    /**
     * @notice Checks if a StackItemType is a primitive type
     * @param itemType The StackItemType to check
     * @return True if it's a primitive type
     */
    function isPrimitive(StackItemType itemType) internal pure returns (bool) {
        return itemType == StackItemType.Any ||
               itemType == StackItemType.Boolean ||
               itemType == StackItemType.Integer ||
               itemType == StackItemType.ByteString ||
               itemType == StackItemType.Buffer;
    }
}
