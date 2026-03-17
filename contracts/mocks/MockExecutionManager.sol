// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.25;

import {IExecutionManager} from "../messageBridge/interfaces/IExecutionManager.sol";
import {AMBTypes} from "../libraries/AMBTypes.sol";

interface IOracleProxyCallback {
    function persistOracleResult(uint256 _requestId, uint256 _responseCode, string calldata _oracleResult) external;
}

/**
 * @title MockExecutionManager
 * @notice Minimal mock that simulates ExecutionManager behaviour for testing.
 *         Sets executingNonce before forwarding the call, then resets it — mirroring
 *         the real ExecutionManager lifecycle.
 */
contract MockExecutionManager is IExecutionManager {
    uint256 public override executingNonce;

    function callOnOracleResult(
        address target,
        uint256 nonce,
        uint256 requestId,
        uint256 responseCode,
        string calldata oracleResult
    ) external {
        executingNonce = nonce;
        IOracleProxyCallback(target).persistOracleResult(requestId, responseCode, oracleResult);
        executingNonce = 0;
    }

    function executeMessage(uint256, bytes calldata, address payable)
        external
        payable
        override
        returns (AMBTypes.Result memory)
    {
        return AMBTypes.Result({ success: false, returnData: "" });
    }
}
