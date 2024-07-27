// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Raffle} from "src/Raffle.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {console} from "forge-std/console.sol";
import {CodeConstants} from "script/HelperConfig.s.sol";

contract RaffleTest is CodeConstants, Test {
    Raffle public raffle;
    HelperConfig public helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane; // keyHas
    uint32 callbackGasLimit;
    uint256 subscriptionId;

    // make users for playing in the raffle
    address public PLAYER = makeAddr("player");
    uint256 public constant STARTNG_PLAYER_BALANCE = 10 ether;

    /**
     * Events
     */
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);

    function setUp() public {
        // deploy the contract
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        callbackGasLimit = config.callbackGasLimit;
        subscriptionId = config.subscriptionId;

        vm.deal(PLAYER, STARTNG_PLAYER_BALANCE); // give the player some mulla
    }

    function testRaffleInitialisesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }
    /*///////////////////////////////////////////////////////////////////////////////
    				ENTER RAFFLE								
    ///////////////////////////////////////////////////////////////////////////////*/

    function testRaffleRevertsWhenYouDontPayEnough() public {
        // Arrange
        vm.prank(PLAYER);
        // Act/Assert
        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector); // it will pass because we are expecting it to revert
        raffle.enterRaffle{value: 0}();
    }

    function testRaffleRecordsPlayersWhenTheyEnter() public {
        // Arrange
        vm.prank(PLAYER);
        // Act
        raffle.enterRaffle{value: entranceFee}();
        // Assert
        address playerRecorded = raffle.getPlayer(0);
        assertEq(playerRecorded, PLAYER);
    }

    function testEnteriingRaffleEmitsEvent() public {
        // Arrange
        vm.prank(PLAYER);
        // Act
        vm.expectEmit(true, false, false, false, address(raffle)); // tell foundry we expect to emit an event
        emit RaffleEntered(PLAYER); // this is the event we expect to emit
        // Assert
        raffle.enterRaffle{value: entranceFee}();
    }

    function testDontAllowPlayersToEnterWhleRaffleIIsCalculating() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        // we want to make sure enough time has passed to allow the raffle to be in calculating state
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1); // also move the block number forward
        raffle.performUpKeep(""); // this should set off the raffle state to CALCULATING
        // Act/ Assert
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector); // it should revert because the raffle is calculating
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}(); // should rever (and pass) because the raffle is calculating
    }

    /*///////////////////////////////////////////////////////////////////////////////
    				CHECK KEEP								
    ///////////////////////////////////////////////////////////////////////////////*/
    function testCheckUpKeepReturnsFalsefIItHasNoBalance() public {
        // Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1); // also move the block number forward
        // Act
        (bool upkeepNeeded,) = raffle.checkUpKeep("");
        // Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpKeepReturnsFalseifRaffleIsntOpen() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1); // also move the block number forward
        raffle.performUpKeep(""); // this should set off the raffle state to CALCULATING

        // Act
        (bool upkeepNeeded,) = raffle.checkUpKeep("");

        // Assert
        assert(upkeepNeeded == false);
    }

    // TO DO:
    // testCheckpKeepReturnsFalseIIfEnoughTimeHasPassed
    // testCheckUpkeepReturnsTrueWhenParametersAreGood

    /*////////////////////////////////////////////////////////////////////////////// 
                                      PERFORM PKEEP                                  
    ////////////////////////////////////////////////////////////////////////////////*/
    function testPerformUpkeepCanOnlyBeRunIfCheckUpkeepIsTrue() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1); // also move the block number forward

        // Act / Assert
        raffle.performUpKeep(""); // if this failes the whole test fails
            // (bool upkeepNeeded,) = raffle.checkUpKeep("");
            // assertEq(upkeepNeeded, true);
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState raffleState = raffle.getRaffleState();

        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        currentBalance = currentBalance + entranceFee;
        numPlayers = 1;

        // Act / Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, numPlayers, uint256(raffleState)
            )
        );
        raffle.performUpKeep("");
    }

    // tired of repeating this
    modifier raffleEntered() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    // What if we need to get emitted data into tests
    function testPerformUpkeepUpdateRaffleStateAndEmitsRequestId() public raffleEntered {
        // Act
        vm.recordLogs();
        raffle.performUpKeep("");
        // all the events that were recorded from `perfomUpKeep` store them in an array
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        // Assert
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0); // assert thaere was a request ID that's not blank
        // assert(raffleState == Raffle.RaffleState.CALCULATING);
        assert(uint256(raffleState) == 1);
    }

    /*////////////////////////////////////////////////////////////////////////////// 
        FULLFIILL RANDOM WORDS - RANDOM NUMBER GENARATOR                                  
    ////////////////////////////////////////////////////////////////////////////////*/

    modifier skipFork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    function testFulfillrandomWordsCanOnlyBeCalledAfterPerformUpKeep(uint256 randomRequestId)
        public
        raffleEntered
        skipFork
    {
        // From VRFCoordinatorV2_5Mock.sol
        //     if (s_subscriptionConfigs[subId].owner == address(0)) {
        //         revert UnknownSubscription();

        // Arrange / Act / Assert
        // should get a different random request Id eact time
        // change the number of tests in foundry.toml
        console.log("randomRequestId: ", randomRequestId); // test for fuzzing
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
    }
    // This is an end to end test of some sort

    function testFulfillRandomWordsPicksWinnerResetsAndSendsMoney() public raffleEntered skipFork {
        // Arrange
        uint256 additionalEntrants = 3; // 4 people in the raffle
        uint256 startingIndex = 1;
        address expectedWinner = address(1);

        for (uint256 i = startingIndex; i < startingIndex + additionalEntrants; i++) {
            address newPlayer = address(uint160(i));
            hoax(newPlayer, 1 ether); // sets a prank and gives them some ether
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        console.log("startingTimeStamp: ", startingTimeStamp);
        uint256 winnerStartingBalance = expectedWinner.balance;

        // Act
        vm.recordLogs();
        raffle.performUpKeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        // Simuulating getting the random number back from ChainLink usiing the Mock
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle)); // this should give a random number to our raffle

        // Assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;

        //vm.sleep(10000);
        // uint256 endingTimeStamp = raffle.getLastTimeStamp();
        // uint256 endingTimeStamp = vm.getBlockTimestamp()
        uint256 endingTimeStamp = block.timestamp;

        console.log("endingTimeStamp: ", endingTimeStamp);
        uint256 prize = entranceFee * (additionalEntrants + 1);

        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == winnerStartingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
    }
}
