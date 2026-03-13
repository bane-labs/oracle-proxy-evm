// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.25;

import {INativeBridgeExtended} from "./interfaces/INativeBridgeExtended.sol";
import {IMessageBridge} from "./messageBridge/interfaces/IMessageBridge.sol";
import {NeoSerializerLib} from "./libraries/NeoSerializerLib.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title OracleProxy
 * @notice Example contract demonstrating the full bridge flow:
 *         1. Bridge GAS from NeoX to N3 using native bridge
 *         2. Send Oracle call through message bridge
 *         3. Receive and store Oracle result
 * @dev Upgradeable via UUPS proxy pattern. Ownership is required to authorize upgrades.
 */
contract OracleProxy is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    INativeBridgeExtended public bridge;
    IMessageBridge public messageBridge;
    address public executionManager;
    address public n3OracleProxyAddress;

    // Mapping from oracle request ID to oracle result
    mapping(uint256 => string) public oracleResults;

    // Mapping from oracle request ID to oracle response code
    mapping(uint256 => uint256) public oracleResponseCodes;

    // Mapping from oracle request ID to whether result has been received
    mapping(uint256 => bool) public hasResult;

    // Auto-incrementing request ID counter; first ID = 0
    uint256 public requestIdCounter;

    // subsidized gas storage
    uint256 public subsidizedGas;

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
        uint256 responseCode,
        string result
    );

    event ExecutionManagerUpdated(address indexed oldExecutionManager, address indexed newExecutionManager);
    event N3OracleProxyAddressUpdated(address indexed oldN3OracleProxyAddress, address indexed newN3OracleProxyAddress);
    event BridgeUpdated(address indexed oldBridge, address indexed newBridge);
    event MessageBridgeUpdated(address indexed oldMessageBridge, address indexed newMessageBridge);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializer (replaces constructor for upgradeable contracts)
     * @param _bridge Address of the native bridge contract
     * @param _messageBridge Address of the message bridge contract
     * @param _executionManager Address of the execution manager contract
     * @param _owner Address to set as the contract owner
     */
    function initialize(
        address _bridge,
        address _messageBridge,
        address _executionManager,
        address _n3OracleProxyAddress,
        address _owner
    ) external initializer {
        require(_bridge != address(0), "Invalid bridge address");
        require(_messageBridge != address(0), "Invalid message bridge address");
        require(_executionManager != address(0), "Invalid execution manager address");
        require(_n3OracleProxyAddress != address(0), "Invalid N3 oracle proxy address");

        __Ownable_init(_owner);

        bridge = INativeBridgeExtended(_bridge);
        messageBridge = IMessageBridge(_messageBridge);
        executionManager = _executionManager;
        n3OracleProxyAddress = _n3OracleProxyAddress;
        subsidizedGas = 1e17; // 0.1 GAS
    }

    /**
     * @notice Initiates the full bridge flow:
     *         1. Bridges GAS to N3
     *         2. Sends Oracle call through message bridge
     * @param _maxBridgeFee Maximum fee willing to pay for bridge withdrawal
     * @param _serializedOracleCall Pre-serialized NeoMethodCall bytes for the Oracle request
     *                              (must contain exactly 4 args: url, filter, callbackContract,
     *                               callbackMethod — gasForOracle, gasOracleRequestExec,
     *                               gasOracleResponseReturn, nonce, and requestId are appended
     *                               here automatically)
     * @param _gasForOracle Gas allocated for the Oracle node (must be > 0.1 GAS and <= _gasOracleRequestExec)
     * @param _gasOracleRequestExec Gas for Oracle request execution on N3
     * @param _gasOracleResponseReturn Gas for returning Oracle response to EVM
     * @param _maxMessageFee Maximum fee willing to pay for message sending
     * @param _storeResult Whether to store the execution result
     * @return messageNonce The nonce of the sent message
     * @return requestId    The oracle request ID assigned by this contract (starts at 0)
     */
    function initiateOracleCall(
        uint256 _maxBridgeFee,
        bytes calldata _serializedOracleCall,
	    uint256 _gasForOracle,
	    uint256 _gasOracleRequestExec,
	    uint256 _gasOracleResponseReturn,
        uint256 _maxMessageFee,
        bool _storeResult
    ) external payable returns (uint256 messageNonce, uint256 requestId) {
	    require(_gasForOracle <= _gasOracleRequestExec, "gasForOracle must be <= gasOracleRequestExec");
	    require(_gasForOracle > 1e17, "gasForOracle must be > 0.1 GAS"); 
	    require(msg.value >= (_gasOracleRequestExec + _gasOracleResponseReturn + _maxBridgeFee + _maxMessageFee) - subsidizedGas,
        "Insufficient value for gas and fees");

        // Assign a new request ID (starts at 0, increments per call)
        requestId = requestIdCounter++;

        // Get the current withdrawal nonce (will be incremented by withdrawNative)
        uint256 currentWithdrawalNonce = bridge.nativeBridge().withdrawalState.nonce;
        uint256 withdrawalNonce = currentWithdrawalNonce + 1;
	    uint256 gasToBridge = (_gasOracleRequestExec + _gasOracleResponseReturn + _maxBridgeFee + _maxMessageFee) - subsidizedGas;
        // Step 1: Bridge GAS to N3
        bridge.withdrawNative{value: gasToBridge }(n3OracleProxyAddress, _maxBridgeFee);

        // Append gas params, withdrawal nonce, and requestId to the pre-serialized call.
        // After appending the N3 signature is:
        //   requestOracleData(url, filter, callbackContract, callbackMethod,
        //                     gasForOracle, gasOracleRequestExec, gasOracleResponseReturn, nonce, requestId)
        bytes memory enrichedCall = bytes(_serializedOracleCall);
        enrichedCall = NeoSerializerLib.appendArgToCall(enrichedCall, NeoSerializerLib.serialize(_gasForOracle));
        enrichedCall = NeoSerializerLib.appendArgToCall(enrichedCall, NeoSerializerLib.serialize(_gasOracleRequestExec));
        enrichedCall = NeoSerializerLib.appendArgToCall(enrichedCall, NeoSerializerLib.serialize(_gasOracleResponseReturn));
        enrichedCall = NeoSerializerLib.appendArgToCall(enrichedCall, NeoSerializerLib.serialize(withdrawalNonce));
        enrichedCall = NeoSerializerLib.appendArgToCall(enrichedCall, NeoSerializerLib.serialize(requestId));

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
     * @param responseCode  The oracle response code (e.g., 0x00 = Success)
     * @param _oracleResult The oracle response string (UTF-8 JSON from the Oracle)
     */
    function onOracleResult(uint256 _requestId, uint256 responseCode, string calldata _oracleResult) external {
        // Allow execution from MessageBridge or ExecutionManager (which executes on behalf of MessageBridge)
        require(
            msg.sender == executionManager,
            "Only message bridge execution"
        );

        oracleResults[_requestId] = _oracleResult;
        oracleResponseCodes[_requestId] = responseCode;
        hasResult[_requestId] = true;

        emit OracleResultReceived(_requestId, responseCode, _oracleResult);
    }

    /**
     * @notice Get the stored Oracle result for a request ID
     * @param _requestId The oracle request ID
     * @return result The Oracle result string
     * @return responseCode The Oracle response code
     * @return exists Whether a result exists for this request ID
     */
    function getOracleResult(uint256 _requestId)
        external
        view
        returns (string memory result, uint256 responseCode, bool exists)
    {
        result = oracleResults[_requestId];
        responseCode = oracleResponseCodes[_requestId];
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

    function setSubsidizedGas(uint256 _subsidizedGas) external onlyOwner {
        require(_subsidizedGas > 0, "Subsidized gas must be greater than 0");
        subsidizedGas = _subsidizedGas;
    }
    
    function setN3OracleProxyAddress(address _n3OracleProxyAddress) external onlyOwner {
        require(_n3OracleProxyAddress != address(0), "Invalid N3 oracle proxy address");
        address oldN3OracleProxyAddress = n3OracleProxyAddress;
        n3OracleProxyAddress = _n3OracleProxyAddress;
        emit N3OracleProxyAddressUpdated(oldN3OracleProxyAddress, _n3OracleProxyAddress);
    }

    /**
     * @notice Update the execution manager address
     * @param _executionManager The new execution manager address
     * @dev Only callable by the owner
     */
    function setExecutionManager(address _executionManager) external onlyOwner {
        require(_executionManager != address(0), "Invalid execution manager address");
        address oldExecutionManager = executionManager;
        executionManager = _executionManager;
        emit ExecutionManagerUpdated(oldExecutionManager, _executionManager);
    }

    /**
     * @notice Update the bridge address
     * @param _bridge The new bridge address
     * @dev Only callable by the owner
     */
    function setBridge(address _bridge) external onlyOwner {
        require(_bridge != address(0), "Invalid bridge address");
        address oldBridge = address(bridge);
        bridge = INativeBridgeExtended(_bridge);
        emit BridgeUpdated(oldBridge, _bridge);
    }

    /**
     * @notice Update the message bridge address
     * @param _messageBridge The new message bridge address
     * @dev Only callable by the owner
     */
    function setMessageBridge(address _messageBridge) external onlyOwner {
        require(_messageBridge != address(0), "Invalid message bridge address");
        address oldMessageBridge = address(messageBridge);
        messageBridge = IMessageBridge(_messageBridge);
        emit MessageBridgeUpdated(oldMessageBridge, _messageBridge);
    }

    /**
     * @notice Authorizes contract upgrades. Only the owner can upgrade.
     * @dev Required by UUPSUpgradeable.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
