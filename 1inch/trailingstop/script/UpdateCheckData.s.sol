// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {IAutomationRegistry} from "../src/interfaces/IAutomationRegistry.sol";
// import {KeeperRegistryLogicA2_1} from "chainlink-brownie-contracts/contracts/src/v0.8/automation/v2_1/KeeperRegistryLogicA2_1.sol";
import {IKeeperRegistryLogicA2_1} from "../src/interfaces/IKeeperRegistryLogicA2_1.sol";

/**
 * @title UpdateCheckDataScript
 * @notice Minimal script to update checkData for an existing Chainlink Automation upkeep
 * @dev This script uses hardcoded values for testing without environment variables
 */
contract UpdateCheckDataScript is Script {
    // Sepolia Chainlink Automation addresses
    address constant SEPOLIA_KEEPER_REGISTRY = 0x86EFBD0b6736Bed994962f9797049422A3A8E8Ad;
    address constant KEEPER_REGISTRY_LOGIC_A2_1 = 0x86EFBD0b6736Bed994962f9797049422A3A8E8Ad;

    // Hardcoded values for testing - replace with your actual values
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    uint256 constant TEST_UPKEEP_ID = 28956307127899810914652287220575233182894625357624166823152631801835204397309; // Replace with your actual upkeep ID

    function run() external {
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance / 1e18, "ETH");
        console.log("Upkeep ID:", TEST_UPKEEP_ID);

        // Create mock order hashes for testing
        bytes32[] memory orderHashes = new bytes32[](3);
        orderHashes[0] = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        orderHashes[1] = 0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890;
        orderHashes[2] = 0x567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234;

        bytes memory newCheckData = abi.encode(orderHashes);

        console.log("Using mock order hashes for testing");
        console.log("Mock order hash 1:", vm.toString(orderHashes[0]));
        console.log("Mock order hash 2:", vm.toString(orderHashes[1]));
        console.log("Mock order hash 3:", vm.toString(orderHashes[2]));
        console.log("New checkData length:", newCheckData.length);
        console.log("New checkData (hex):", vm.toString(newCheckData));

        // Get current checkData for comparison
        IAutomationRegistry registry = IAutomationRegistry(SEPOLIA_KEEPER_REGISTRY);
        // (,, bytes memory currentCheckData,,,,,,) = registry.getUpkeep(TEST_UPKEEP_ID);
        // console.log("Current checkData length:", currentCheckData.length);
        // console.log("Current checkData (hex):", vm.toString(currentCheckData));

        // console.log("Updating checkData for upkeep ID:", TEST_UPKEEP_ID);

        vm.startBroadcast(deployerPrivateKey);

        // Call setUpkeepCheckData on the KeeperRegistryLogicA2_1 contract
        IKeeperRegistryLogicA2_1 keeperLogic = IKeeperRegistryLogicA2_1(KEEPER_REGISTRY_LOGIC_A2_1);
        keeperLogic.setUpkeepCheckData(TEST_UPKEEP_ID, newCheckData);

        vm.stopBroadcast();

        console.log("CheckData updated successfully!");

        // // Verify the update
        // (,, bytes memory updatedCheckData,,,,,,) = registry.getUpkeep(TEST_UPKEEP_ID);
        // console.log("Updated checkData length:", updatedCheckData.length);
        // console.log("Updated checkData (hex):", vm.toString(updatedCheckData));

        // // Check if the update was successful
        // if (keccak256(updatedCheckData) == keccak256(newCheckData)) {
        //     console.log("CheckData update verified successfully");
        // } else {
        //     console.log("CheckData update verification failed");
        // }
    }
}
