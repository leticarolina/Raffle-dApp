// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {Test, Vm} from "forge-std/Test.sol";

abstract contract BaseTest is Test {
    // This function extracts the VRF request ID from the logs emitted by the VRFCoordinatorV2_5Mock contract
    // It scans the logs in reverse order to find the most recent RandomWordsRequested event
    // and decodes the request ID from the event data.
    // Helper: safely parse requestId from coordinator's RandomWordsRequested log

    function _findVRFRequestIdFromCoordinatorLogs(
        Vm.Log[] memory logs,
        address coordinator
    ) internal pure returns (uint256) {
        bytes32 sig = keccak256(
            "RandomWordsRequested(bytes32,uint256,uint256,uint256,uint16,uint32,uint32,bytes,address)"
        );
        for (uint256 i = logs.length; i > 0; i--) {
            Vm.Log memory log = logs[i - 1];
            if (log.emitter != coordinator) continue;
            if (log.topics.length == 0 || log.topics[0] != sig) continue;
            (uint256 requestId, , , , , ) = abi.decode(
                log.data,
                (uint256, uint256, uint16, uint32, uint32, bytes)
            );
            return requestId;
        }
        return 0;
    }
}
