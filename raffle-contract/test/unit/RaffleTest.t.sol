// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {HelperConfig, CodeConstants} from "../../script/HelperConfig.s.sol"; // Contract to get network-specific settings
import {Vm} from "forge-std/Vm.sol"; // Import the Vm contract for logging and testing events
import {VRFCoordinatorV2_5Mock} from "@chainlink/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol"; //This is the mock contract for Chainlink VRF
import {BaseTest} from "../utils/BaseTest.sol"; // Setup function for finding the requestId from the logs

contract RaffleTest is Test, CodeConstants, BaseTest {
    Raffle public raffle;
    HelperConfig public helperConfig;

    //mock player
    address public PLAYER = makeAddr("player_leticia"); //makeAddr creates a new address with a unique name
    uint256 public STARTING_BALANCE = 1 ether;

    // mock variables
    uint256 entranceFee;
    uint256 interval;

    //mock chainlink vrf variables
    address vrfCoordinator;
    bytes32 keyHash;
    uint256 subscriptionId;
    uint32 callbackGasLimit;

    address linkToken; // address of the mock token used to fund the VRF subscription
    uint256 account; // account used to deploy the contract and fund the subscription

    //events redeclared in the test file to use them with vm.expectEmit
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
        account = config.account; // get the account from the config

        vm.deal(PLAYER, STARTING_BALANCE); // give ETH to player
    }

    //modifier to enter the raffle and warp/foward time so that checkUpkeep returns true
    modifier raffleEnteredAndTimePassed() {
        // STEP 1: Player enters Raffles
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        // STEP 2: Fast-forward time and block number  (need this so checkUpkeep() returns true)
        vm.warp(block.timestamp + interval + 1);
        //skip(31); //also moves the block.timestamp 31 seconds forward but hardcoded
        vm.roll(block.number + 1); // advances block height
        //Together, they "fool" the contract into thinking conditions to pick a winner are met and PerformUpkeep can be called.
        _;
    }
    modifier raffleEntered() {
        //Player only enters the raffle, no time passed
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        _;
    }

    //this modifier is used to skip the fork test, so it only runs on local chain
    modifier onlyLocal() {
        if (block.chainid != CodeConstants.LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    //test_<unitUnderTest>_<stateOrCondition>_<expectedOutcome/Behaviour>

    /*//////////////////////////////////////////////////////////////
                           ENTER RAFFLE 
    //////////////////////////////////////////////////////////////*/
    function test_enterRaffle_RaffleStartsOpenState() public view {
        // Check that the raffle state is OPEN or basically the number 0, calculating refers to the number 1
        assertEq(
            uint256(raffle.getRaffleState()),
            uint256(Raffle.RaffleState.OPEN)
        );
    }

    function test_enterRaffle_reverts_whenRaffleStateIsCalculating()
        public
        raffleEnteredAndTimePassed
    {
        // after the player enters the raffle and time has passed, the raffle state should be CALCULATING
        raffle.performUpkeep(""); // this should flip state to CALCULATING

        //Assert: Expect a revert with custom error if someone tries to enter during CALCULATING
        vm.expectRevert(Raffle.Raffle__CalculatingRaffle.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}(); // this should now REVERT
    }

    function test_enterRaffle_reverts_whenPlayerEntersWithoutFee() public {
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle(); //player tries to enter without sending the entrance fee
    }

    function test_enterRaffle_reverts_whenPlayerEntersWithInsufficientFee()
        public
    {
        uint256 insufficienteFee = entranceFee - 0.005 ether;

        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle{value: insufficienteFee}();
    }
    function test_enterRaffle_recordsPlayerInTheArray_whenTheyEnterRaffle()
        public
    {
        //arrange
        vm.prank(PLAYER);
        //act
        raffle.enterRaffle{value: entranceFee}();
        //assert
        address playerRecorded = raffle.getPlayer(0);
        assertEq(playerRecorded, PLAYER);
    }
    function test_enterRaffle_emitsEvent_whenPlayerEntersRaffle() public {
        // Arrange
        vm.prank(PLAYER);
        // Act / Assert
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(PLAYER, entranceFee);
        raffle.enterRaffle{value: entranceFee}();
    }

    /*//////////////////////////////////////////////////////////////
                           CHECK UPKEEP
    //////////////////////////////////////////////////////////////*/
    function test_checkUpkeep_returnsFalse_ifContractHasNoBalanceOrPlayers()
        public
    {
        //arrange: assume the time has passed but no one has entered the raffle yet
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        //act: checkUpkeep() is called by the Chainlink Keeper to check if upkeep is needed
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        //assert: upkeepNeeded should be false because the contract has no balance
        assert(!upkeepNeeded);
    }
    function test_checkUpkeep_returnsFalse_ifRaffleIsNotOpen()
        public
        raffleEnteredAndTimePassed
    {
        // arrange: raffleEnteredAndTimePassed
        raffle.performUpkeep(""); // making it switch to CALCULATING state
        Raffle.RaffleState raffleState = raffle.getRaffleState(); // state should be: 1, CALCULATING
        //Enums belong to the contract where they’re declared, if want to reference an enum type/value from outside, must prefix it with the contract name not the instance name

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep(""); // checkUpkeep() is called by the Chainlink Keeper to check if upkeep is needed

        // Assert
        assert(raffleState == Raffle.RaffleState.CALCULATING);
        assert(upkeepNeeded == false); // upkeepNeeded should be false because the raffle is not open anymore
    }
    function test_checkUpkeep_returnsFalse_ifNotEnoughTimeHasPassed()
        public
        raffleEntered
    {
        //arrange - raffleEntered modifier
        skip(29); // skips only 29 seconds, so not enough time has passed

        //act - call checkUpkeep() to make sure it returns false
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        //assert
        assert(upkeepNeeded == false);
    }
    function test_checkUpkeep_returnsTrue_whenAllConditionsAreMet()
        public
        raffleEnteredAndTimePassed
    {
        //arrange - raffleEnteredAndTimePassed

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assertEq(upkeepNeeded, true);
    }
    /*//////////////////////////////////////////////////////////////
                          PERFORM UPKEEP
    //////////////////////////////////////////////////////////////*/
    function test_performUpkeep_canOnlyRun_whenCheckUpkeepReturnsTrue()
        public
        raffleEnteredAndTimePassed
    {
        // Arrange: raffleEnteredAndTimePassed

        //upkeepNeeded should be true, so performUpkeep can be called
        raffle.performUpkeep("");
    }
    function test_performUpkeep_reverts_whenCheckUpkeepReturnsFalse() public {
        uint256 currentBalance = 0; // no one has entered the raffle yet, so balance is 0
        uint256 currentPlayers = 0; // no players have entered yet
        Raffle.RaffleState currentRaffleState = raffle.getRaffleState(); // should be OPEN

        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance, // passing the 3 parameters that the error requires
                currentPlayers,
                uint256(currentRaffleState)
            )
        );
        raffle.performUpkeep(""); //this should REVERT since checkUpkeep() would return false, no players and no balance
    }

    /*//////////////////////////////////////////////////////////////
                        getTimeUntilNextDraw
    //////////////////////////////////////////////////////////////*/
    function test_getTimeUntilNextDraw_returnsPositive_beforeInterval()
        public
        view
    {
        // Fresh deployment starts OPEN, lastTimeStamp=block.timestamp
        uint256 remainingTime = raffle.getTimeUntilNextDraw();
        assertGt(remainingTime, 0); // just deployed, interval not passed yet
    }

    function test_getTimeUntilNextDraw_returnsZero_whenAfterInterval() public {
        vm.warp(block.timestamp + interval + 1); // warp time so that the interval has passed
        assertEq(raffle.getTimeUntilNextDraw(), 0); // after the interval has passed, it should return 0
    }

    /*//////////////////////////////////////////////////////////////
                          GETTERS
    //////////////////////////////////////////////////////////////*/
    function test_getters() public {
        assertEq(raffle.getEntranceFee(), entranceFee);
        assertEq(raffle.getInterval(), interval);
        assertEq(uint256(raffle.getRaffleState()), 0); // OPEN at start
        assertEq(raffle.getNumberOfPlayers(), 0);
        assertEq(raffle.getPlayers().length, 0);

        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        assertEq(raffle.getNumberOfPlayers(), 1);
        assertEq(raffle.getPlayer(0), PLAYER);
        assertEq(raffle.getNumOfWords(), 1);
    }
}
