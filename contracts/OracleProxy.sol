// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.25;

import {INativeBridgeExtended} from "./interfaces/INativeBridgeExtended.sol";
import {IMessageBridge} from "./messageBridge/interfaces/IMessageBridge.sol";
import {NeoSerializerLib} from "./libraries/NeoSerializerLib.sol";

/**
 * @title OracleProxy
 * @notice Example contract demonstrating the full bridge flow:
 *         1. Bridge GAS from NeoX to N3 using native bridge
 *         2. Send Oracle call through message bridge
 *         3. Receive and store Oracle result
 */
contract OracleProxy {
    INativeBridgeExtended public immutable bridge;
    IMessageBridge public immutable messageBridge;
    address public immutable executionManager;

    // Mapping from oracle request ID to oracle result
    mapping(uint256 => bytes) public oracleResults;

    // Mapping from oracle request ID to whether result has been received
    mapping(uint256 => bool) public hasResult;

    // Auto-incrementing request ID counter; first ID = 0
    uint256 public requestIdCounter;

    // Events
    event OracleCallInitiated(
        uint256 indexed requestId,
        uint256 indexed withdrawalNonce,
        uint256 indexed messageNonce,
        address sender,
        bytes oracleRequest
    );
    
    event OracleResultReceived(
        uint256 indexed requestId,
        bytes result
    );

    /**
     * @notice Constructor
     * @param _bridge Address of the native bridge contract
     * @param _messageBridge Address of the message bridge contract
     * @param _executionManager Address of the execution manager contract
     */
    constructor(address _bridge, address _messageBridge, address _executionManager) {
        require(_bridge != address(0), "Invalid bridge address");
        require(_messageBridge != address(0), "Invalid message bridge address");
        require(_executionManager != address(0), "Invalid execution manager address");
        bridge = INativeBridgeExtended(_bridge);
        messageBridge = IMessageBridge(_messageBridge);
        executionManager = _executionManager;
    }

    /**
     * @notice Initiates the full bridge flow:
     *         1. Bridges GAS to N3
     *         2. Sends Oracle call through message bridge
     * @param _toN3Address The N3 address (Hash160) to receive the GAS, as an EVM address
     *                     Note: N3 addresses are 20 bytes, same as EVM addresses
     * @param _gasAmount The amount of GAS to bridge (in wei)
     * @param _maxBridgeFee Maximum fee willing to pay for bridge withdrawal
     * @param _serializedOracleCall Pre-serialized NeoMethodCall bytes for the Oracle request
     *                              (must contain exactly 5 args: url, filter, callbackContract,
     *                               callbackMethod, gasForResponse — nonce and requestId are
     *                               appended here automatically)
     * @param _maxMessageFee Maximum fee willing to pay for message sending
     * @param _storeResult Whether to store the execution result
     * @return messageNonce The nonce of the sent message
     * @return requestId    The oracle request ID assigned by this contract (starts at 0)
     */
    function initiateOracleCall(
        address _toN3Address,
        uint256 _gasAmount,
        uint256 _maxBridgeFee,
        bytes calldata _serializedOracleCall,
        uint256 _maxMessageFee,
        bool _storeResult
    ) external payable returns (uint256 messageNonce, uint256 requestId) {
        require(msg.value >= _gasAmount + _maxBridgeFee + _maxMessageFee, "Insufficient value");

        // Assign a new request ID (starts at 0, increments per call)
        requestId = requestIdCounter++;

        // Get the current withdrawal nonce (will be incremented by withdrawNative)
        uint256 currentWithdrawalNonce = bridge.nativeBridge().withdrawalState.nonce;
        uint256 withdrawalNonce = currentWithdrawalNonce + 1;

        // Step 1: Bridge GAS to N3
        bridge.withdrawNative{value: _gasAmount + _maxBridgeFee}(_toN3Address, _maxBridgeFee);

        // Append withdrawal nonce then requestId to the pre-serialized call.
        // After appending the N3 signature is:
        //   requestOracleData(url, filter, callbackContract, callbackMethod, gasForResponse, nonce, requestId)
        bytes memory enrichedCall = NeoSerializerLib.appendArgToCall(
            NeoSerializerLib.appendArgToCall(
                bytes(_serializedOracleCall),
                NeoSerializerLib.serialize(withdrawalNonce)
            ),
            NeoSerializerLib.serialize(requestId)
        );

        // Step 2: Send Oracle call through message bridge
        messageNonce = messageBridge.sendExecutableMessage{value: _maxMessageFee}(
            enrichedCall,
            _storeResult
        );

        emit OracleCallInitiated(requestId, withdrawalNonce, messageNonce, msg.sender, enrichedCall);
    }

    /**
     * @notice Called by the EVM message bridge when the N3 oracle result message is executed.
     *         Bridgeman builds an ABI-encoded Call targeting this function with the request ID
     *         and raw oracle result bytes, then forwards it through the N3→EVM message bridge
     *         as an executable message.
     * @param _requestId    The oracle request ID on the N3 side
     * @param _oracleResult The raw oracle response bytes (UTF-8 JSON from the Oracle)
     */
    function onOracleResult(uint256 _requestId, bytes calldata _oracleResult) external {
        // Allow execution from MessageBridge or ExecutionManager (which executes on behalf of MessageBridge)
        //quire(
        //  msg.sender == address(messageBridge) || 
        //  msg.sender == executionManager || 
        //  msg.sender == address(0), 
        //  "Only message bridge execution"
        //

        oracleResults[_requestId] = _oracleResult;
        hasResult[_requestId] = true;

        emit OracleResultReceived(_requestId, _oracleResult);
    }

    /**
     * @notice Get the stored Oracle result for a request ID
     * @param _requestId The oracle request ID
     * @return result The Oracle result bytes
     * @return exists Whether a result exists for this request ID
     */
    function getOracleResult(uint256 _requestId)
        external
        view
        returns (bytes memory result, bool exists)
    {
        result = oracleResults[_requestId];
        exists = hasResult[_requestId];
    }

    /**
     * @notice Check if a result has been received for a request ID
     * @param _requestId The oracle request ID
     * @return True if result exists
     */
    function hasOracleResult(uint256 _requestId) external view returns (bool) {
        return hasResult[_requestId];
    }
}
