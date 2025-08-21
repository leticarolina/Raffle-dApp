// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {HelperConfig, CodeConstants} from "../../script/HelperConfig.s.sol"; // Contract to get network-specific settings
import {Vm} from "forge-std/Vm.sol"; // Import the Vm contract for logging and testing events
import {VRFCoordinatorV2_5Mock} from "@chainlink/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol"; //This is the mock contract for Chainlink VRF
import {WinnerCannotReceiveEth} from "../mocks/WinnerCannotReceiveEth.sol"; // Used to test the customer error Raffle__transferFailed() when sending ETH to a winner that does not accept it
import {BaseTest} from "../utils/BaseTest.sol"; // Setup function for finding the requestId from the logs

contract Integration is Test, CodeConstants, BaseTest {
    Raffle public raffle;
    HelperConfig public helperConfig;

    //mock player
    address public PLAYER = makeAddr("player_leticia");
    uint256 public STARTING_BALANCE = 1 ether;

    // mock variables
    uint256 entranceFee;
    uint256 interval;

    //mock chainlink vrf variables
    address vrfCoordinator;
    bytes32 keyHash;
    uint256 subscriptionId;
    uint32 callbackGasLimit;

    address linkToken;
    uint256 account;

    event RaffleEntered(address indexed player, uint256 amount);
    event WinnerPicked(address indexed winner);

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        keyHash = config.keyHash;
        callbackGasLimit = config.callbackGasLimit;
        subscriptionId = config.subscriptionId;
        linkToken = config.token;
        account = config.account;

        vm.deal(PLAYER, STARTING_BALANCE);
    }

    modifier raffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1); // advances block height
        _;
    }
    modifier raffleEntered() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        _;
    }

    modifier onlyLocal() {
        if (block.chainid != CodeConstants.LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                          PERFORM UPKEEP
    //////////////////////////////////////////////////////////////*/

    // it checks the event emitted by performUpkeep and using vm.recordLogs() to get the requestId
    function test_performUpkeep_UpdateStateToCalculatingAndEmitsRequestId()
        public
        raffleEnteredAndTimePassed
    {
        // Arrange: raffleEnteredAndTimePassed

        // Act
        vm.recordLogs(); // this tells Foundry: “start capturing all EVM logs (events) emitted until I call vm.getRecordedLogs().” records all the logs that happen during the next call
        raffle.performUpkeep(""); // calls the VRF coordinator mock > mock emits its own events (e.g., RandomWordsRequested) , my contract emits RequestedRaffleWinner(requestId)

        //vm.getRecordedLogs() returns an array of all logs emitted during that call (both from my contract and from the coordinator mock)
        Vm.Log[] memory entries = vm.getRecordedLogs(); // get the recorded logs on the last call
        // bytes32 lastEntryRequestId = entries[1].topics[1]; // topics is the array of indexed parameters, so we get the second topic which is the requestId, topics[0] is the event signature, topics[1] is the first indexed parameter, etc.
        //Why entries[1]? Because the first log (entries[0]) is usually from the VRF mock (RandomWordsRequested), and the second log (entries[1]) is from my contract (RequestedRaffleWinner).

        //I have created a helper function in BaseTest.sol to find the requestId from the logs instead topics[1]
        uint256 lastEntryRequestId = _findVRFRequestIdFromCoordinatorLogs(
            entries,
            raffle.getVrfCoordinator()
        );

        // Assert
        Raffle.RaffleState raffleState = raffle.getRaffleState(); // get the new raffle state
        assert(bytes32(lastEntryRequestId) > 0); // assert that the requestId is greater than 0, meaning it was emitted
        assert(uint256(raffleState) == 1); // raffle state should be CALCULATING (1) because performUpkeep was called
    }

    /*//////////////////////////////////////////////////////////////
                          FULFILL RANDOM WORDS
    //////////////////////////////////////////////////////////////*/

    function test_fulfillRandomWords_canOnlyBeCalledAfterPerformUpkeep()
        public
        raffleEnteredAndTimePassed
        onlyLocal
    {
        //this is using a manually generated random requestId
        //A valid requestId exists only after raffle calls performUpkeep() and the coordinator accepts the request.
        //testing that fulfillRandomWords() can only be called after performUpkeep() has been called, and performUpkeep() has not been called yet
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            0, ///this is using a random requestId, fuzzing the input
            address(raffle) // consumer address
        );
    }

    function test_fulfillRandomWords_pickAWinner_resetStates_andTransferPrize()
        public
        raffleEntered
        onlyLocal
    {
        // Arrange
        address expectedWinner = address(1);
        uint256 additionalEntrants = 3; //4 players in total
        uint256 startingIndex = 1; // start from index 1 because index 0 is the PLAYER
        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrants;
            i++
        ) {
            address player = address(uint160(i)); //create a new player address and convert it to address type
            hoax(player, STARTING_BALANCE); //hoax will send 10 ether to each player address
            raffle.enterRaffle{value: entranceFee}(); // each player enters the raffle
        }

        uint256 startingTimeStamp = raffle.getLastTimeStamp(); // get the starting timestamp before we warp time
        uint256 winnerStartingBalance = expectedWinner.balance;
        vm.warp(block.timestamp + raffle.getInterval() + 1); // warp time so that the raffle can be drawn
        vm.roll(block.number + 1);

        // check that the raffle has enough funds to pay the winner
        {
            address coord = raffle.getVrfCoordinator();
            uint256 subId = raffle.getSubscriptionId();

            (uint96 linkBal, , , , ) = VRFCoordinatorV2_5Mock(coord)
                .getSubscription(subId);
            assertGt(linkBal, 0, "balance is zero");
        }

        vm.recordLogs();
        raffle.performUpkeep(""); // emits the event RequestedRaffleWinner(requestId)
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 requestId = _findVRFRequestIdFromCoordinatorLogs(
            logs,
            raffle.getVrfCoordinator()
        );

        // Pretend to be Chainlink VRF
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        // Assert
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        address recentWinner = raffle.getRecentWinner();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp(); // get the ending timestamp after the winner is picked
        uint256 prize = entranceFee * (additionalEntrants + 1); //prize is the entrance fee multiplied by the number of players (including the PLAYER) entranceFee * 4
        uint256 playersLength = raffle.getNumberOfPlayers(); // get the number of players

        assert(uint256(raffleState) == 0); // raffle state should be OPEN again
        assert(expectedWinner == recentWinner);
        assert(winnerBalance == winnerStartingBalance + prize); // winner balance should be increased by the prize amount
        assert(endingTimeStamp > startingTimeStamp); // ending timestamp should be greater than the starting timestamp
        assert(playersLength == 0); // players array should be reset
    }

    function test_fulfillRandomWords_reverts_whenWinnerRejectsPrize()
        public
        onlyLocal
    {
        WinnerCannotReceiveEth winner = new WinnerCannotReceiveEth();

        // Enter ONLY the unavailable winner so they’re index 0
        hoax(address(winner), STARTING_BALANCE);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + raffle.getInterval() + 1);
        vm.roll(block.number + 1);

        // Request randomness
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 requestId = _findVRFRequestIdFromCoordinatorLogs(
            logs,
            raffle.getVrfCoordinator()
        );

        VRFCoordinatorV2_5Mock(raffle.getVrfCoordinator()).fulfillRandomWords(
            requestId,
            address(raffle)
        );

        // payout failed -> raffle stayed CALCULATING
        assertEq(
            uint256(raffle.getRaffleState()),
            1,
            "should remain CALCULATING"
        );
    }
}
