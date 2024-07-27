// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscripton, FundSubscription, AddConsumer} from "script/Interactions.s.sol";
import {console} from "forge-std/console.sol";

contract DeployRaffle is Script {
    function run() public {
        (Raffle raffle, HelperConfig helperConfig) = deployContract();
        console.log("Raffle deployed to: ", address(raffle));
        console.log("HelperConfig deployed to: ", address(helperConfig));
    }

    function deployContract() public returns (Raffle, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        // if local network deploy -> morks (getLocalConfig)
        // sepolia deploy -> sepolia config
        // AddConsumer addConsumer = new AddConsumer();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        if (config.subscriptionId == 0) {
            // create subscription
            CreateSubscripton createSubscripton = new CreateSubscripton();
            (config.subscriptionId, config.vrfCoordinator) =
                createSubscripton.createSubscription(config.vrfCoordinator, config.account);

            // fund subscription
            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(config.vrfCoordinator, config.subscriptionId, config.link, config.account);
        }

        // start deployng our raffle
        vm.startBroadcast(config.account);
        Raffle raffle = new Raffle(
            config.entranceFee,
            config.interval,
            config.vrfCoordinator,
            config.gasLane, // keyHash
            config.subscriptionId,
            config.callbackGasLimit
        );
        vm.stopBroadcast();

        AddConsumer addConsumer = new AddConsumer();
        // Don't need to broadcast. it's already being done in AddConsumer
        addConsumer.addConsumer(address(raffle), config.vrfCoordinator, config.subscriptionId, config.account);

        return (raffle, helperConfig);
    }
}
