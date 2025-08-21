// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import {Script, console} from "forge-std/Script.sol";
import {CodeConstants, HelperConfig} from "./HelperConfig.s.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "../test/mocks/TokenToFundVRF.sol";
import {DevOpsTools} from "../lib/foundry-devops/src/DevOpsTools.sol";

/*//////////////////////////////////////////////////////////////
                           CREATE SUBSCRIPTION
    //////////////////////////////////////////////////////////////*/
// This is a script to create a Chainlink VRF subscription and fund it with tokens
// It can be used to create a subscription for Chainlink VRF on any network, including local development networks.
contract CreateSubscription is Script {
    function createSubscriptionUsingConfig() public returns (uint256, address) {
        HelperConfig helperConfig = new HelperConfig(); //deploying a new instance of the HelperConfig contract in the script environment
        uint256 account = helperConfig
            .getConfigByChainId(block.chainid)
            .account; // get the account from the config
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator; // calling the getConfig() function from the helperConfig instance, which returns a NetworkConfig struct with all your network-specific settings (entranceFee, interval, etc).

        return createSubscription(vrfCoordinator, account); // return the subscription ID and VRF Coordinator address
    }

    function createSubscription(
        address vrfCoordinator,
        uint256 account
    ) public returns (uint256, address) {
        vm.startBroadcast(account);
        uint256 subId = VRFCoordinatorV2_5Mock(vrfCoordinator)
            .createSubscription();
        vm.stopBroadcast();

        return (subId, vrfCoordinator);
    }

    function run() external returns (uint256, address) {
        return createSubscriptionUsingConfig();
    }
}

/*//////////////////////////////////////////////////////////////
                           FUND SUBSCRIPTION
    //////////////////////////////////////////////////////////////*/
// This script is used to fund the Chainlink VRF subscription with LINK tokens
// It can be used to fund the subscription on any network, including local development networks.
contract FundSubscription is Script {
    uint96 public constant FUND_AMOUNT = 0.03 ether; // Amount of LINK tokens to fund the subscription with

    function fundSubscriptionUsingConfig() public payable {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        uint256 subscriptionId = helperConfig.getConfig().subscriptionId;
        address linkToken = helperConfig.getConfig().token;
        uint256 account = helperConfig.getConfig().account; // get the account from the config

        if (subscriptionId == 0) {
            CreateSubscription createSub = new CreateSubscription();
            (uint256 updatedSubId, address updatedVRFv2) = createSub.run();
            subscriptionId = updatedSubId;
            vrfCoordinator = updatedVRFv2;
        }

        fundSubscription(vrfCoordinator, subscriptionId, linkToken, account);
    }

    function fundSubscription(
        address vrfCoordinator,
        uint256 subscriptionId,
        address linkToken,
        uint256 account
    ) public payable {
        if (block.chainid == 31337) {
            vm.startBroadcast(account);

            VRFCoordinatorV2_5Mock(vrfCoordinator).fundSubscription(
                subscriptionId,
                FUND_AMOUNT
            );

            vm.stopBroadcast();
        } else {
            vm.startBroadcast();
            LinkToken(linkToken).transferAndCall(
                vrfCoordinator,
                FUND_AMOUNT,
                abi.encode(subscriptionId)
            );
            vm.stopBroadcast();
        }
    }

    function run() external {
        fundSubscriptionUsingConfig();
    }
}

/*//////////////////////////////////////////////////////////////
                           ADDING CONSUMER
    //////////////////////////////////////////////////////////////*/
// This script is used to add a consumer to the Chainlink VRF subscription
contract AddConsumer is Script {
    function addConsumer(
        address raffle,
        address vrfCoordinator,
        uint256 subscriptionId,
        uint256 account
    ) public {
        vm.startBroadcast(account);
        VRFCoordinatorV2_5Mock(vrfCoordinator).addConsumer(
            subscriptionId,
            raffle
        );
        vm.stopBroadcast();
    }

    function addConsumerUsingConfig(address raffle) public {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        uint256 subscriptionId = helperConfig.getConfig().subscriptionId;
        uint256 account = helperConfig.getConfig().account; // get the account from the config

        addConsumer(raffle, vrfCoordinator, subscriptionId, account);
    }

    function run() external {
        address raffle = DevOpsTools.get_most_recent_deployment(
            "Raffle",
            block.chainid
        );
        addConsumerUsingConfig(raffle);
    }
}
