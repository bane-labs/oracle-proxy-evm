// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {INativeBridge} from "./INativeBridge.sol";
import {StorageTypes} from "../libraries/StorageTypes.sol";

/**
 * @title INativeBridgeExtended
 * @notice Extended interface for NativeBridge that includes access to the nativeBridge storage getter
 * @dev This interface extends INativeBridge to expose the public nativeBridge storage variable
 *      which allows reading the withdrawal state including the nonce
 */
interface INativeBridgeExtended is INativeBridge {
    /**
     * @notice Returns the native bridge storage struct
     * @return The NativeBridge struct containing paused state, deposit state, withdrawal state, and config
     */
    function nativeBridge() external view returns (StorageTypes.NativeBridge memory);
}
