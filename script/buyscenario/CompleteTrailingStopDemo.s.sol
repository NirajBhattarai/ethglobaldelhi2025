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
 * @title CompleteTrailingStopDemo
 * @notice Complete demo that creates real trailing stop orders, simulates price movements, and fulfills orders
 */
contract CompleteTrailingStopDemo is Script {
    // Contract instances
    MockChainlinkAggregator public linkUsdAggregator;
    MockChainlinkAggregator public usdcUsdAggregator;
    MockERC20 public mockUSDC;
    MockERC20 public mockLINK;
    LimitOrderProtocol public limitOrderProtocol;
    TrailingStopOrder public trailingStopOrder;
    TrailingStopKeeper public keeper;
    OrderBuilderHelper public orderBuilder;

    // Demo parameters
    uint256 constant INITIAL_LINK_PRICE = 2000e8; // $2000
    uint256 constant TRAILING_DISTANCE = 300; // 3% trailing distance (300 basis points)
    uint256 constant USDC_AMOUNT = 10000e6; // 10,000 USDC
    uint256 constant LINK_AMOUNT = 2e18; // 2 LINK (adjusted to match price ratio)

    // Order data
    IOrderMixin.Order public buyOrder;
    bytes32 public orderHash;
    bytes32 public r;
    bytes32 public vs;

    function run() external {
        uint256 makerPrivateKey = vm.envUint("MAKER_PRIVATE_KEY");
        uint256 takerPrivateKey = vm.envUint("TAKER_PRIVATE_KEY");
        address maker = vm.addr(makerPrivateKey);
        address taker = vm.addr(takerPrivateKey);

        console.log("=== COMPLETE TRAILING STOP DEMO ===");
        console.log("Maker address:", maker);
        console.log("Taker address:", taker);
        console.log("Maker balance:", maker.balance / 1e18, "ETH");
        console.log("Taker balance:", taker.balance / 1e18, "ETH");

        vm.startBroadcast(makerPrivateKey);

        // Step 1: Deploy all contracts
        _deployContracts();

        // Step 2: Setup initial conditions
        _setupInitialConditions(maker, taker);

        // Step 3: Create real trailing stop buy order
        _createTrailingStopOrder(maker);

        // Step 4: Simulate price movements
        _simulatePriceMovements();

        vm.stopBroadcast();

        // Setup taker after broadcast (to avoid prank issues)
        console.log("\n=== Setting up taker ===");
        
        // Mint LINK to taker
        mockLINK.mint(taker, LINK_AMOUNT);
        console.log("Taker minted", LINK_AMOUNT / 1e18, "LINK");
        
        // Approve protocol to spend USDC (taker needs to approve)
        vm.prank(taker);
        mockUSDC.approve(address(limitOrderProtocol), USDC_AMOUNT);
        console.log("Taker approved protocol to spend USDC");
        
        // Approve protocol to spend LINK (taker needs to approve)
        vm.prank(taker);
        mockLINK.approve(address(limitOrderProtocol), LINK_AMOUNT);
        console.log("Taker approved protocol to spend LINK");

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

        usdcUsdAggregator = new MockChainlinkAggregator(8, "USDC / USD");
        console.log("MockChainlinkAggregator (USDC/USD) deployed at:", address(usdcUsdAggregator));

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

        // Set initial USDC price (should be $1.00)
        usdcUsdAggregator.setPrice(1e8); // $1.00
        console.log("Initial USDC price set to: $1");

        // Mint USDC to maker
        mockUSDC.mint(maker, USDC_AMOUNT);
        console.log("Minted", USDC_AMOUNT / 1e6, "USDC to maker");

        // Approve protocol to spend USDC
        mockUSDC.approve(address(limitOrderProtocol), USDC_AMOUNT);
        console.log("Approved protocol to spend USDC");
        
        // Fund maker with ETH for order execution and gas fees
        vm.deal(maker, 50 ether);
        
        // Fund taker with ETH and USDC for order execution
        vm.deal(taker, 10 ether);
        mockUSDC.mint(taker, USDC_AMOUNT);
        console.log("Funded taker with", USDC_AMOUNT / 1e6, "USDC");
        
        // Mint LINK to maker
        mockLINK.mint(maker, LINK_AMOUNT);
        console.log("Minted", LINK_AMOUNT / 1e18, "LINK to maker");
        
        // Approve protocol to spend LINK (maker needs to approve)
        mockLINK.approve(address(limitOrderProtocol), LINK_AMOUNT);
        console.log("Maker approved protocol to spend LINK");

        // Check balances
        uint256 usdcBalance = mockUSDC.balanceOf(maker);
        uint256 usdcAllowance = mockUSDC.allowance(maker, address(limitOrderProtocol));
        console.log("USDC balance:", usdcBalance / 1e6);
        console.log("USDC allowance:", usdcAllowance / 1e6);
    }

    function _createTrailingStopOrder(address maker) internal {
        console.log("\n--- STEP 3: CREATING TRAILING STOP ORDER ---");

        // Create order configuration
        OrderBuilderLib.OrderConfig memory config = OrderBuilderLib.OrderConfig({
            maker: maker,
            receiver: maker,
            makerAsset: address(mockUSDC),
            takerAsset: address(mockLINK),
            makingAmount: USDC_AMOUNT,
            takingAmount: LINK_AMOUNT,
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
        buyOrder = orderBuilder.createCustomOrder(config);
        console.log("Order created successfully");

        // Calculate order hash using the protocol's hashOrder function
        orderHash = limitOrderProtocol.hashOrder(buyOrder);
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

        // Create trailing stop configuration
        TrailingStopOrder.TrailingStopConfig memory config = TrailingStopOrder.TrailingStopConfig({
            makerAssetOracle: linkUsdAggregator, // LINK/USD oracle
            initialStopPrice: initialStopPrice,
            trailingDistance: TRAILING_DISTANCE,
            currentStopPrice: initialStopPrice,
            configuredAt: block.timestamp,
            lastUpdateAt: block.timestamp,
            updateFrequency: 30, // 30 seconds for faster updates
            maxSlippage: 100, // 1% max slippage
            maxPriceDeviation: 500, // 5% max price deviation
            twapWindow: 300, // 5 minutes TWAP window
            keeper: address(keeper),
            orderMaker: maker,
            orderType: TrailingStopOrder.OrderType.SELL, // This is correct for a sell order
            makerAssetDecimals: 6, // USDC decimals
            takerAssetDecimals: 18 // LINK decimals
        });

        // Configure the trailing stop
        trailingStopOrder.configureTrailingStop(orderHash, config);
        console.log("Trailing stop configured successfully");

        // Verify configuration
        (bool shouldTrigger, uint256 currentPriceCheck, uint256 twapPrice, uint256 stopPrice) = 
            trailingStopOrder.isTrailingStopTriggered(orderHash);
        
        console.log("Trailing stop verification:");
        console.log("- Should trigger:", shouldTrigger);
        console.log("- Current price: $", currentPriceCheck / 1e18);
        console.log("- TWAP price: $", twapPrice / 1e18);
        console.log("- Stop price: $", stopPrice / 1e8);
    }

    function _simulatePriceMovements() internal {
        console.log("\n--- STEP 4: SIMULATING PRICE MOVEMENTS ---");
        
        // Price drops: $2000 → $1980 → $1950 → $1900 → $1850 → $1800
        console.log("Simulating price drops:");
        int256[] memory dropPrices = new int256[](6);
        dropPrices[0] = 2000e8;  // $2000
        dropPrices[1] = 1980e8;  // $1980 (-$20)
        dropPrices[2] = 1950e8;  // $1950 (-$30)
        dropPrices[3] = 1900e8;  // $1900 (-$50)
        dropPrices[4] = 1850e8;  // $1850 (-$50)
        dropPrices[5] = 1800e8;  // $1800 (-$50)

        for (uint256 i = 0; i < dropPrices.length; i++) {
            linkUsdAggregator.setPrice(dropPrices[i]);
            console.log("Price updated to: $", uint256(dropPrices[i]) / 1e8);
            
            // Check trailing stop status
            _checkTrailingStopStatus();
            
            vm.warp(block.timestamp + 60); // 1 minute
        }

        // Price rises: $1800 → $1850 → $1900 → $1950 → $2000 → $2050
        console.log("\nSimulating price rises:");
        int256[] memory risePrices = new int256[](6);
        risePrices[0] = 1850e8;  // $1850 (+$50)
        risePrices[1] = 1900e8;  // $1900 (+$50)
        risePrices[2] = 1950e8;  // $1950 (+$50)
        risePrices[3] = 2000e8;  // $2000 (+$50)
        risePrices[4] = 2050e8;  // $2050 (+$50)
        risePrices[5] = 2100e8;  // $2100 (+$50) - Should trigger sell order

        for (uint256 i = 0; i < risePrices.length; i++) {
            linkUsdAggregator.setPrice(risePrices[i]);
            console.log("Price updated to: $", uint256(risePrices[i]) / 1e8);
            
            // Check trailing stop status
            _checkTrailingStopStatus();
            
            vm.warp(block.timestamp + 60); // 1 minute
        }
    }

    function _checkTrailingStopStatus() internal view {
        (bool shouldTrigger, uint256 currentPrice, , uint256 stopPrice) = 
            trailingStopOrder.isTrailingStopTriggered(orderHash);
        
        console.log("  Trailing stop status:");
        console.log("  - Should trigger:", shouldTrigger);
        console.log("  - Current price: $", currentPrice / 1e18);
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
        console.log("- Current price: $", currentPrice / 1e18);
        console.log("- TWAP price: $", twapPrice / 1e18);
        console.log("- Stop price: $", stopPrice / 1e8);

        if (shouldTrigger) {
            console.log("\n*** EXECUTING ORDER ***");
            
            // Create taker traits
            OrderBuilderLib.TakerTraitsConfig memory takerConfig = OrderBuilderLib.TakerTraitsConfig({
                makingAmount: false,
                unwrapWeth: false,
                skipMakerPermit: false,
                usePermit2: false,
                target: address(0),
                extension: "",
                interaction: "",
                threshold: LINK_AMOUNT
            });
            
            (TakerTraits takerTraits,) = orderBuilder.createTakerTraits(takerConfig);

            // Execute the order as taker using fillOrderArgs
            vm.startBroadcast(takerPrivateKey);
            try limitOrderProtocol.fillOrderArgs(
                buyOrder,
                r,
                vs,
                LINK_AMOUNT, // amount parameter - LINK amount taker wants to give
                takerTraits,
                "" // no interaction data for simple execution
            ) returns (uint256 makingAmount, uint256 takingAmount, bytes32 executedOrderHash) {
                console.log("Order executed successfully!");
                console.log("- Making amount:", makingAmount / 1e6, "USDC");
                console.log("- Taking amount:", takingAmount / 1e18, "LINK");
                console.log("- Order hash:", vm.toString(executedOrderHash));
                
                // Check final balances
                uint256 finalUsdcBalance = mockUSDC.balanceOf(taker);
                uint256 finalLinkBalance = mockLINK.balanceOf(taker);
                console.log("- Final USDC balance:", finalUsdcBalance / 1e6);
                console.log("- Final LINK balance:", finalLinkBalance / 1e18);
                
            } catch Error(string memory reason) {
                console.log("Order execution failed:", reason);
            }
            vm.stopBroadcast();
        } else {
            console.log("\nOrder not triggered - conditions not met");
        }
    }

    function _signOrder(bytes32 orderHashParam, address /* signer */) internal view returns (bytes32 rParam, bytes32 vsParam) {
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
