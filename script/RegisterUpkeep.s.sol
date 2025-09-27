// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {TrailingStopKeeper} from "../src/helpers/TrailingStopKeeper.sol";
import {TrailingStopOrder} from "../src/extensions/TrailingStopOrder.sol";
import {LimitOrderProtocol} from "../src/LimitOrderProtocol.sol";
import {IWETH} from "@1inch/solidity-utils/interfaces/IWETH.sol";
import {IAutomationRegistry} from "../src/interfaces/IAutomationRegistry.sol";
import {IAutomationRegistrar} from "../src/interfaces/IAutomationRegistrar.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC677 {
    function transferAndCall(address to, uint256 amount, bytes memory data) external returns (bool);
}

/**
 * @title RegisterUpkeepScript
 * @notice Script to register TrailingStopOrderKeeper with Chainlink Automation on Sepolia
 * @dev This script registers the keeper contract for automated trailing stop order updates
 */
contract RegisterUpkeepScript is Script {
    // Sepolia Chainlink Automation addresses
    address constant SEPOLIA_LINK_TOKEN = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
    address constant SEPOLIA_REGISTRAR = 0xb0E49c5D0d05cbc241d68c05BC5BA1d1B7B72976;
    address constant SEPOLIA_KEEPER_REGISTRY = 0x86EFBD0b6736Bed994962f9797049422A3A8E8Ad;

    // Configuration
    uint32 constant GAS_LIMIT = 500000; // Gas limit for upkeep execution
    uint96 constant FUNDING_AMOUNT = 2 ether; // 2 LINK tokens for funding (in wei)

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance / 1e18, "ETH");

        // Get contract addresses from environment or use defaults
        address trailingStopOrderAddress = vm.envOr("TRAILING_STOP_ORDER_ADDRESS", address(0));
        address keeperAddress = vm.envOr("KEEPER_ADDRESS", address(0));

        if (trailingStopOrderAddress == address(0)) {
            console.log("TRAILING_STOP_ORDER_ADDRESS not set, deploying contracts...");
            vm.startBroadcast(deployerPrivateKey);

            // Deploy LimitOrderProtocol first
            // For script deployment, we'll use a mock WETH address
            address mockWETH = address(0x1234567890123456789012345678901234567890); // Mock WETH address
            LimitOrderProtocol limitOrderProtocol = new LimitOrderProtocol(IWETH(mockWETH));
            console.log("LimitOrderProtocol deployed at:", address(limitOrderProtocol));

            // Deploy TrailingStopOrder with the deployed LimitOrderProtocol
            TrailingStopOrder trailingStopOrder = new TrailingStopOrder(address(limitOrderProtocol));
            trailingStopOrderAddress = address(trailingStopOrder);
            vm.stopBroadcast();
            console.log("TrailingStopOrder deployed at:", trailingStopOrderAddress);
        }

        if (keeperAddress == address(0)) {
            console.log("KEEPER_ADDRESS not set, deploying TrailingStopKeeper...");
            vm.startBroadcast(deployerPrivateKey);
            TrailingStopKeeper keeper = new TrailingStopKeeper(trailingStopOrderAddress);
            keeperAddress = address(keeper);
            vm.stopBroadcast();
            console.log("TrailingStopKeeper deployed at:", keeperAddress);
        }

        // Prepare checkData - empty array for initial registration
        // This will be updated later with actual order hashes
        bytes32[] memory orderHashes = new bytes32[](0);
        bytes memory checkData = abi.encode(orderHashes);

        console.log("Registering upkeep with Chainlink Automation...");
        console.log("Target contract:", keeperAddress);
        console.log("Gas limit:", GAS_LIMIT);
        console.log("Admin:", deployer);
        console.log("Check data length:", checkData.length);

        vm.startBroadcast(deployerPrivateKey);

        // Use transferAndCall to register upkeep
        console.log("Using transferAndCall to register upkeep...");

        // Encode the register function call data
        bytes memory registerData = abi.encodeWithSignature(
            "register(string,bytes,address,uint32,address,uint8,bytes,bytes,bytes,uint96,address)",
            "Testing", // name
            "", // encryptedEmail
            keeperAddress, // upkeepContract
            GAS_LIMIT, // gasLimit
            deployer, // adminAddress
            uint8(0), // triggerType
            checkData, // checkData
            "", // triggerConfig
            "", // offchainConfig
            FUNDING_AMOUNT, // amount
            deployer // sender
        );

        // Use transferAndCall to send LINK and trigger registration
        IERC677 linkToken = IERC677(SEPOLIA_LINK_TOKEN);
        linkToken.transferAndCall(SEPOLIA_REGISTRAR, FUNDING_AMOUNT, registerData);

        vm.stopBroadcast();
    }
}
