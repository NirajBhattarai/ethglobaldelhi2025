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
 * @title SellOrderScenarioScript
 * @notice Demo script showcasing sell order trailing stop functionality
 * @dev This script demonstrates selling ETH for USDC using trailing stop orders
 */
contract SellOrderScenarioScript is Script {
    // Demo contracts
    MockWETH public mockWETH;
    MockERC20 public mockUSDC;
    MockChainlinkAggregator public ethUsdAggregator;
    TrailingStopOrder public trailingStopOrder;
    TrailingStopKeeper public keeper;
    LimitOrderProtocol public limitOrderProtocol;

    // Demo parameters
    uint256 constant INITIAL_ETH_PRICE = 2000e8; // $2000
    uint256 constant TRAILING_DISTANCE = 500; // 5% trailing distance in basis points
    uint256 constant ORDER_AMOUNT = 1e18; // 1 ETH
    uint256 constant USDC_AMOUNT = 2000e6; // 2000 USDC

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("============================================================");
        console.log("SELL ORDER TRAILING STOP DEMO - PROFIT PROTECTION STRATEGY");
        console.log("============================================================");
        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance / 1e18, "ETH");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock contracts
        _deployMockContracts();

        // Deploy main contracts
        _deployMainContracts();

        vm.stopBroadcast();

        // Run sell order demo
        _demoSellOrder();
        _simulatePriceMovements();

        console.log("=== SELL ORDER DEMO COMPLETED SUCCESSFULLY ===");
    }

    function _deployMockContracts() internal {
        console.log("\n--- Deploying Mock Contracts ---");

        // Deploy Mock WETH
        mockWETH = new MockWETH();
        console.log("MockWETH deployed at:", address(mockWETH));

        // Deploy Mock USDC
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);
        console.log("MockUSDC deployed at:", address(mockUSDC));

        // Deploy Mock Chainlink Aggregator
        ethUsdAggregator = new MockChainlinkAggregator(8, "ETH / USD");
        console.log("ETH/USD Aggregator deployed at:", address(ethUsdAggregator));

        // Set initial price
        ethUsdAggregator.setPrice(int256(INITIAL_ETH_PRICE));
        console.log("Initial ETH price set to: $", INITIAL_ETH_PRICE / 1e8);
    }

    function _deployMainContracts() internal {
        console.log("\n--- Deploying Main Contracts ---");

        // Deploy LimitOrderProtocol
        limitOrderProtocol = new LimitOrderProtocol(IWETH(address(mockWETH)));
        console.log("LimitOrderProtocol deployed at:", address(limitOrderProtocol));

        // Deploy TrailingStopOrder
        trailingStopOrder = new TrailingStopOrder(address(limitOrderProtocol));
        console.log("TrailingStopOrder deployed at:", address(trailingStopOrder));

        // Deploy Keeper
        keeper = new TrailingStopKeeper(address(trailingStopOrder));
        console.log("TrailingStopKeeper deployed at:", address(keeper));
    }

    function _demoSellOrder() internal {
        console.log("\n=== DEMO: SELL ORDER SCENARIO ===");

        address user = vm.addr(vm.envUint("PRIVATE_KEY"));

        // Setup: User has ETH and wants to sell with trailing stop
        console.log("Setting up sell order scenario...");

        // Mint WETH to user
        mockWETH.mint(user, ORDER_AMOUNT);
        console.log("Minted", ORDER_AMOUNT / 1e18, "WETH to user");

        // User approves the protocol
        vm.prank(user);
        mockWETH.approve(address(limitOrderProtocol), ORDER_AMOUNT);
        console.log("User approved protocol to spend WETH");

        // Create sell order (sell ETH for USDC with trailing stop)
        IOrderMixin.Order memory orderInfo = IOrderMixin.Order({
            salt: 0,
            maker: Address.wrap(uint160(user)),
            receiver: Address.wrap(uint160(user)),
            makerAsset: Address.wrap(uint160(address(mockWETH))),
            takerAsset: Address.wrap(uint160(address(mockUSDC))),
            makingAmount: ORDER_AMOUNT,
            takingAmount: USDC_AMOUNT,
            makerTraits: MakerTraits.wrap(0)
        });

        // Create trailing stop extension data
        TrailingStopOrder.TrailingStopConfig memory config = TrailingStopOrder.TrailingStopConfig({
            makerAssetOracle: ethUsdAggregator,
            takerAssetOracle: ethUsdAggregator,
            initialStopPrice: INITIAL_ETH_PRICE - (INITIAL_ETH_PRICE * TRAILING_DISTANCE / 10000), // $1900 (5% below $2000)
            trailingDistance: TRAILING_DISTANCE,
            currentStopPrice: INITIAL_ETH_PRICE - (INITIAL_ETH_PRICE * TRAILING_DISTANCE / 10000),
            configuredAt: block.timestamp,
            lastUpdateAt: block.timestamp,
            updateFrequency: 60, // 1 minute
            maxSlippage: 100, // 1%
            maxPriceDeviation: 200, // 2%
            twapWindow: 300, // 5 minutes
            keeper: address(keeper),
            orderMaker: user,
            orderType: TrailingStopOrder.OrderType.SELL,
            makerAssetDecimals: 18,
            takerAssetDecimals: 6
        });

        // Place the order
        vm.prank(user);
        bytes32 orderHash = limitOrderProtocol.hashOrder(orderInfo);

        // Configure trailing stop
        vm.prank(user);
        trailingStopOrder.configureTrailingStop(orderHash, config);

        console.log("Sell order placed!");
        console.log("Order hash:", vm.toString(orderHash));
        console.log("Initial stop price: $", config.initialStopPrice / 1e8);
        console.log("Trailing distance: ", TRAILING_DISTANCE / 100, "%");
        console.log("Order type: SELL (stop loss when price goes down)");
    }

    function _simulatePriceMovements() internal {
        console.log("\n============================================================");
        console.log("SIMULATING TRAILING STOP PRICE MOVEMENTS - SELL ORDER");
        console.log("============================================================");

        (, int256 currentPrice,,,) = ethUsdAggregator.latestRoundData();
        console.log("Starting ETH price: $", uint256(currentPrice) / 1e8);
        console.log("Initial stop price: $", (INITIAL_ETH_PRICE - (INITIAL_ETH_PRICE * TRAILING_DISTANCE / 10000)) / 1e8);
        console.log("Trailing distance: ", TRAILING_DISTANCE / 100, "%");
        console.log("");

        // Visual pause to set the stage
        _visualPause("Starting sell order simulation - watch how trailing stop works");
        _visualPause("Phase 1: Price rises, stop price follows upward");

        // Phase 1: 3 Price Rises (Stop price follows upward)
        console.log("PHASE 1: PRICE RISES (STOP PRICE FOLLOWS UPWARD)");
        console.log("==================================================");
        console.log("Strategy: Stop price trails behind rising ETH price");
        console.log("Purpose: Lock in profits as price moves favorably");
        console.log("");

        int256[] memory priceRises = new int256[](3);
        priceRises[0] = 50e8;   // Rise $50
        priceRises[1] = 75e8;    // Rise $75 more
        priceRises[2] = 100e8;   // Rise $100 more

        int256 accumulatedPrice = currentPrice;
        uint256 currentStopPrice = INITIAL_ETH_PRICE - (INITIAL_ETH_PRICE * TRAILING_DISTANCE / 10000);

        for (uint i = 0; i < priceRises.length; i++) {
            console.log("RISE #", i + 1, " - ==============================");
            
            // Show current price before rise
            console.log("Current ETH price: $", uint256(accumulatedPrice) / 1e8);
            console.log("Current stop price: $", currentStopPrice / 1e8);
            console.log("About to rise by: $", uint256(priceRises[i]) / 1e8);
            
            // Execute the price rise
            accumulatedPrice += priceRises[i];
            ethUsdAggregator.setPrice(accumulatedPrice);
            
            // Calculate new trailing stop price (only moves UP for sell orders)
            uint256 newStopPrice = uint256(accumulatedPrice) - (uint256(accumulatedPrice) * TRAILING_DISTANCE / 10000);
            if (newStopPrice > currentStopPrice) {
                currentStopPrice = newStopPrice;
            }
            
            console.log("RISE EXECUTED!");
            console.log("New ETH price: $", uint256(accumulatedPrice) / 1e8);
            console.log("Rise amount: $", uint256(priceRises[i]) / 1e8);
            console.log("Total rise from start: $", uint256(accumulatedPrice - currentPrice) / 1e8);
            console.log("New stop price: $", currentStopPrice / 1e8);
            console.log("Stop price moved UP by: $", (currentStopPrice - (INITIAL_ETH_PRICE - (INITIAL_ETH_PRICE * TRAILING_DISTANCE / 10000))) / 1e8);
            console.log("");
            
            // Time advancement
            vm.warp(block.timestamp + 300); // 5 minutes between rises
            console.log("Time advanced by 5 minutes");
            console.log("");
            
            // Visual pause for better demonstration
            _visualPause("Price rise completed - showing trailing stop adjustment");
        }

        // Longer pause between phases
        _visualPause("Phase 1 completed - transitioning to Phase 2");
        _visualPause("Now showing how stop price stays fixed during drops");

        // Phase 2: 3 Price Drops (Stop price stays fixed, triggers when crossed)
        console.log("PHASE 2: PRICE DROPS (STOP PRICE STAYS FIXED)");
        console.log("==================================================");
        console.log("Strategy: Stop price stays at highest level achieved");
        console.log("Purpose: Protect profits when price reverses");
        console.log("");

        int256[] memory priceDrops = new int256[](3);
        priceDrops[0] = -30e8;   // Drop $30
        priceDrops[1] = -50e8;    // Drop $50 more
        priceDrops[2] = -70e8;    // Drop $70 more

        for (uint i = 0; i < priceDrops.length; i++) {
            console.log("DROP #", i + 1, " - ==============================");
            
            // Show current price before drop
            console.log("Current ETH price: $", uint256(accumulatedPrice) / 1e8);
            console.log("Current stop price: $", currentStopPrice / 1e8);
            console.log("About to drop by: $", uint256(-priceDrops[i]) / 1e8);
            
            // Execute the price drop
            accumulatedPrice += priceDrops[i];
            ethUsdAggregator.setPrice(accumulatedPrice);
            
            console.log("DROP EXECUTED!");
            console.log("New ETH price: $", uint256(accumulatedPrice) / 1e8);
            console.log("Drop amount: $", uint256(-priceDrops[i]) / 1e8);
            console.log("Total drop from peak: $", uint256((currentPrice + 225e8) - accumulatedPrice) / 1e8);
            console.log("Stop price remains: $", currentStopPrice / 1e8, "(PROTECTS PROFIT!)");
            
            // Check if stop price is triggered
            if (uint256(accumulatedPrice) <= currentStopPrice) {
                console.log("STOP PRICE TRIGGERED!");
                console.log("Current price:", uint256(accumulatedPrice) / 1e8);
                console.log("Stop price:", currentStopPrice / 1e8);
                console.log("SELL ORDER EXECUTES!");
                console.log("Selling 1 ETH at $", uint256(accumulatedPrice) / 1e8);
                console.log("Expected USDC amount: $", uint256(accumulatedPrice) / 1e8);
                break;
            } else {
                console.log("Still above stop price - order continues");
            }
            
            console.log("");
            
            // Time advancement
            vm.warp(block.timestamp + 300); // 5 minutes between drops
            console.log("Time advanced by 5 minutes");
            console.log("");
            
            // Visual pause for better demonstration
            _visualPause("Price drop completed - checking stop price trigger");
        }

        // Get final market price
        (, int256 finalPrice,,,) = ethUsdAggregator.latestRoundData();
        console.log("FINAL MARKET PRICE: $", uint256(finalPrice) / 1e8);
        console.log("");

        console.log("TRAILING STOP SELL ORDER SUMMARY");
        console.log("==================================================");
        console.log("[OK] User held 1 ETH worth $", INITIAL_ETH_PRICE / 1e8);
        console.log("[OK] Initial stop price: $", (INITIAL_ETH_PRICE - (INITIAL_ETH_PRICE * TRAILING_DISTANCE / 10000)) / 1e8);
        console.log("[OK] ETH price rose to $", uint256(currentPrice + 225e8) / 1e8, "(peak)");
        console.log("[OK] Stop price rose to $", currentStopPrice / 1e8, "(locked in profit)");
        console.log("[OK] ETH price dropped to $", uint256(finalPrice) / 1e8);
        console.log("[OK] Order triggered at $", uint256(finalPrice) / 1e8, "(protected profit)");
        console.log("[OK] Profit protected: $", (currentStopPrice - (INITIAL_ETH_PRICE - (INITIAL_ETH_PRICE * TRAILING_DISTANCE / 10000))) / 1e8);
        console.log("[OK] Strategy: Sell on dips while protecting gains");
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
}
