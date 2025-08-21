// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//this contract is used to test the customer error Raffle__transferFailed() when sending ETH to a winner that does not accept it
contract WinnerCannotReceiveEth {
    receive() external payable {
        revert("test"); // Any ETH sent will revert
    }
}
