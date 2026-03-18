// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {INativeBridgeExtended} from "../interfaces/INativeBridgeExtended.sol";
import {StorageTypes} from "../libraries/StorageTypes.sol";
import {BridgeLib} from "../libraries/BridgeLib.sol";

contract MockNativeBridgeExtended is INativeBridgeExtended {
    StorageTypes.NativeBridge private _nativeBridge;

    constructor(uint256 initialWithdrawalNonce) {
        _nativeBridge.withdrawalState.nonce = initialWithdrawalNonce;
    }

    function nativeBridge() external view returns (StorageTypes.NativeBridge memory) {
        return _nativeBridge;
    }

    function withdrawNative(address, uint256) external payable {
        unchecked {
            _nativeBridge.withdrawalState.nonce += 1;
        }
    }

    // ---- Unused INativeBridge methods (stubs) ----
    function nativeBridgeIsSet() external pure returns (bool) {
        return true;
    }

    function setNativeBridge(uint256, uint256, uint256, uint256, uint256, uint256) external pure {
        revert("not implemented");
    }

    function pauseNativeBridge() external pure {
        revert("not implemented");
    }

    function unpauseNativeBridge() external pure {
        revert("not implemented");
    }

    function depositNative(bytes32, BridgeLib.Signature[] calldata, BridgeLib.DepositData[] calldata) external pure {
        revert("not implemented");
    }

    function claimNative(uint256) external pure {
        revert("not implemented");
    }

    function setNativeWithdrawalFee(uint256) external pure {
        revert("not implemented");
    }

    function setMinNativeWithdrawalAmount(uint256) external pure {
        revert("not implemented");
    }

    function setMaxNativeWithdrawalAmount(uint256) external pure {
        revert("not implemented");
    }

    function setMaxNativeDeposits(uint256) external pure {
        revert("not implemented");
    }
}

