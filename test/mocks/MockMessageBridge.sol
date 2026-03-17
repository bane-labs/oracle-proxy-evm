// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.25;

import {IMessageBridge} from "../../contracts/messageBridge/interfaces/IMessageBridge.sol";
import {AMBTypes} from "../../contracts/libraries/AMBTypes.sol";
import {AMBStorage} from "../../contracts/messageBridge/AMBStorage.sol";
import {BridgeLib} from "../../contracts/libraries/BridgeLib.sol";

/**
 * @title MockMessageBridge
 * @notice Minimal mock of IMessageBridge for testing OracleProxy.
 */
contract MockMessageBridge is IMessageBridge {
    uint256 public messageNonce;

    mapping(uint256 => AMBStorage.StoredMessage) private _storedMessages;

    // ── IMessageBridge (key function) ────────────────────────────────────────

    function sendExecutableMessage(
        bytes calldata,
        bool
    ) external payable override returns (uint256 nonce) {
        nonce = ++messageNonce;
    }

    // ── Test helpers ─────────────────────────────────────────────────────────

    function setStoredMessage(uint256 nonce, bytes calldata encodedMetadata, bytes calldata rawMessage) external {
        _storedMessages[nonce] = AMBStorage.StoredMessage({
            encodedMetadata: encodedMetadata,
            rawMessage: rawMessage
        });
    }

    function getEvmMessage(uint256 nonce) external view returns (AMBStorage.StoredMessage memory) {
        return _storedMessages[nonce];
    }

    // ── Stubs ────────────────────────────────────────────────────────────────

    function pause() external override {}
    function unpause() external override {}
    function pauseSending() external override {}
    function unpauseSending() external override {}
    function pauseExecuting() external override {}
    function unpauseExecuting() external override {}

    function getExecutableState(uint256) external pure override
        returns (AMBStorage.ExecutableState memory)
    {
        return AMBStorage.ExecutableState({ executed: false, expirationTimestamp: 0 });
    }

    function sendStoreOnlyMessage(bytes calldata) external payable override returns (uint256) {
        return ++messageNonce;
    }

    function sendResultMessage(uint256) external payable override returns (uint256) {
        return ++messageNonce;
    }

    function getEvmExecutionResult(uint256) external pure override
        returns (AMBTypes.Result memory)
    {
        return AMBTypes.Result({ success: false, returnData: "" });
    }

    function getNeoExecutionResult(uint256) external pure override returns (bytes memory) {
        return "";
    }

    function storeMessages(
        bytes32,
        BridgeLib.Signature[] calldata,
        AMBTypes.MessageData[] calldata
    ) external override {}

    function executeMessage(uint256) external payable override returns (AMBTypes.Result memory) {
        return AMBTypes.Result({ success: false, returnData: "" });
    }

    function setSendingFee(uint256) external override {}
    function setMaxMessageSize(uint256) external override {}
    function setMaxNrMessages(uint256) external override {}
    function setExecutionManager(address) external override {}
    function setExecutionWindowSeconds(uint256) external override {}
}
