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
 * @title TrailingStopDemoScript
 * @notice Comprehensive demo script for Sepolia showcasing trailing stop functionality
 * @dev This script demonstrates buy orders, sell orders, and trigger operations
 */
contract TrailingStopDemoScript is Script {
    // Sepolia-specific addresses
    address constant SEPOLIA_WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;

    // Demo contracts
    MockWETH public mockWETH;
    MockERC20 public mockUSDC;
    MockChainlinkAggregator public ethUsdAggregator;
    TrailingStopOrder public trailingStopOrder;
    TrailingStopKeeper public keeper;
    LimitOrderProtocol public limitOrderProtocol;

    // Demo parameters
    uint256 constant INITIAL_ETH_PRICE = 2000e8; // $2000
    uint256 constant TRAILING_DISTANCE = 50e8; // $50 trailing distance
    uint256 constant ORDER_AMOUNT = 1e18; // 1 ETH
    uint256 constant USDC_AMOUNT = 2000e6; // 2000 USDC

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== TRAILING STOP DEMO FOR SEPOLIA ===");
        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance / 1e18, "ETH");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock contracts
        _deployMockContracts();

        // Deploy main contracts
        _deployMainContracts();

        vm.stopBroadcast();

        // Run demo scenarios
        _demoSellOrder();
        _demoBuyOrder();
        _demoTriggerOperations();
        _demoKeeperOperations();

        console.log("=== DEMO COMPLETED SUCCESSFULLY ===");
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
            initialStopPrice: INITIAL_ETH_PRICE - TRAILING_DISTANCE, // $1950
            trailingDistance: TRAILING_DISTANCE,
            currentStopPrice: INITIAL_ETH_PRICE - TRAILING_DISTANCE,
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
        console.log("Trailing distance: $", TRAILING_DISTANCE / 1e8);

        // Simulate price movements
        _simulatePriceMovements(orderHash, false);
    }

    function _demoBuyOrder() internal {
        console.log("\n=== DEMO: BUY ORDER SCENARIO ===");

        address user = vm.addr(vm.envUint("PRIVATE_KEY"));

        // Setup: User has USDC and wants to buy ETH with trailing stop
        console.log("Setting up buy order scenario...");

        // Mint USDC to user
        mockUSDC.mint(user, USDC_AMOUNT);
        console.log("Minted", USDC_AMOUNT / 1e6, "USDC to user");

        // User approves the protocol
        vm.prank(user);
        mockUSDC.approve(address(limitOrderProtocol), USDC_AMOUNT);
        console.log("User approved protocol to spend USDC");

        // Create buy order (buy ETH with USDC using trailing stop)
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

        // Create trailing stop extension data for buy order
        TrailingStopOrder.TrailingStopConfig memory config = TrailingStopOrder.TrailingStopConfig({
            makerAssetOracle: ethUsdAggregator,
            takerAssetOracle: ethUsdAggregator,
            initialStopPrice: INITIAL_ETH_PRICE + TRAILING_DISTANCE, // $2050
            trailingDistance: TRAILING_DISTANCE,
            currentStopPrice: INITIAL_ETH_PRICE + TRAILING_DISTANCE,
            configuredAt: block.timestamp,
            lastUpdateAt: block.timestamp,
            updateFrequency: 60, // 1 minute
            maxSlippage: 100, // 1%
            maxPriceDeviation: 200, // 2%
            twapWindow: 300, // 5 minutes
            keeper: address(keeper),
            orderMaker: user,
            orderType: TrailingStopOrder.OrderType.BUY,
            makerAssetDecimals: 6,
            takerAssetDecimals: 18
        });

        // Place the order
        vm.prank(user);
        bytes32 orderHash = limitOrderProtocol.hashOrder(orderInfo);

        // Configure trailing stop
        vm.prank(user);
        trailingStopOrder.configureTrailingStop(orderHash, config);

        console.log("Buy order placed!");
        console.log("Order hash:", vm.toString(orderHash));
        console.log("Initial stop price: $", config.initialStopPrice / 1e8);
        console.log("Trailing distance: $", TRAILING_DISTANCE / 1e8);

        // Simulate price movements
        _simulatePriceMovements(orderHash, true);
    }

    function _simulatePriceMovements(bytes32 orderHash, bool isBuyOrder) internal {
        console.log("\n--- Simulating Price Movements ---");

        // Get current price
        (, int256 currentPrice,,,) = ethUsdAggregator.latestRoundData();
        console.log("Current ETH price: $", uint256(currentPrice) / 1e8);

        // Simulate favorable price movement (up for sell orders, down for buy orders)
        int256 newPrice;
        if (isBuyOrder) {
            // For buy orders, price goes down (favorable)
            newPrice = currentPrice - 100e8; // Price drops by $100
            console.log("Price drops to $", uint256(newPrice) / 1e8, "(favorable for buy order)");
        } else {
            // For sell orders, price goes up (favorable)
            newPrice = currentPrice + 100e8; // Price rises by $100
            console.log("Price rises to $", uint256(newPrice) / 1e8, "(favorable for sell order)");
        }

        ethUsdAggregator.setPrice(newPrice);

        // Update trailing stop
        vm.prank(address(keeper));
        bool updated = keeper._processOrder(orderHash);
        console.log("Trailing stop updated:", updated);

        // Get updated order info
        (,,,, uint256 currentStopPrice,,,,,,,,,,,) = trailingStopOrder.trailingStopConfigs(orderHash);
        console.log("Updated stop price: $", currentStopPrice / 1e8);

        // Simulate unfavorable price movement (trigger condition)
        if (isBuyOrder) {
            // For buy orders, price goes up (unfavorable - triggers order)
            newPrice = newPrice + 200e8; // Price rises significantly
            console.log("Price rises to $", uint256(newPrice) / 1e8, "(triggers buy order)");
        } else {
            // For sell orders, price goes down (unfavorable - triggers order)
            newPrice = newPrice - 200e8; // Price drops significantly
            console.log("Price drops to $", uint256(newPrice) / 1e8, "(triggers sell order)");
        }

        ethUsdAggregator.setPrice(newPrice);

        // Check if order should be triggered
        (bool shouldTrigger,,,) = trailingStopOrder.isTrailingStopTriggered(orderHash);
        console.log("Order should trigger:", shouldTrigger);
    }

    function _demoTriggerOperations() internal {
        console.log("\n=== DEMO: TRIGGER OPERATIONS ===");

        // Create a test order for trigger demonstration
        address user = vm.addr(vm.envUint("PRIVATE_KEY"));

        // Create a simple order
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

        TrailingStopOrder.TrailingStopConfig memory config = TrailingStopOrder.TrailingStopConfig({
            makerAssetOracle: ethUsdAggregator,
            takerAssetOracle: ethUsdAggregator,
            initialStopPrice: INITIAL_ETH_PRICE - TRAILING_DISTANCE,
            trailingDistance: TRAILING_DISTANCE,
            currentStopPrice: INITIAL_ETH_PRICE - TRAILING_DISTANCE,
            configuredAt: block.timestamp,
            lastUpdateAt: block.timestamp,
            updateFrequency: 60,
            maxSlippage: 100,
            maxPriceDeviation: 200,
            twapWindow: 300,
            keeper: address(keeper),
            orderMaker: user,
            orderType: TrailingStopOrder.OrderType.SELL,
            makerAssetDecimals: 18,
            takerAssetDecimals: 6
        });

        vm.prank(user);
        bytes32 orderHash = limitOrderProtocol.hashOrder(orderInfo);

        // Configure trailing stop
        vm.prank(user);
        trailingStopOrder.configureTrailingStop(orderHash, config);

        console.log("Test order created for trigger demo");
        console.log("Order hash:", vm.toString(orderHash));

        // Demonstrate trigger check
        (bool shouldTrigger,,,) = trailingStopOrder.isTrailingStopTriggered(orderHash);
        console.log("Should trigger order:", shouldTrigger);

        // Get order data
        (,,,, uint256 currentStopPrice,,,,,,,,,,,) = trailingStopOrder.trailingStopConfigs(orderHash);
        console.log("Current stop price: $", currentStopPrice / 1e8);

        // Get current market price
        (, int256 currentPrice,,,) = ethUsdAggregator.latestRoundData();
        console.log("Current market price: $", uint256(currentPrice) / 1e8);

        // Calculate trigger condition
        if (config.orderType == TrailingStopOrder.OrderType.BUY) {
            console.log("Buy order trigger condition: market price >= stop price");
            console.log("Trigger condition met:", uint256(currentPrice) >= currentStopPrice);
        } else {
            console.log("Sell order trigger condition: market price <= stop price");
            console.log("Trigger condition met:", uint256(currentPrice) <= currentStopPrice);
        }
    }

    function _demoKeeperOperations() internal {
        console.log("\n=== DEMO: KEEPER OPERATIONS ===");

        console.log("Keeper contract address:", address(keeper));
        console.log("TrailingStopOrder contract:", address(trailingStopOrder));

        // Demonstrate keeper stats
        console.log("Keeper stats:");
        console.log("- Last processed block:", keeper.lastProcessedBlock());
        console.log("- Total orders processed:", keeper.totalOrdersProcessed());
        console.log("- Total updates performed:", keeper.totalUpdatesPerformed());

        // Create multiple orders for batch processing demo
        address user = vm.addr(vm.envUint("PRIVATE_KEY"));

        bytes32[] memory orderHashes = new bytes32[](3);

        for (uint256 i = 0; i < 3; i++) {
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

            TrailingStopOrder.TrailingStopConfig memory config = TrailingStopOrder.TrailingStopConfig({
                makerAssetOracle: ethUsdAggregator,
                takerAssetOracle: ethUsdAggregator,
                initialStopPrice: INITIAL_ETH_PRICE - TRAILING_DISTANCE,
                trailingDistance: TRAILING_DISTANCE,
                currentStopPrice: INITIAL_ETH_PRICE - TRAILING_DISTANCE,
                configuredAt: block.timestamp,
                lastUpdateAt: block.timestamp,
                updateFrequency: 60,
                maxSlippage: 100,
                maxPriceDeviation: 200,
                twapWindow: 300,
                keeper: address(keeper),
                orderMaker: user,
                orderType: TrailingStopOrder.OrderType.SELL,
                makerAssetDecimals: 18,
                takerAssetDecimals: 6
            });

            vm.prank(user);
            orderHashes[i] = limitOrderProtocol.hashOrder(orderInfo);

            // Configure trailing stop
            vm.prank(user);
            trailingStopOrder.configureTrailingStop(orderHashes[i], config);
        }

        console.log("Created 3 orders for batch processing demo");

        // Simulate price movement
        ethUsdAggregator.setPrice(int256(INITIAL_ETH_PRICE + 50e8));
        console.log("Price updated to trigger trailing stop updates");

        // Process orders individually
        for (uint256 i = 0; i < orderHashes.length; i++) {
            vm.prank(address(keeper));
            bool updated = keeper._processOrder(orderHashes[i]);
            console.log("Order", i + 1, "updated:", updated);
        }

        console.log("Batch processing completed");
        console.log("Updated keeper stats:");
        console.log("- Total orders processed:", keeper.totalOrdersProcessed());
        console.log("- Total updates performed:", keeper.totalUpdatesPerformed());
    }
}
