// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {MockChainlinkAggregator} from "../MockChainlinkAggregator.sol";
import {MockERC20} from "../MockERC20.sol";
import {MockWETH} from "../MockWETH.sol";
import {TrailingStopOrder} from "../../src/extensions/TrailingStopOrder.sol";
import {TrailingStopKeeper} from "../../src/helpers/TrailingStopKeeper.sol";
import {LimitOrderProtocol} from "../../src/LimitOrderProtocol.sol";
import {OrderBuilderHelper} from "../../src/helpers/OrderBuilderHelper.sol";
import {OrderBuilderLib} from "../../src/libraries/OrderBuilderLib.sol";
import {OrderLib} from "../../src/OrderLib.sol";
import {IOrderMixin} from "../../src/interfaces/IOrderMixin.sol";
import {TakerTraits} from "../../src/libraries/TakerTraitsLib.sol";
import {IWETH} from "@1inch/solidity-utils/interfaces/IWETH.sol";
import {ECDSA} from "@1inch/solidity-utils/libraries/ECDSA.sol";

/**
 * @title CompleteSellTrailingStopDemo
 * @notice Complete demo that creates a SELL trailing stop order, simulates price movements, and fulfills the order
 * @dev This script creates a proper SELL order where maker sells LINK for USDC with trailing stop protection
 *
 * DEMO PURPOSE: This script uses demo functions instead of Chainlink Automation upkeep for testing purposes.
 * The TrailingStopKeeper contract has upkeep functionality temporarily commented out and uses updateTrailingStopDemo() instead.
 */
contract CompleteSellTrailingStopDemo is Script {
    // Contract instances
    MockChainlinkAggregator public linkUsdAggregator;
    MockERC20 public mockUSDC;
    MockERC20 public mockLINK;
    LimitOrderProtocol public limitOrderProtocol;
    TrailingStopOrder public trailingStopOrder;
    TrailingStopKeeper public keeper;
    OrderBuilderHelper public orderBuilder;

    // Demo parameters
    uint256 constant INITIAL_LINK_PRICE = 20e8; // $20
    uint256 constant TRAILING_DISTANCE = 300; // 3% trailing distance (300 basis points)
    uint256 constant LINK_AMOUNT = 2e18; // 2 LINK (maker sells this)
    uint256 constant USDC_AMOUNT = 70e6; // 70 USDC (maker wants this - adjusted for higher prices)

    // Order data
    IOrderMixin.Order public sellOrder;
    bytes32 public orderHash;
    bytes32 public r;
    bytes32 public vs;

    function run() external {
        uint256 makerPrivateKey = vm.envUint("MAKER_PRIVATE_KEY");
        uint256 takerPrivateKey = vm.envUint("TAKER_PRIVATE_KEY");
        address maker = vm.addr(makerPrivateKey);
        address taker = vm.addr(takerPrivateKey);

        console.log("=== COMPLETE SELL TRAILING STOP DEMO ===");
        console.log("Maker address:", maker);
        console.log("Taker address:", taker);
        console.log("Maker balance:", maker.balance / 1e18, "ETH");
        console.log("Taker balance:", taker.balance / 1e18, "ETH");

        vm.startBroadcast(makerPrivateKey);

        // Step 1: Deploy all contracts
        _deployContracts();

        // Step 2: Setup initial conditions
        _setupInitialConditions(maker, taker);

        // Step 3: Create real trailing stop SELL order
        _createTrailingStopSellOrder(maker);

        // Step 4: Simulate price movements with keeper updates
        _simulatePriceMovementsWithKeeper();

        vm.stopBroadcast();

        // Setup taker after broadcast (to avoid prank issues)
        console.log("\n=== Setting up taker ===");
        console.log("Taker setup will be done within execution context");

        // Step 5: Check and execute order (outside broadcast context)
        _checkAndExecuteOrder(taker, takerPrivateKey);

        console.log("\n=== DEMO COMPLETED SUCCESSFULLY ===");
        console.log("Order Hash:", vm.toString(orderHash));
        (, int256 finalPrice,,,) = linkUsdAggregator.latestRoundData();
        console.log("Final LINK price: $", uint256(finalPrice) / 1e8);
    }

    function _deployContracts() internal {
        console.log("\n--- STEP 1: DEPLOYING CONTRACTS ---");

        linkUsdAggregator = new MockChainlinkAggregator(8, "LINK / USD");
        console.log("MockChainlinkAggregator (LINK/USD) deployed at:", address(linkUsdAggregator));

        mockUSDC = new MockERC20("USD Coin", "USDC", 6);
        console.log("MockUSDC deployed at:", address(mockUSDC));

        mockLINK = new MockERC20("Chainlink", "LINK", 18);
        console.log("MockLINK deployed at:", address(mockLINK));

        // Create a mock WETH for the protocol (required by constructor)
        MockWETH mockWETH = new MockWETH();
        console.log("MockWETH deployed at:", address(mockWETH));

        limitOrderProtocol = new LimitOrderProtocol(IWETH(address(mockWETH)));
        console.log("LimitOrderProtocol deployed at:", address(limitOrderProtocol));

        trailingStopOrder = new TrailingStopOrder(address(limitOrderProtocol));
        console.log("TrailingStopOrder deployed at:", address(trailingStopOrder));

        keeper = new TrailingStopKeeper(address(trailingStopOrder));
        console.log("TrailingStopKeeper deployed at:", address(keeper));

        orderBuilder = new OrderBuilderHelper();
        console.log("OrderBuilderHelper deployed at:", address(orderBuilder));
    }

    function _setupInitialConditions(address maker, address taker) internal {
        console.log("\n--- STEP 2: SETTING UP INITIAL CONDITIONS ---");

        // Set initial LINK price
        linkUsdAggregator.setPrice(int256(INITIAL_LINK_PRICE));
        console.log("Initial LINK price set to: $", INITIAL_LINK_PRICE / 1e8);

        // Mint LINK to maker (maker has LINK to sell)
        mockLINK.mint(maker, LINK_AMOUNT);
        console.log("Minted", LINK_AMOUNT / 1e18, "LINK to maker");

        // Approve protocol to spend LINK
        mockLINK.approve(address(limitOrderProtocol), LINK_AMOUNT);
        console.log("Approved protocol to spend LINK");

        // Fund maker with ETH for order execution and gas fees
        vm.deal(maker, 50 ether);

        // Fund taker with ETH for order execution
        vm.deal(taker, 10 ether);

        // Check balances
        uint256 linkBalance = mockLINK.balanceOf(maker);
        uint256 linkAllowance = mockLINK.allowance(maker, address(limitOrderProtocol));
        console.log("LINK balance:", linkBalance / 1e18);
        console.log("LINK allowance:", linkAllowance / 1e18);
    }

    function _createTrailingStopSellOrder(address maker) internal {
        console.log("\n--- STEP 3: CREATING TRAILING STOP SELL ORDER ---");

        // Create SELL order configuration (maker sells LINK for USDC)
        OrderBuilderLib.OrderConfig memory config = OrderBuilderLib.OrderConfig({
            maker: maker,
            receiver: maker,
            makerAsset: address(mockLINK), // Maker sells LINK
            takerAsset: address(mockUSDC), // Taker gives USDC
            makingAmount: LINK_AMOUNT, // Maker sells 2 LINK
            takingAmount: USDC_AMOUNT, // Maker wants 4000 USDC
            makerTraits: OrderBuilderLib.MakerTraitsConfig({
                allowedSender: address(0),
                shouldCheckEpoch: false,
                allowPartialFill: true,
                allowMultipleFills: true,
                usePermit2: false,
                unwrapWeth: false,
                expiry: uint32(block.timestamp + 1 days), // 1 day expiry
                nonce: 1,
                series: 0
            }),
            extension: OrderBuilderLib.OrderExtensionConfig({
                makerAssetSuffix: "",
                takerAssetSuffix: "",
                makingAmountData: "",
                takingAmountData: "",
                predicate: "",
                permit: "",
                preInteraction: "",
                postInteraction: "",
                customData: ""
            })
        });

        // Build the order
        sellOrder = orderBuilder.createCustomOrder(config);
        console.log("SELL Order created successfully");

        // Calculate order hash using the protocol's hashOrder function
        orderHash = limitOrderProtocol.hashOrder(sellOrder);
        console.log("Order hash:", vm.toString(orderHash));

        // Sign the order
        (r, vs) = _signOrder(orderHash, maker);
        console.log("Order signed successfully");

        // Configure trailing stop
        _configureTrailingStop(maker);
    }

    function _configureTrailingStop(address maker) internal {
        console.log("\n--- CONFIGURING TRAILING STOP ---");

        // Calculate initial stop price (for sell order: current price - trailing distance)
        (, int256 currentPriceInt,,,) = linkUsdAggregator.latestRoundData();
        uint256 currentPrice = uint256(currentPriceInt);
        uint256 initialStopPrice = currentPrice - (currentPrice * TRAILING_DISTANCE / 10000);

        console.log("Current LINK price: $", currentPrice / 1e8);
        console.log("Trailing distance: 3%");
        console.log("Initial stop price: $", initialStopPrice / 1e8);

        // Create trailing stop configuration for SELL order
        TrailingStopOrder.TrailingStopConfig memory config = TrailingStopOrder.TrailingStopConfig({
            makerAssetOracle: linkUsdAggregator, // LINK/USD oracle
            initialStopPrice: initialStopPrice,
            trailingDistance: TRAILING_DISTANCE,
            currentStopPrice: initialStopPrice,
            configuredAt: block.timestamp,
            lastUpdateAt: block.timestamp,
            updateFrequency: 10, // 10 seconds for faster updates
            maxSlippage: 100, // 1% max slippage
            maxPriceDeviation: 500, // 5% max price deviation
            twapWindow: 300, // 5 minutes TWAP window
            keeper: address(keeper),
            orderMaker: maker,
            orderType: TrailingStopOrder.OrderType.SELL, // Correct for sell order
            makerAssetDecimals: 18, // LINK decimals
            takerAssetDecimals: 6 // USDC decimals
        });

        // Configure the trailing stop
        trailingStopOrder.configureTrailingStop(orderHash, config);
        console.log("Trailing stop configured successfully");

        // Verify configuration
        (bool shouldTrigger, uint256 currentPriceCheck, uint256 twapPrice, uint256 stopPrice) =
            trailingStopOrder.isTrailingStopTriggered(orderHash);

        console.log("Trailing stop verification:");
        console.log("- Should trigger:", shouldTrigger);
        console.log("- Current price: $", currentPriceCheck / 1e8);
        console.log("- TWAP price: $", twapPrice / 1e8);
        console.log("- Stop price: $", stopPrice / 1e8);
    }

    function _simulatePriceMovementsWithKeeper() internal {
        console.log("\n--- STEP 4: SIMULATING PRICE MOVEMENTS WITH KEEPER UPDATES ---");

        // Price rises first: $20 → $22 → $25 → $28 → $30 → $32
        console.log("Simulating price rises (trailing stop should follow):");
        int256[] memory risePrices = new int256[](6);
        risePrices[0] = 22e8; // $22 (+$2)
        risePrices[1] = 25e8; // $25 (+$3)
        risePrices[2] = 28e8; // $28 (+$3)
        risePrices[3] = 30e8; // $30 (+$2)
        risePrices[4] = 32e8; // $32 (+$2)
        risePrices[5] = 35e8; // $35 (+$3)

        for (uint256 i = 0; i < risePrices.length; i++) {
            linkUsdAggregator.setPrice(risePrices[i]);
            console.log("Price updated to: $", uint256(risePrices[i]) / 1e8);

            // Update trailing stop via keeper
            _updateTrailingStopViaKeeper();

            vm.warp(block.timestamp + 15); // 15 seconds (more than 10 second update frequency)
        }

        // Price drops: $35 → $30 → $25 → $20 → $15 → $10
        console.log("\nSimulating price drops (should trigger sell):");
        int256[] memory dropPrices = new int256[](6);
        dropPrices[0] = 30e8; // $30 (-$5)
        dropPrices[1] = 25e8; // $25 (-$5)
        dropPrices[2] = 20e8; // $20 (-$5)
        dropPrices[3] = 15e8; // $15 (-$5)
        dropPrices[4] = 10e8; // $10 (-$5)
        dropPrices[5] = 8e8; // $8 (-$2) - Should trigger sell order

        for (uint256 i = 0; i < dropPrices.length; i++) {
            linkUsdAggregator.setPrice(dropPrices[i]);
            console.log("Price updated to: $", uint256(dropPrices[i]) / 1e8);

            // Update trailing stop via keeper
            _updateTrailingStopViaKeeper();

            // Check trailing stop status
            _checkTrailingStopStatus();

            vm.warp(block.timestamp + 35); // 35 seconds
        }
    }

    function _updateTrailingStopViaKeeper() internal {
        // DEMO FUNCTION - Directly call the demo update function instead of upkeep
        console.log("  Keeper updating trailing stop (DEMO MODE)...");
        (bool updated, uint256 currentStopPrice) = keeper.updateTrailingStopDemo(orderHash);

        // Always show the current stop price for demo purposes
        console.log("  Current stop price: $", currentStopPrice / 1e8);

        if (updated) {
            console.log("  [SUCCESS] Trailing stop updated successfully");
        } else {
            console.log("  [INFO] No update needed (price conditions not met)");
        }
    }

    function _checkTrailingStopStatus() internal view {
        (bool shouldTrigger, uint256 currentPrice,, uint256 stopPrice) =
            trailingStopOrder.isTrailingStopTriggered(orderHash);

        console.log("  Trailing stop status:");
        console.log("  - Should trigger:", shouldTrigger);
        console.log("  - Current price: $", currentPrice / 1e8);
        console.log("  - Stop price: $", stopPrice / 1e8);

        if (shouldTrigger) {
            console.log("  *** TRAILING STOP TRIGGERED! ***");
        }
    }

    function _checkAndExecuteOrder(address taker, uint256 takerPrivateKey) internal {
        console.log("\n--- STEP 5: CHECKING AND EXECUTING ORDER ---");

        // Check if trailing stop is triggered
        (bool shouldTrigger, uint256 currentPrice, uint256 twapPrice, uint256 stopPrice) =
            trailingStopOrder.isTrailingStopTriggered(orderHash);

        console.log("Final trailing stop status:");
        console.log("- Should trigger:", shouldTrigger);
        console.log("- Current price: $", currentPrice / 1e8);
        console.log("- TWAP price: $", twapPrice / 1e8);
        console.log("- Stop price: $", stopPrice / 1e8);

        if (shouldTrigger) {
            console.log("\n*** EXECUTING SELL ORDER ***");

            // Check taker balances before execution
            uint256 takerUsdcBalance = mockUSDC.balanceOf(taker);
            uint256 takerLinkBalance = mockLINK.balanceOf(taker);
            console.log("Taker balances before execution:");
            console.log("- USDC balance:", takerUsdcBalance / 1e6);
            console.log("- LINK balance:", takerLinkBalance / 1e18);

            // Ensure taker has enough USDC (double the amount to handle potential double execution)
            uint256 requiredAmount = USDC_AMOUNT * 2; // Double to handle simulation double-execution
            if (takerUsdcBalance < requiredAmount) {
                console.log("Taker needs more USDC, minting additional tokens...");
                mockUSDC.mint(taker, requiredAmount - takerUsdcBalance);
                console.log("Additional USDC minted (double amount for simulation safety)");
            }

            // Create taker traits
            OrderBuilderLib.TakerTraitsConfig memory takerConfig = OrderBuilderLib.TakerTraitsConfig({
                makingAmount: false,
                unwrapWeth: false,
                skipMakerPermit: false,
                usePermit2: false,
                target: address(0),
                extension: "",
                interaction: "",
                threshold: USDC_AMOUNT // Taker wants to give USDC amount
            });

            (TakerTraits takerTraits,) = orderBuilder.createTakerTraits(takerConfig);

            // Execute the order as taker using fillOrderArgs
            vm.startBroadcast(takerPrivateKey);

            // Setup taker within broadcast context (same as maker setup)
            console.log("Setting up taker within broadcast context...");

            // Mint USDC to taker (taker needs USDC to buy LINK) - mint double amount for safety
            mockUSDC.mint(taker, USDC_AMOUNT * 2);
            console.log("Taker minted", (USDC_AMOUNT * 2) / 1e6, "USDC");

            // Approve protocol to spend USDC (taker needs to approve) - approve double amount for safety
            mockUSDC.approve(address(limitOrderProtocol), USDC_AMOUNT * 2);
            console.log("Taker approved protocol to spend USDC (double amount for safety)");

            // Also approve LINK for taker (in case needed)
            mockLINK.approve(address(limitOrderProtocol), LINK_AMOUNT);
            console.log("Taker approved protocol to spend LINK");

            // Check balances and allowance before execution
            uint256 currentBalance = mockUSDC.balanceOf(taker);
            uint256 allowance = mockUSDC.allowance(taker, address(limitOrderProtocol));
            console.log("Final checks before execution:");
            console.log("- USDC balance:", currentBalance / 1e6);
            console.log("- USDC allowance:", allowance / 1e6);

            // Execute the order directly without try-catch
            (uint256 makingAmount, uint256 takingAmount, bytes32 executedOrderHash) = limitOrderProtocol.fillOrderArgs(
                sellOrder,
                r,
                vs,
                USDC_AMOUNT, // amount parameter - USDC amount taker wants to give
                takerTraits,
                "" // no interaction data for simple execution
            );

            console.log("SELL Order executed successfully!");
            console.log("- Making amount:", makingAmount / 1e18, "LINK");
            console.log("- Taking amount:", takingAmount / 1e6, "USDC");
            console.log("- Order hash:", vm.toString(executedOrderHash));

            // Check final balances
            uint256 finalUsdcBalance = mockUSDC.balanceOf(taker);
            uint256 finalLinkBalance = mockLINK.balanceOf(taker);
            console.log("- Final USDC balance:", finalUsdcBalance / 1e6);
            console.log("- Final LINK balance:", finalLinkBalance / 1e18);

            vm.stopBroadcast();
        } else {
            console.log("\nOrder not triggered - conditions not met");
        }
    }

    function _signOrder(bytes32 orderHashParam, address /* signer */ )
        internal
        view
        returns (bytes32 rParam, bytes32 vsParam)
    {
        // Get the maker private key from environment
        uint256 makerPrivateKey = vm.envUint("MAKER_PRIVATE_KEY");

        // Sign the order hash directly (not with EIP-712 prefix)
        (uint8 v, bytes32 r_raw, bytes32 s) = vm.sign(makerPrivateKey, orderHashParam);

        // Convert to r, vs format (same as in tests)
        rParam = r_raw;
        // For vs format: v is 27 or 28, so we need to subtract 27 and shift left by 255 bits
        vsParam = bytes32((uint256(v - 27) << 255) | uint256(s));
    }
}
