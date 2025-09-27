// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {TrailingStopOrder} from "../src/extensions/TrailingStopOrder.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOrderMixin} from "../src/interfaces/IOrderMixin.sol";
import {Address, AddressLib} from "@1inch/solidity-utils/libraries/AddressLib.sol";
import {MakerTraits, MakerTraitsLib} from "../src/libraries/MakerTraitsLib.sol";

/**
 * @title OrderFillMainnetTest
 * @notice Single focused test for filling trailing stop orders on mainnet with BTC/USDC
 * @dev Run with: forge test --fork-url yourforkurl -vvvv --match-test testFillTrailingStopOrderBTCUSDC
 */
contract OrderFillMainnetTest is Test {
    // ============ State Variables ============

    TrailingStopOrder public trailingStopOrder;

    // Mainnet addresses
    address constant BTC_USD_ORACLE = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c; // BTC/USD Chainlink Oracle
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // Wrapped BTC
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC (correct mainnet address)
    address constant AGGREGATION_ROUTER = 0x1111111254EEB25477B68fb85Ed929f73A960582; // 1inch Router

    // Test accounts
    address public maker;
    address public taker;

    // ============ Setup ============

    function setUp() public {
        // Deploy TrailingStopOrder contract
        trailingStopOrder = new TrailingStopOrder();

        // Setup test accounts
        maker = makeAddr("maker");
        taker = makeAddr("taker");

        // Fund test accounts with ETH
        vm.deal(maker, 100 ether);
        vm.deal(taker, 100 ether);

        // Fund maker with WBTC (simulate having WBTC)
        vm.prank(0x28C6c06298d514Db089934071355E5743bf21d60); // Binance hot wallet
        IERC20(WBTC).transfer(maker, 1e8); // 1 WBTC (8 decimals)

        // Fund taker with USDC by directly setting balance in storage
        // USDC uses standard ERC20 mapping storage: balances[address] = amount
        vm.store(USDC, keccak256(abi.encode(taker, 0x9)), bytes32(uint256(1000e6)));

        // Approve the trailing stop contract to spend taker's USDC
        vm.prank(taker);
        IERC20(USDC).approve(address(trailingStopOrder), 1000e6);

        // Fund the trailing stop contract with USDC for testing
        // This simulates the contract having USDC to transfer to the taker
        vm.store(USDC, keccak256(abi.encode(address(trailingStopOrder), 0x9)), bytes32(uint256(1000e6)));

        // Approve the trailing stop contract to spend maker's WBTC
        vm.prank(maker);
        IERC20(WBTC).approve(address(trailingStopOrder), 1e8);
    }

    // ============ Main Test ============

    /**
     * @notice Test filling a trailing stop order with BTC/USDC on mainnet
     * @dev This test simulates a real trailing stop order execution
     */
    function testFillTrailingStopOrderBTCUSDC() public {
        console.log("=== Starting BTC/USDC Trailing Stop Order Fill Test ===");

        // 1. Create order hash
        bytes32 orderHash = keccak256(abi.encodePacked("BTC_USDC_ORDER", maker, block.timestamp));

        console.log("Order Hash:", vm.toString(orderHash));

        // 2. Configure trailing stop
        TrailingStopOrder.TrailingStopConfig memory config = TrailingStopOrder.TrailingStopConfig({
            makerAssetOracle: AggregatorV3Interface(BTC_USD_ORACLE),
            initialStopPrice: 45000e18, // $45,000 BTC price (18 decimals)
            trailingDistance: 200, // 2% trailing distance (200 basis points)
            currentStopPrice: 45000e18,
            configuredAt: block.timestamp,
            lastUpdateAt: block.timestamp,
            updateFrequency: 300, // 5 minutes
            maxSlippage: 100, // 1% max slippage (100 basis points)
            keeper: address(0) // No specific keeper set
        });

        console.log("Configuring trailing stop...");
        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);

        // 3. Get current BTC price
        (, int256 btcPrice,,,) = AggregatorV3Interface(BTC_USD_ORACLE).latestRoundData();
        uint256 currentBTCPrice = uint256(btcPrice) * 1e10; // Convert to 18 decimals
        console.log("Current BTC Price: $%s", currentBTCPrice / 1e18);

        // 4. Update trailing stop to simulate price movement
        console.log("Updating trailing stop...");
        vm.warp(block.timestamp + 600); // Move time forward 10 minutes
        vm.prank(taker);
        trailingStopOrder.updateTrailingStop(orderHash);

        // 5. Get updated stop price
        (,,, uint256 currentStopPrice,,,,,) = trailingStopOrder.trailingStopConfigs(orderHash);
        console.log("Updated Stop Price: $%s", currentStopPrice / 1e18);

        // 6. Create mock order for taker interaction
        IOrderMixin.Order memory order = IOrderMixin.Order({
            salt: 12345,
            maker: Address.wrap(uint256(uint160(maker))),
            receiver: Address.wrap(uint256(uint160(address(0)))),
            makerAsset: Address.wrap(uint256(uint160(WBTC))),
            takerAsset: Address.wrap(uint256(uint160(USDC))),
            makingAmount: 1e8, // 1 WBTC
            takingAmount: 1000e6, // 1k USDC
            makerTraits: MakerTraits.wrap(0)
        });

        // 7. Test the trailing stop configuration and update functionality
        console.log("Testing trailing stop configuration...");

        // Verify the trailing stop was configured correctly
        (
            AggregatorV3Interface oracle,
            uint256 initialStopPrice,
            uint256 trailingDistance,
            uint256 updatedStopPrice,
            ,
            ,
            uint256 updateFrequency,
            ,
            
        ) = trailingStopOrder.trailingStopConfigs(orderHash);

        assertEq(address(oracle), BTC_USD_ORACLE, "Oracle address should match");
        assertEq(initialStopPrice, 45000e18, "Initial stop price should be $45,000");
        assertEq(trailingDistance, 200, "Trailing distance should be 200 basis points");
        assertTrue(updatedStopPrice > initialStopPrice, "Current stop price should be updated");
        assertEq(updateFrequency, 300, "Update frequency should be 300 seconds");

        console.log("Trailing stop configuration verified successfully!");

        // Test updating the trailing stop again
        console.log("Testing another trailing stop update...");
        vm.warp(block.timestamp + 600); // Move time forward another 10 minutes
        vm.prank(taker);
        trailingStopOrder.updateTrailingStop(orderHash);

        // Verify the stop price was updated again (or remained the same if price didn't change)
        (,,, uint256 finalStopPrice,,,,,) = trailingStopOrder.trailingStopConfigs(orderHash);
        // The stop price should either be the same (if BTC price didn't change) or different (if it did)
        // This is correct behavior for trailing stops
        assertTrue(finalStopPrice >= updatedStopPrice, "Stop price should not decrease");

        console.log("Trailing stop update test completed successfully!");

        // 8. Now test actual order execution - taker takes the order
        console.log("Testing order execution - taker takes the order...");

        // For direct settlement, we just need to pass the router address (even though we don't use it)
        bytes memory extraData = abi.encode(AGGREGATION_ROUTER);

        // Record initial balances
        uint256 makerWBTCBefore = IERC20(WBTC).balanceOf(maker);
        uint256 takerUSDCBefore = IERC20(USDC).balanceOf(taker);
        uint256 makerUSDCBefore = IERC20(USDC).balanceOf(maker);
        uint256 takerWBTCBefore = IERC20(WBTC).balanceOf(taker);

        console.log("Maker WBTC before: %s", makerWBTCBefore);
        console.log("Taker USDC before: %s", takerUSDCBefore);
        console.log("Maker USDC before: %s", makerUSDCBefore);
        console.log("Taker WBTC before: %s", takerWBTCBefore);

        // Execute taker interaction
        vm.prank(taker);
        trailingStopOrder.takerInteraction(
            order,
            "", // extension
            orderHash,
            taker,
            1e8, // makingAmount (1 WBTC)
            1000e6, // takingAmount (1k USDC)
            1e8, // remainingMakingAmount
            extraData
        );

        // Record final balances
        uint256 makerWBTCAfter = IERC20(WBTC).balanceOf(maker);
        uint256 takerUSDCAfter = IERC20(USDC).balanceOf(taker);
        uint256 makerUSDCAfter = IERC20(USDC).balanceOf(maker);
        uint256 takerWBTCAfter = IERC20(WBTC).balanceOf(taker);

        console.log("Maker WBTC after: %s", makerWBTCAfter);
        console.log("Taker USDC after: %s", takerUSDCAfter);
        console.log("Maker USDC after: %s", makerUSDCAfter);
        console.log("Taker WBTC after: %s", takerWBTCAfter);

        // Verify the order execution - direct settlement between maker and taker
        assertEq(makerWBTCBefore - makerWBTCAfter, 1e8, "Maker should have lost 1 WBTC");
        assertEq(takerWBTCAfter - takerWBTCBefore, 1e8, "Taker should have received 1 WBTC");
        assertEq(takerUSDCBefore - takerUSDCAfter, 1000e6, "Taker should have lost 1000 USDC");
        assertEq(makerUSDCAfter - makerUSDCBefore, 1000e6, "Maker should have received 1000 USDC");

        console.log("Order execution successful!");
        console.log("WBTC transferred from maker to taker");
        console.log("USDC transferred from taker to maker");
        console.log("Direct settlement completed successfully");
        console.log("=== Trailing Stop Order Fill Test Completed ===");

        // The test demonstrates successful order execution with direct settlement
        assertTrue(true, "Test completed successfully - direct settlement working!");
    }
}
