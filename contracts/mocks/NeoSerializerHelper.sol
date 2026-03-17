// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.25;

import {NeoSerializerLib} from "../libraries/NeoSerializerLib.sol";

/**
 * @title NeoSerializerHelper
 * @notice Test helper that exposes NeoSerializerLib serialization functions.
 */
contract NeoSerializerHelper {
    /**
     * @notice Builds a valid serialized NeoMethodCall with 4 arguments (the exact
     *         shape expected by OracleProxy.initiateOracleCall before it appends
     *         gasForOracle, gasOracleRequestExec, gasOracleResponseReturn, nonce, requestId).
     *
     *  requestOracleData(url, filter, callbackContract, callbackMethod)
     */
    function buildOracleCall(
        address oracleContract,
        string calldata url,
        string calldata filter,
        address callbackContract,
        string calldata callbackMethod
    ) external pure returns (bytes memory) {
        bytes[] memory args = new bytes[](4);
        args[0] = NeoSerializerLib.serialize(url);
        args[1] = NeoSerializerLib.serialize(filter);
        args[2] = NeoSerializerLib.serializeHash160(callbackContract);
        args[3] = NeoSerializerLib.serialize(callbackMethod);

        return NeoSerializerLib.serializeCall(
            oracleContract,
            "requestOracleData",
            15, // CallFlags.All
            args
        );
    }
}
