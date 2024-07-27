// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title Raffle - Simple raffle contract
 * @author Antony Mapfumo
 * @notice This is a simple contract for a raffle
 * @dev This contract is not audited. This contract implements Chainlink VRFv2.5
 */
contract Raffle is VRFConsumerBaseV2Plus {
    // Custom errors
    error Raffle__SendMoreToEnterRaffle();
    error Raffle__NotEnoughTimePassed();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 balance, uint256 playersLength, uint256 raffleState);

    /* Type Declarations */
    // keep track of the Raffle state
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    /* State Variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    // "i" for mmutable. immutables are gas efficient
    uint256 private immutable i_entranceFee;
    // @dev the duration of the lottery in secondss
    uint256 private immutable i_interval; // interval between pickWinner() calls
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /**
     * Events
     */
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane, // keyHas
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        // Since we inheriiting from VRFConsumerBaseV2Plus, we also need to pass parameters to its constructor
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        // as of Solidity 0.8.4 you can use use custom errors like "error NotEnoughETH()"
        // require(msg.value == i_entranceFee, "Not enough ETH sent!");
        // storing the above error message as a strng costs a lot of gas
        // so we can use a custom error instead
        // custom errors are gas efficient
        if (msg.value < i_entranceFee) {
            revert Raffle__SendMoreToEnterRaffle();
        }

        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        // push the player to the players array
        s_players.push(payable(msg.sender));
        // there's a rule of thumb whenver we up date a storage variable, emit an event
        // 1. Make miigration easier
        // 2. Makes frond end "indexing" easier
        emit RaffleEntered(msg.sender); // emit an event
    }

    /* when should the winner be picked 
     * @dev This is the function that the Chainlink wiill call to see
     * if the lottery is ready to have a winner picked.
     * The following should be true in order for upKeepNeeded to be true
     * 1. The time interval has passed between raffle runs
     * 2. The raffle is open
     * 3. The contract has ETH
     * 4. Implicitly, your subscription has LINK
     * @param - ignored
     * @return upkeepNeeded - true if its time to restart the lottery
     * @return - ignored
     */
    function checkUpKeep(bytes memory /* checkData */ )
        public
        view
        returns (bool upkeepNeeded, bytes memory /* performData */ )
    {
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        bool isOpen = (s_raffleState == RaffleState.OPEN);
        bool hasBalance = (address(this).balance > 0);
        bool hasPlayers = (s_players.length > 0);

        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        //performData = abi.encode(s_lastTimeStamp);
        return (upkeepNeeded, "");
    }

    // 1. Get a random number
    // 2. use the random number to pick a winner
    // 3. Be automatically called
    function performUpKeep(bytes calldata /* performData */ ) external {
        // check if enough time has passed
        (bool upkeepNdeeded,) = checkUpKeep("");
        if (!upkeepNdeeded) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }
        s_raffleState = RaffleState.CALCULATING;

        // Get a random number VRF 2.5
        // Two step process
        // 1. Request RNG (Random Number Generator)
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: i_keyHash, // some gas price to work with the chainlink node
            subId: i_subscriptionId, // how we are going to fund the oracle to work wth chanlink VRF
            requestConfirmations: REQUEST_CONFIRMATIONS, // how many blocks should we wait before before we can get the random number
            callbackGasLimit: i_callbackGasLimit, // so we don't overspend gas
            numWords: NUM_WORDS, // number of random numbers that we want
            extraArgs: VRFV2PlusClient._argsToBytes(
                // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead off LINK
                VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
            )
        });
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
        // redudant (since VRFCoordinator is also emitting this event) but good for debugging
        emit RequestedRaffleWinner(requestId);
    }

    // This need to be implemented as defined in the abstract contract
    // when chainlink node giives us a random number, we need to do some stuff using the function fuullfillRandomWords
    // use the keyword override because it's marked as virtual in the abstract contract
    // CEI - Check Effects Interactions
    function fulfillRandomWords(uint256, /*requestId*/ uint256[] calldata randomWords) internal virtual override {
        // Checks - Its more gas efficient to start with checks

        // Effect (Internal Contract State Changes)
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_raffleState = RaffleState.OPEN; // reset the lottery state to open
        s_players = new address payable[](0); // reset the players array
        emit WinnerPicked(s_recentWinner);

        // Interactions (External Contract Interactions)
        (bool success,) = recentWinner.call{value: address(this).balance}("");
        // give the winner the entrire balance of "this" contract
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /**
     * Getters
     */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }
}
