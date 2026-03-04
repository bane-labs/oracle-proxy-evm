// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.25;

import {INativeBridgeExtended} from "../../contracts/interfaces/INativeBridgeExtended.sol";
import {StorageTypes} from "../../contracts/libraries/StorageTypes.sol";
import {BridgeLib} from "../../contracts/libraries/BridgeLib.sol";

/**
 * @title MockNativeBridge
 * @notice Minimal mock of INativeBridgeExtended for testing OracleProxy.
 */
contract MockNativeBridge is INativeBridgeExtended {
    uint256 public withdrawalNonce;

    constructor(uint256 _initialNonce) {
        withdrawalNonce = _initialNonce;
    }

    // ── INativeBridgeExtended ────────────────────────────────────────────────

    function nativeBridge() external view override returns (StorageTypes.NativeBridge memory) {
        StorageTypes.State memory depositState;
        StorageTypes.State memory withdrawalState;
        withdrawalState.nonce = withdrawalNonce;
        StorageTypes.NativeConfig memory config;
        return StorageTypes.NativeBridge({
            paused: false,
            depositState: depositState,
            withdrawalState: withdrawalState,
            config: config
        });
    }

    // ── INativeBridge ────────────────────────────────────────────────────────

    function withdrawNative(address /*_to*/, uint256 /*_maxFee*/) external payable override {
        withdrawalNonce++;
    }

    // ── Stubs (unused by OracleProxy) ────────────────────────────────────────

    function nativeBridgeIsSet() external pure override returns (bool) { return true; }

    function setNativeBridge(
        uint256, uint256, uint256, uint256, uint256, uint256
    ) external override {}

    function pauseNativeBridge() external override {}
    function unpauseNativeBridge() external override {}

    function depositNative(
        bytes32,
        BridgeLib.Signature[] calldata,
        BridgeLib.DepositData[] calldata
    ) external override {}

    function claimNative(uint256) external override {}
    function setNativeWithdrawalFee(uint256) external override {}
    function setMinNativeWithdrawalAmount(uint256) external override {}
    function setMaxNativeWithdrawalAmount(uint256) external override {}
    function setMaxNativeDeposits(uint256) external override {}
}
