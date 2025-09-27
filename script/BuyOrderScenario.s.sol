// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {TrailingStopOrder} from "../src/extensions/TrailingStopOrder.sol";
import {TrailingStopKeeper} from "../src/helpers/TrailingStopKeeper.sol";
import {LimitOrderProtocol} from "../src/LimitOrderProtocol.sol";
import {IWETH} from "@1inch/solidity-utils/interfaces/IWETH.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address, AddressLib} from "@1inch/solidity-utils/libraries/AddressLib.sol";
import {MakerTraitsLib, MakerTraits} from "../src/libraries/MakerTraitsLib.sol";
import {IOrderMixin} from "../src/interfaces/IOrderMixin.sol";

/**
 * @title MockChainlinkAggregator
 * @notice Mock Chainlink aggregator for Sepolia demo
 */
contract MockChainlinkAggregator is AggregatorV3Interface {
    uint8 public decimals;
    string public description;
    uint256 public version;
    uint80 public roundId;
    int256 public answer;
    uint256 public startedAt;
    uint256 public updatedAt;
    uint80 public answeredInRound;

    constructor(uint8 _decimals, string memory _description) {
        decimals = _decimals;
        description = _description;
        version = 1;
        roundId = 1;
        answer = 2000e8; // Default $2000 ETH price
        startedAt = block.timestamp;
        updatedAt = block.timestamp;
        answeredInRound = 1;
    }

    function setPrice(int256 _price) external {
        answer = _price;
        updatedAt = block.timestamp;
        roundId++;
        answeredInRound = roundId;
    }

    function latestRoundData() external view override returns (uint80, int256, uint256, uint256, uint80) {
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    function getRoundData(uint80 _roundId) external view override returns (uint80, int256, uint256, uint256, uint80) {
        return (_roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}

/**
 * @title MockERC20
 * @notice Mock ERC20 token for Sepolia demo
 */
contract MockERC20 is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;
    string public name;
    string public symbol;
    uint8 public decimals;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        return true;
    }
}

/**
 * @title MockWETH
 * @notice Mock WETH contract for Sepolia demo
 */
contract MockWETH is IWETH {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;
    string public name = "Wrapped Ether";
    string public symbol = "WETH";
    uint8 public decimals = 18;

    function deposit() external payable override {
        _balances[msg.sender] += msg.value;
        _totalSupply += msg.value;
    }

    function withdraw(uint256 amount) external override {
        _balances[msg.sender] -= amount;
        _totalSupply -= amount;
        payable(msg.sender).transfer(amount);
    }

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        return true;
    }
}

/**
 * @title BuyOrderScenarioScript
 * @notice Demo script showcasing buy order trailing stop functionality
 * @dev This script demonstrates buying ETH with USDC using trailing stop orders
 */
contract BuyOrderScenarioScript is Script {
    // Demo contracts
    MockWETH public mockWETH;
    MockERC20 public mockUSDC;
    MockChainlinkAggregator public ethUsdAggregator;
    TrailingStopOrder public trailingStopOrder;
    TrailingStopKeeper public keeper;
    LimitOrderProtocol public limitOrderProtocol;

    // Demo parameters - More realistic values
    uint256 constant INITIAL_ETH_PRICE = 2000e8; // $2000
    uint256 constant TRAILING_DISTANCE = 300; // 3% trailing distance in basis points (more realistic)
    uint256 constant ORDER_AMOUNT = 1e18; // 1 ETH
    uint256 constant USDC_AMOUNT = 2000e6; // 2000 USDC
    uint256 constant DCA_INTERVAL = 300; // 5 minutes between DCA purchases

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("\n============================================================");
        console.log("BUY ORDER TRAILING STOP DEMO - ENTRY PROTECTION STRATEGY");
        console.log("============================================================");
        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance / 1e18, "ETH");
        console.log("Starting at:", block.timestamp);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock contracts
        _deployMockContracts();
        _pauseForReadability("Mock contracts deployed");

        // Deploy main contracts
        _deployMainContracts();
        _pauseForReadability("Main contracts deployed");

        vm.stopBroadcast();

        // Run buy order demo
        _demoBuyOrder();
        _pauseForReadability("Initial buy order configured");

        _simulatePriceMovements();

        console.log("\n============================================================");
        console.log("BUY ORDER DEMO COMPLETED SUCCESSFULLY!");
        console.log("============================================================");
    }

    function _pauseForReadability(string memory message) internal view {
        console.log("\n----------------------------------------");
        console.log("PAUSE:", message);
        console.log("----------------------------------------");
        console.log("Press Enter to continue... (simulated pause)");
        console.log("");
    }

    function _deployMockContracts() internal {
        console.log("\n======================");
        console.log("DEPLOYING MOCK CONTRACTS");
        console.log("======================");

        // Deploy Mock WETH
        console.log("Deploying MockWETH...");
        mockWETH = new MockWETH();
        console.log("MockWETH deployed at:", address(mockWETH));
        console.log("   - Name: Wrapped Ether");
        console.log("   - Symbol: WETH");
        console.log("   - Decimals: 18");
        console.log("");

        // Deploy Mock USDC
        console.log("Deploying MockUSDC...");
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);
        console.log("MockUSDC deployed at:", address(mockUSDC));
        console.log("   - Name: USD Coin");
        console.log("   - Symbol: USDC");
        console.log("   - Decimals: 6");
        console.log("");

        // Deploy Mock Chainlink Aggregator
        console.log("Deploying Mock Chainlink Aggregator...");
        ethUsdAggregator = new MockChainlinkAggregator(8, "ETH / USD");
        console.log("ETH/USD Aggregator deployed at:", address(ethUsdAggregator));
        console.log("   - Description: ETH / USD");
        console.log("   - Decimals: 8");
        console.log("   - Version: 1");
        console.log("");

        // Set initial price
        console.log("Setting initial ETH price...");
        ethUsdAggregator.setPrice(int256(INITIAL_ETH_PRICE));
        console.log("Initial ETH price set to: $", INITIAL_ETH_PRICE / 1e8);
        console.log("   - This will be our starting point for the demo");
    }

    function _deployMainContracts() internal {
        console.log("\n======================");
        console.log("DEPLOYING MAIN CONTRACTS");
        console.log("======================");

        // Deploy LimitOrderProtocol
        console.log("Deploying LimitOrderProtocol...");
        limitOrderProtocol = new LimitOrderProtocol(IWETH(address(mockWETH)));
        console.log("LimitOrderProtocol deployed at:", address(limitOrderProtocol));
        console.log("   - Core protocol for limit orders");
        console.log("   - Integrated with MockWETH");
        console.log("");

        // Deploy TrailingStopOrder
        console.log("Deploying TrailingStopOrder...");
        trailingStopOrder = new TrailingStopOrder(address(limitOrderProtocol));
        console.log("TrailingStopOrder deployed at:", address(trailingStopOrder));
        console.log("   - Extension for trailing stop functionality");
        console.log("   - Connected to LimitOrderProtocol");
        console.log("");

        // Deploy Keeper
        console.log("Deploying TrailingStopKeeper...");
        keeper = new TrailingStopKeeper(address(trailingStopOrder));
        console.log("TrailingStopKeeper deployed at:", address(keeper));
        console.log("   - Automated keeper for order execution");
        console.log("   - Monitors price movements and triggers orders");
        console.log("");
    }

    function _demoBuyOrder() internal {
        console.log("\n======================");
        console.log("CONFIGURING BUY ORDER SCENARIO");
        console.log("======================");

        address user = vm.addr(vm.envUint("PRIVATE_KEY"));
        console.log("User address:", user);
        console.log("");

        // Setup: User has USDC and wants to buy ETH with trailing stop
        console.log("Setting up buy order scenario...");
        console.log("   Strategy: Dollar Cost Averaging (DCA) with Trailing Stop Protection");
        console.log("   Goal: Buy ETH during price drops, protect against sudden recovery");
        console.log("");

        // Mint USDC to user
        console.log("Minting USDC to user...");
        mockUSDC.mint(user, USDC_AMOUNT);
        console.log("Minted", USDC_AMOUNT / 1e6, "USDC to user");
        console.log("   - This represents the user's available capital");
        console.log("");

        // User approves the protocol
        console.log("User approving protocol to spend USDC...");
        vm.prank(user);
        mockUSDC.approve(address(limitOrderProtocol), USDC_AMOUNT);
        console.log("User approved protocol to spend USDC");
        console.log("   - Required for the protocol to execute trades");
        console.log("");

        // Create buy order (buy ETH with USDC using trailing stop)
        console.log("Creating buy order parameters...");
        IOrderMixin.Order memory orderInfo = IOrderMixin.Order({
            salt: 0,
            maker: Address.wrap(uint160(user)),
            receiver: Address.wrap(uint160(user)),
            makerAsset: Address.wrap(uint160(address(mockUSDC))),
            takerAsset: Address.wrap(uint160(address(mockWETH))),
            makingAmount: USDC_AMOUNT,
            takingAmount: ORDER_AMOUNT,
            makerTraits: MakerTraits.wrap(0)
        });
        console.log("Order parameters created");
        console.log("   - Maker: User (", user, ")");
        console.log("   - Maker Asset: USDC (", address(mockUSDC), ")");
        console.log("   - Taker Asset: WETH (", address(mockWETH), ")");
        console.log("   - Making Amount:", USDC_AMOUNT / 1e6, "USDC");
        console.log("   - Taking Amount:", ORDER_AMOUNT / 1e18, "ETH");
        console.log("");

        // Create trailing stop extension data for buy order
        console.log("Configuring trailing stop parameters...");
        TrailingStopOrder.TrailingStopConfig memory config = TrailingStopOrder.TrailingStopConfig({
            makerAssetOracle: ethUsdAggregator,
            takerAssetOracle: ethUsdAggregator,
            initialStopPrice: INITIAL_ETH_PRICE + (INITIAL_ETH_PRICE * TRAILING_DISTANCE / 10000), // $2060 (3% above $2000)
            trailingDistance: TRAILING_DISTANCE,
            currentStopPrice: INITIAL_ETH_PRICE + (INITIAL_ETH_PRICE * TRAILING_DISTANCE / 10000),
            configuredAt: block.timestamp,
            lastUpdateAt: block.timestamp,
            updateFrequency: 60, // 1 minute
            maxSlippage: 50, // 0.5% (tighter slippage)
            maxPriceDeviation: 100, // 1% (tighter deviation)
            twapWindow: 300, // 5 minutes
            keeper: address(keeper),
            orderMaker: user,
            orderType: TrailingStopOrder.OrderType.BUY,
            makerAssetDecimals: 6,
            takerAssetDecimals: 18
        });
        console.log("Trailing stop configuration created");
        console.log("   - Initial Stop Price: $", config.initialStopPrice / 1e8);
        console.log("   - Trailing Distance:", TRAILING_DISTANCE / 100, "%");
        console.log("   - Max Slippage:", config.maxSlippage / 100, "%");
        console.log("   - Max Price Deviation:", config.maxPriceDeviation / 100, "%");
        console.log("   - Update Frequency:", config.updateFrequency, "seconds");
        console.log("   - TWAP Window:", config.twapWindow, "seconds");
        console.log("");

        // Place the order
        console.log("Placing the buy order...");
        vm.prank(user);
        bytes32 orderHash = limitOrderProtocol.hashOrder(orderInfo);
        console.log("Order hash generated:", vm.toString(orderHash));
        console.log("");

        // Configure trailing stop
        console.log("Configuring trailing stop extension...");
        vm.prank(user);
        trailingStopOrder.configureTrailingStop(orderHash, config);
        console.log("Trailing stop configured successfully!");
        console.log("");

        console.log("BUY ORDER SUMMARY:");
        console.log("   Order Type: BUY (DCA strategy with trailing stop protection)");
        console.log("   Capital: ", USDC_AMOUNT / 1e6, "USDC");
        console.log("   Target: ", ORDER_AMOUNT / 1e18, "ETH");
        console.log("   Stop Price: $", config.initialStopPrice / 1e8);
        console.log("   Trailing Distance:", TRAILING_DISTANCE / 100, "%");
        console.log("   Strategy: Accumulate on dips, protect on recovery");
    }

    function _simulatePriceMovements() internal {
        console.log("\n============================================================");
        console.log("SIMULATING TRAILING STOP PRICE MOVEMENTS - BUY ORDER");
        console.log("============================================================");

        (, int256 currentPrice,,,) = ethUsdAggregator.latestRoundData();
        console.log("Starting ETH price: $", uint256(currentPrice) / 1e8);
        console.log("Initial stop price: $", (INITIAL_ETH_PRICE + (INITIAL_ETH_PRICE * TRAILING_DISTANCE / 10000)) / 1e8);
        console.log("Trailing distance: ", TRAILING_DISTANCE / 100, "%");
        console.log("");

        // Visual pause to set the stage
        _visualPause("Starting buy order simulation - watch how trailing stop works");
        _visualPause("Phase 1: Price drops, stop price follows downward");

        // Phase 1: 3 Price Drops (Stop price follows downward)
        console.log("PHASE 1: PRICE DROPS (STOP PRICE FOLLOWS DOWNWARD)");
        console.log("==================================================");
        console.log("Strategy: Stop price trails behind falling ETH price");
        console.log("Purpose: Ensure good entry prices as price moves favorably");
        console.log("");

        int256[] memory priceDrops = new int256[](3);
        priceDrops[0] = -50e8;   // Drop $50
        priceDrops[1] = -75e8;    // Drop $75 more
        priceDrops[2] = -100e8;   // Drop $100 more

        int256 accumulatedPrice = currentPrice;
        uint256 currentStopPrice = INITIAL_ETH_PRICE + (INITIAL_ETH_PRICE * TRAILING_DISTANCE / 10000);

        for (uint i = 0; i < priceDrops.length; i++) {
            console.log("DROP #", i + 1, " - ==============================");
            
            // Show current price before drop
            console.log("Current ETH price: $", uint256(accumulatedPrice) / 1e8);
            console.log("Current stop price: $", currentStopPrice / 1e8);
            console.log("About to drop by: $", uint256(-priceDrops[i]) / 1e8);
            
            // Execute the price drop
            accumulatedPrice += priceDrops[i];
            ethUsdAggregator.setPrice(accumulatedPrice);
            
            // Calculate new trailing stop price (only moves DOWN for buy orders)
            uint256 newStopPrice = uint256(accumulatedPrice) + (uint256(accumulatedPrice) * TRAILING_DISTANCE / 10000);
            if (newStopPrice < currentStopPrice) {
                currentStopPrice = newStopPrice;
            }
            
            console.log("DROP EXECUTED!");
            console.log("New ETH price: $", uint256(accumulatedPrice) / 1e8);
            console.log("Drop amount: $", uint256(-priceDrops[i]) / 1e8);
            console.log("Total drop from start: $", uint256(currentPrice - accumulatedPrice) / 1e8);
            console.log("New stop price: $", currentStopPrice / 1e8);
            console.log("Stop price moved DOWN by: $", ((INITIAL_ETH_PRICE + (INITIAL_ETH_PRICE * TRAILING_DISTANCE / 10000)) - currentStopPrice) / 1e8);
            console.log("");
            
            // Time advancement
            vm.warp(block.timestamp + 300); // 5 minutes between drops
            console.log("Time advanced by 5 minutes");
            console.log("");
            
            // Visual pause for better demonstration
            _visualPause("Price drop completed - showing trailing stop adjustment");
        }

        // Longer pause between phases
        _visualPause("Phase 1 completed - transitioning to Phase 2");
        _visualPause("Now showing how stop price stays fixed during rises");

        // Phase 2: 3 Price Rises (Stop price stays fixed, triggers when crossed)
        console.log("PHASE 2: PRICE RISES (STOP PRICE STAYS FIXED)");
        console.log("==================================================");
        console.log("Strategy: Stop price stays at lowest level achieved");
        console.log("Purpose: Ensure good entry price when price reverses");
        console.log("");

        int256[] memory priceRises = new int256[](3);
        priceRises[0] = 30e8;   // Rise $30
        priceRises[1] = 50e8;    // Rise $50 more
        priceRises[2] = 70e8;    // Rise $70 more

        for (uint i = 0; i < priceRises.length; i++) {
            console.log("RISE #", i + 1, " - ==============================");
            
            // Show current price before rise
            console.log("Current ETH price: $", uint256(accumulatedPrice) / 1e8);
            console.log("Current stop price: $", currentStopPrice / 1e8);
            console.log("About to rise by: $", uint256(priceRises[i]) / 1e8);
            
            // Execute the price rise
            accumulatedPrice += priceRises[i];
            ethUsdAggregator.setPrice(accumulatedPrice);
            
            console.log("RISE EXECUTED!");
            console.log("New ETH price: $", uint256(accumulatedPrice) / 1e8);
            console.log("Rise amount: $", uint256(priceRises[i]) / 1e8);
            console.log("Total rise from low: $", uint256(accumulatedPrice - (currentPrice - 225e8)) / 1e8);
            console.log("Stop price remains: $", currentStopPrice / 1e8, "(ENSURES GOOD ENTRY!)");
            
            // Check if stop price is triggered
            if (uint256(accumulatedPrice) >= currentStopPrice) {
                console.log("STOP PRICE TRIGGERED!");
                console.log("Current price:", uint256(accumulatedPrice) / 1e8);
                console.log("Stop price:", currentStopPrice / 1e8);
                console.log("BUY ORDER EXECUTES!");
                console.log("Buying ETH at $", uint256(accumulatedPrice) / 1e8, "with 2000 USDC");
                console.log("Expected ETH amount:", (2000e6 * 1e18) / uint256(accumulatedPrice));
                break;
            } else {
                console.log("Still below stop price - order continues");
            }
            
            console.log("");
            
            // Time advancement
            vm.warp(block.timestamp + 300); // 5 minutes between rises
            console.log("Time advanced by 5 minutes");
            console.log("");
            
            // Visual pause for better demonstration
            _visualPause("Price rise completed - checking stop price trigger");
        }

        // Get final market price
        (, int256 finalPrice,,,) = ethUsdAggregator.latestRoundData();
        console.log("FINAL MARKET PRICE: $", uint256(finalPrice) / 1e8);
        console.log("");

        console.log("TRAILING STOP BUY ORDER SUMMARY");
        console.log("==================================================");
        console.log("[OK] User wants to buy ETH with 2000 USDC");
        console.log("[OK] Initial stop price: $", (INITIAL_ETH_PRICE + (INITIAL_ETH_PRICE * TRAILING_DISTANCE / 10000)) / 1e8);
        console.log("[OK] ETH price dropped to $", uint256(currentPrice - 225e8) / 1e8, "(lowest)");
        console.log("[OK] Stop price dropped to $", currentStopPrice / 1e8, "(ensured good entry)");
        console.log("[OK] ETH price rose to $", uint256(finalPrice) / 1e8);
        console.log("[OK] Order triggered at $", uint256(finalPrice) / 1e8, "(good entry price)");
        console.log("[OK] Entry price improvement: $", ((INITIAL_ETH_PRICE + (INITIAL_ETH_PRICE * TRAILING_DISTANCE / 10000)) - currentStopPrice) / 1e8);
        console.log("[OK] Strategy: Buy on rises while ensuring good entry");
    }

    function _visualPause(string memory message) internal {
        console.log("----------------------------------------");
        console.log("PAUSE:", message);
        console.log("----------------------------------------");
        console.log("Waiting 3 seconds for visual demonstration...");
        
        // Simulate a pause by advancing time
        vm.warp(block.timestamp + 3);
        
        console.log("Continuing simulation...");
        console.log("");
    }

    function _shouldExecuteBuyOrder(int256 currentPrice, int256 initialPrice, uint256 dropNumber) internal pure returns (bool) {
        // Define buying conditions
        int256 totalDrop = initialPrice - currentPrice;
        uint256 totalDropPercent = uint256(totalDrop * 10000) / uint256(initialPrice); // in basis points
        
        console.log("CHECKING BUY CONDITIONS:");
        console.log("   Total drop: $", uint256(totalDrop) / 1e8);
        console.log("   Drop percentage:", totalDropPercent / 100, "%");
        console.log("   Drop number:", dropNumber + 1);
        
        // Condition 1: Buy if price dropped more than 5%
        bool condition1 = totalDropPercent >= 500; // 5%
        console.log("   Condition 1 (5% drop):", condition1 ? "MET" : "NOT MET");
        
        // Condition 2: Buy if this is drop #3 or later (accumulate on deeper drops)
        bool condition2 = dropNumber >= 2; // Drop #3, 4, or 5
        console.log("   Condition 2 (Drop #3+):", condition2 ? "MET" : "NOT MET");
        
        // Condition 3: Buy if price is below $1900 (good entry point)
        bool condition3 = currentPrice <= 1900e8;
        console.log("   Condition 3 (Below $1900):", condition3 ? "MET" : "NOT MET");
        
        // Execute buy if any condition is met
        bool shouldBuy = condition1 || condition2 || condition3;
        console.log("   FINAL DECISION:", shouldBuy ? "BUY" : "WAIT");
        console.log("");
        
        return shouldBuy;
    }

    function _executeBuyOrder(address user, uint256 currentPrice, uint256 dropNumber) internal {
        console.log("EXECUTING BUY ORDER #", dropNumber);
        console.log("------------------------------");
        
        // Calculate buy amount based on drop (more aggressive buying at lower prices)
        uint256 buyAmount = (USDC_AMOUNT * (100 + dropNumber * 20)) / 100; // Increase buy amount by 20% per drop
        
        console.log("Buy Amount:", buyAmount / 1e6, "USDC");
        console.log("Price per ETH: $", currentPrice / 1e8);
        console.log("DCA Multiplier:", (100 + dropNumber * 20), "% (more aggressive at lower prices)");
        console.log("");
        
        // Mint additional USDC for this buy
        console.log("Minting additional USDC for this purchase...");
        mockUSDC.mint(user, buyAmount);
        console.log("Minted", buyAmount / 1e6, "USDC");
        console.log("");
        
        // Approve additional amount
        console.log("Approving protocol to spend USDC...");
        vm.prank(user);
        mockUSDC.approve(address(limitOrderProtocol), buyAmount);
        console.log("Approved", buyAmount / 1e6, "USDC for protocol");
        console.log("");
        
        // Calculate ETH amount to buy
        uint256 ethAmount = (buyAmount * 1e18) / (currentPrice * 1e6 / 1e8); // Convert USDC to ETH amount
        
        console.log("PURCHASE CALCULATION:");
        console.log("   USDC Amount:", buyAmount / 1e6, "USDC");
        console.log("   ETH Price: $", currentPrice / 1e8);
        console.log("   Expected ETH:", ethAmount / 1e18, "ETH");
        console.log("   Effective Price: $", (buyAmount * 1e8) / ethAmount, "per ETH");
        console.log("   Price vs Start: $", (INITIAL_ETH_PRICE - currentPrice) / 1e8, "discount");
        console.log("");
    }
}
