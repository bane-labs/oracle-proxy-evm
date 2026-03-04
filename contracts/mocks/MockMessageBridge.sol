// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.25;

import {IMessageBridge} from "../messageBridge/interfaces/IMessageBridge.sol";
import {AMBTypes} from "../libraries/AMBTypes.sol";
import {AMBStorage} from "../messageBridge/AMBStorage.sol";
import {BridgeLib} from "../libraries/BridgeLib.sol";

/**
 * @title MockMessageBridge
 * @notice Minimal mock of IMessageBridge for testing OracleProxy.
 */
contract MockMessageBridge is IMessageBridge {
    uint256 public messageNonce;

    // ── IMessageBridge (key function) ────────────────────────────────────────

    function sendExecutableMessage(
        bytes calldata,
        bool
    ) external payable override returns (uint256 nonce) {
        nonce = ++messageNonce;
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
