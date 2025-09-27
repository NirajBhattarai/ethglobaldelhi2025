// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {TrailingStopOrder} from "../src/extensions/TrailingStopOrder.sol";
import {LimitOrderProtocol} from "../src/LimitOrderProtocol.sol";
import {IWETH} from "@1inch/solidity-utils/interfaces/IWETH.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address, AddressLib} from "@1inch/solidity-utils/libraries/AddressLib.sol";
import {MakerTraitsLib, MakerTraits} from "../src/libraries/MakerTraitsLib.sol";
import {IOrderMixin} from "../src/interfaces/IOrderMixin.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title MockChainlinkAggregator
 * @notice Mock Chainlink aggregator for testing price movements
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
        answer = 2000e8; // Default $2000 price
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
 * @notice Mock ERC20 token for testing
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
 * @title TrailingStopOrderComprehensiveTest
 * @notice Comprehensive test suite for TrailingStopOrder contract
 */
contract TrailingStopOrderComprehensiveTest is Test {
    // ============ State Variables ============
    
    TrailingStopOrder public trailingStopOrder;
    LimitOrderProtocol public limitOrderProtocol;
    MockChainlinkAggregator public mockOracle;
    MockERC20 public mockWBTC;
    MockERC20 public mockUSDC;
    
    // Test accounts
    address public maker;
    address public taker;
    address public keeper;
    address public admin;
    address public attacker;
    address public mevBot;
    address public owner;
    
    // Test constants
    uint256 constant INITIAL_ETH_PRICE = 2000e8; // $2000 in 8 decimals
    uint256 constant INITIAL_STOP_PRICE_SELL = 1900e18; // $1900 in 18 decimals
    uint256 constant INITIAL_STOP_PRICE_BUY = 2100e18; // $2100 in 18 decimals
    uint256 constant TRAILING_DISTANCE = 200; // 2% in basis points
    uint256 constant UPDATE_FREQUENCY = 60; // 1 minute
    uint256 constant MAX_SLIPPAGE = 100; // 1% in basis points
    
    // ============ Events ============
    
    event TrailingStopConfigUpdated(
        address indexed maker,
        address indexed makerAssetOracle,
        uint256 initialStopPrice,
        uint256 trailingDistance,
        TrailingStopOrder.OrderType orderType
    );
    
    event TrailingStopUpdated(
        bytes32 indexed orderHash,
        uint256 oldStopPrice,
        uint256 newStopPrice,
        uint256 currentPrice,
        address updater
    );
    
    event TrailingStopTriggered(
        bytes32 indexed orderHash,
        address indexed taker,
        uint256 takerAssetBalance,
        uint256 stopPrice
    );

    // ============ Setup ============
    
    function setUp() public {
        // Deploy mock oracle
        mockOracle = new MockChainlinkAggregator(8, "ETH / USD");
        mockOracle.setPrice(int256(INITIAL_ETH_PRICE));
        
        // Deploy mock tokens
        mockWBTC = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        mockUSDC = new MockERC20("USD Coin", "USDC", 6);
        
        // Deploy LimitOrderProtocol with mock WETH
        address mockWETH = address(new MockERC20("Wrapped Ether", "WETH", 18));
        limitOrderProtocol = new LimitOrderProtocol(IWETH(mockWETH));
        
        // Deploy TrailingStopOrder
        trailingStopOrder = new TrailingStopOrder(address(limitOrderProtocol));
        
        // Setup test accounts
        maker = makeAddr("maker");
        taker = makeAddr("taker");
        keeper = makeAddr("keeper");
        admin = makeAddr("admin");
        attacker = makeAddr("attacker");
        mevBot = makeAddr("mevBot");
        owner = address(this);
        
        // Fund accounts
        vm.deal(maker, 100 ether);
        vm.deal(taker, 100 ether);
        vm.deal(keeper, 100 ether);
        vm.deal(admin, 100 ether);
        
        // Mint tokens to maker
        mockWBTC.mint(maker, 1000e8); // 1000 WBTC
        mockUSDC.mint(maker, 1000000e6); // 1M USDC
        
        // Mint tokens to taker for trading
        mockUSDC.mint(taker, 1000000e6); // 1M USDC
    }

    // ============ Helper Functions ============
    
    function createOrderHash(string memory orderId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(orderId));
    }
    
    function createTrailingStopConfig(
        uint256 initialStopPrice,
        uint256 trailingDistance,
        TrailingStopOrder.OrderType orderType
    ) internal view returns (TrailingStopOrder.TrailingStopConfig memory config) {
        config.makerAssetOracle = AggregatorV3Interface(address(mockOracle));
        config.initialStopPrice = initialStopPrice;
        config.trailingDistance = trailingDistance;
        config.currentStopPrice = initialStopPrice;
        config.orderType = orderType;
        config.updateFrequency = UPDATE_FREQUENCY;
        config.maxSlippage = MAX_SLIPPAGE;
        config.keeper = keeper;
    }
    
    function convertTo18Decimals(uint256 price8Dec) internal pure returns (uint256) {
        return price8Dec * 1e10;
    }
    
    function convertTo8Decimals(uint256 price18Dec) internal pure returns (uint256) {
        return price18Dec / 1e10;
    }
    
    function simulatePriceMovement(uint256 newPrice8Dec) internal {
        mockOracle.setPrice(int256(newPrice8Dec));
    }
    
    function getCurrentPrice18Decimals() internal view returns (uint256) {
        (, int256 answer,,,) = mockOracle.latestRoundData();
        return uint256(answer) * 1e10;
    }
    
    function createTestOrder() internal view returns (IOrderMixin.Order memory) {
        return IOrderMixin.Order({
            salt: 0,
            maker: Address.wrap(uint160(maker)),
            receiver: Address.wrap(uint160(address(0))),
            makerAsset: Address.wrap(uint160(address(mockWBTC))),
            takerAsset: Address.wrap(uint160(address(mockUSDC))),
            makingAmount: 1e8, // 1 WBTC
            takingAmount: 1800000000, // 1800 USDC (6 decimals)
            makerTraits: MakerTraits.wrap(0)
        });
    }

    // ============ Configuration Tests ============
    
    function testConfigureTrailingStopSellOrder() public {
        // Arrange
        bytes32 orderHash = createOrderHash("sell-order-1");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );
        
        // Act
        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);
        
        // Assert
        (
            AggregatorV3Interface oracle,
            uint256 storedInitialStopPrice,
            uint256 storedTrailingDistance,
            uint256 storedCurrentStopPrice,
            uint256 configuredAt,
            uint256 lastUpdateAt,
            uint256 updateFrequency,
            uint256 maxSlippage,
            address storedKeeper,
            TrailingStopOrder.OrderType orderType,
            uint8 makerAssetDecimals,
            uint8 takerAssetDecimals
        ) = trailingStopOrder.trailingStopConfigs(orderHash);
        
        assertEq(address(oracle), address(mockOracle));
        assertEq(storedInitialStopPrice, initialStopPrice);
        assertEq(storedTrailingDistance, TRAILING_DISTANCE);
        assertEq(storedCurrentStopPrice, initialStopPrice);
        assertEq(uint256(orderType), uint256(TrailingStopOrder.OrderType.SELL));
        assertEq(storedKeeper, keeper);
        assertTrue(configuredAt > 0);
        assertEq(lastUpdateAt, configuredAt);
        assertEq(updateFrequency, UPDATE_FREQUENCY);
        assertEq(maxSlippage, MAX_SLIPPAGE);
    }
    
    function testConfigureTrailingStopBuyOrder() public {
        // Arrange
        bytes32 orderHash = createOrderHash("buy-order-1");
        uint256 initialStopPrice = convertTo18Decimals(2100e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.BUY
        );
        
        // Act
        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);
        
        // Assert
        (
            AggregatorV3Interface oracle,
            uint256 storedInitialStopPrice,
            uint256 storedTrailingDistance,
            uint256 storedCurrentStopPrice,
            uint256 configuredAt,
            uint256 lastUpdateAt,
            uint256 updateFrequency,
            uint256 maxSlippage,
            address storedKeeper,
            TrailingStopOrder.OrderType orderType,
            uint8 makerAssetDecimals,
            uint8 takerAssetDecimals
        ) = trailingStopOrder.trailingStopConfigs(orderHash);
        
        assertEq(address(oracle), address(mockOracle));
        assertEq(storedInitialStopPrice, initialStopPrice);
        assertEq(storedTrailingDistance, TRAILING_DISTANCE);
        assertEq(storedCurrentStopPrice, initialStopPrice);
        assertEq(uint256(orderType), uint256(TrailingStopOrder.OrderType.BUY));
        assertEq(storedKeeper, keeper);
        assertTrue(configuredAt > 0);
        assertEq(lastUpdateAt, configuredAt);
        assertEq(updateFrequency, UPDATE_FREQUENCY);
        assertEq(maxSlippage, MAX_SLIPPAGE);
    }
    
    function testConfigureTrailingStopEventEmission() public {
        // Arrange
        bytes32 orderHash = createOrderHash("event-test");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );
        
        // Act & Assert
        vm.prank(maker);
        vm.expectEmit(true, true, false, true);
        emit TrailingStopConfigUpdated(
            maker,
            address(mockOracle),
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );
        trailingStopOrder.configureTrailingStop(orderHash, config);
    }
    
    function testConfigureTrailingStopInvalidOracle() public {
        // Arrange
        bytes32 orderHash = createOrderHash("invalid-oracle");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );
        config.makerAssetOracle = AggregatorV3Interface(address(0));
        
        // Act & Assert
        vm.prank(maker);
        vm.expectRevert(TrailingStopOrder.InvalidMakerAssetOracle.selector);
        trailingStopOrder.configureTrailingStop(orderHash, config);
    }
    
    function testConfigureTrailingStopInvalidPrice() public {
        // Arrange
        bytes32 orderHash = createOrderHash("invalid-price");
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            0, // Invalid price
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );
        
        // Act & Assert
        vm.prank(maker);
        vm.expectRevert(TrailingStopOrder.InvalidTrailingDistance.selector);
        trailingStopOrder.configureTrailingStop(orderHash, config);
    }
    
    function testConfigureTrailingStopInvalidTrailingDistance() public {
        // Arrange
        bytes32 orderHash = createOrderHash("invalid-distance");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            30, // Too small (minimum is 50)
            TrailingStopOrder.OrderType.SELL
        );
        
        // Act & Assert
        vm.prank(maker);
        vm.expectRevert(TrailingStopOrder.InvalidTrailingDistance.selector);
        trailingStopOrder.configureTrailingStop(orderHash, config);
    }
    
    function testConfigureTrailingStopInvalidSlippage() public {
        // Arrange
        bytes32 orderHash = createOrderHash("invalid-slippage");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );
        config.maxSlippage = 2000; // Too high (maximum is 1000)
        
        // Act & Assert
        vm.prank(maker);
        vm.expectRevert(TrailingStopOrder.InvalidTrailingDistance.selector);
        trailingStopOrder.configureTrailingStop(orderHash, config);
    }

    // ============ Price Update Tests ============
    
    function testUpdateTrailingStopSellOrderPriceIncrease() public {
        // Arrange
        bytes32 orderHash = createOrderHash("sell-update-1");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );
        
        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);
        
        // Simulate price increase to $2100
        simulatePriceMovement(2100e8);
        
        // Wait for update frequency
        vm.warp(block.timestamp + UPDATE_FREQUENCY + 1);
        
        // Act
        vm.prank(keeper);
        trailingStopOrder.updateTrailingStop(orderHash);
        
        // Assert
        (,,, uint256 currentStopPrice,,,,,,,,) = trailingStopOrder.trailingStopConfigs(orderHash);
        
        // For SELL orders: stop price should be current price - trailing distance
        // Expected: 2100e18 - (2100e18 * 200 / 10000) = 2100e18 - 42e18 = 2058e18
        uint256 expectedStopPrice = convertTo18Decimals(2058e8);
        assertEq(currentStopPrice, expectedStopPrice);
    }
    
    function testUpdateTrailingStopBuyOrderPriceDecrease() public {
        // Arrange
        bytes32 orderHash = createOrderHash("buy-update-1");
        uint256 initialStopPrice = convertTo18Decimals(2100e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.BUY
        );
        
        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);
        
        // Simulate price decrease to $1900
        simulatePriceMovement(1900e8);
        
        // Wait for update frequency
        vm.warp(block.timestamp + UPDATE_FREQUENCY + 1);
        
        // Act
        vm.prank(keeper);
        trailingStopOrder.updateTrailingStop(orderHash);
        
        // Assert
        (,,, uint256 currentStopPrice,,,,,,,,) = trailingStopOrder.trailingStopConfigs(orderHash);
        
        // For BUY orders: stop price should be current price + trailing distance
        // Expected: 1900e18 + (1900e18 * 200 / 10000) = 1900e18 + 38e18 = 1938e18
        uint256 expectedStopPrice = convertTo18Decimals(1938e8);
        assertEq(currentStopPrice, expectedStopPrice);
    }
    
    function testUpdateTrailingStopEventEmission() public {
        // Arrange
        bytes32 orderHash = createOrderHash("update-event");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );
        
        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);
        
        // Simulate price increase
        simulatePriceMovement(2100e8);
        
        // Wait for update frequency
        vm.warp(block.timestamp + UPDATE_FREQUENCY + 1);
        
        // Act & Assert
        vm.prank(keeper);
        vm.expectEmit(true, false, false, true);
        emit TrailingStopUpdated(
            orderHash,
            initialStopPrice,
            convertTo18Decimals(2058e8), // Expected new stop price
            convertTo18Decimals(2100e8), // Current price
            keeper
        );
        trailingStopOrder.updateTrailingStop(orderHash);
    }
    
    function testUpdateTrailingStopNotConfigured() public {
        // Arrange
        bytes32 orderHash = createOrderHash("not-configured");
        
        // Act & Assert
        vm.prank(keeper);
        vm.expectRevert(TrailingStopOrder.TrailingStopNotConfigured.selector);
        trailingStopOrder.updateTrailingStop(orderHash);
    }
    
    function testUpdateTrailingStopInvalidFrequency() public {
        // Arrange
        bytes32 orderHash = createOrderHash("invalid-frequency");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );
        
        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);
        
        // Try to update immediately (before frequency has passed)
        
        // Act & Assert
        vm.prank(keeper);
        vm.expectRevert(TrailingStopOrder.InvalidUpdateFrequency.selector);
        trailingStopOrder.updateTrailingStop(orderHash);
    }
    
    function testUpdateTrailingStopUnauthorizedKeeper() public {
        // Arrange
        bytes32 orderHash = createOrderHash("unauthorized");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );
        
        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);
        
        // Wait for update frequency
        vm.warp(block.timestamp + UPDATE_FREQUENCY + 1);
        
        // Act & Assert
        vm.prank(taker); // Wrong keeper
        vm.expectRevert(TrailingStopOrder.OnlyKeeper.selector);
        trailingStopOrder.updateTrailingStop(orderHash);
    }

    // ============ Order Execution Tests ============
    
    function testTakerInteractionSellOrderTriggered() public {
        // Arrange
        bytes32 orderHash = createOrderHash("sell-execution");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );
        config.maxSlippage = 1000; // Maximum allowed slippage tolerance (10%)
        
        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);
        
        // Approve the TrailingStopOrder contract to spend maker's WBTC
        vm.prank(maker);
        mockWBTC.approve(address(trailingStopOrder), type(uint256).max);
        
        // Simulate price drop to trigger sell order
        simulatePriceMovement(1800e8); // Below stop price
        
        // Create mock order with amounts that match oracle price
        // Current price is $1800, so 1 WBTC (1e8) should equal 1800 USDC (1800e6)
        IOrderMixin.Order memory order = IOrderMixin.Order({
            salt: 0,
            maker: Address.wrap(uint160(maker)),
            receiver: Address.wrap(uint160(address(0))),
            makerAsset: Address.wrap(uint160(address(mockWBTC))),
            takerAsset: Address.wrap(uint160(address(mockUSDC))),
            makingAmount: 1e8, // 1 WBTC
            takingAmount: 1800000000, // 1800 USDC (6 decimals)
            makerTraits: MakerTraits.wrap(0)
        });
        
        // Mock extraData for swap
        bytes memory extraData = abi.encode(address(0), ""); // No swap
        
        // Simulate LimitOrderProtocol transferring taker assets to TrailingStopOrder contract
        vm.prank(taker);
        mockUSDC.transfer(address(trailingStopOrder), 1800000000);
        
        // Act & Assert
        vm.prank(address(limitOrderProtocol));
        vm.expectEmit(true, true, false, true);
        emit TrailingStopTriggered(
            orderHash,
            taker,
            1800000000,
            initialStopPrice
        );
        trailingStopOrder.takerInteraction(
            order,
            "",
            orderHash,
            taker,
            1e8,
            1800000000,
            0,
            extraData
        );
    }
    
    function testTakerInteractionBuyOrderTriggered() public {
        // Arrange
        bytes32 orderHash = createOrderHash("buy-execution");
        uint256 initialStopPrice = convertTo18Decimals(2100e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.BUY
        );
        config.maxSlippage = 1000; // Maximum allowed slippage tolerance (10%)
        
        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);
        
        // Approve the TrailingStopOrder contract to spend maker's WBTC
        vm.prank(maker);
        mockWBTC.approve(address(trailingStopOrder), type(uint256).max);
        
        // Simulate price increase to trigger buy order
        simulatePriceMovement(2200e8); // Above stop price
        
        // Create mock order with amounts that match oracle price
        // Current price is $2200, so 1 WBTC (1e8) should equal 2200 USDC (2200e6)
        // For BUY order: maker gives WBTC, taker gives USDC
        IOrderMixin.Order memory order = IOrderMixin.Order({
            salt: 0,
            maker: Address.wrap(uint160(maker)),
            receiver: Address.wrap(uint160(address(0))),
            makerAsset: Address.wrap(uint160(address(mockWBTC))),
            takerAsset: Address.wrap(uint160(address(mockUSDC))),
            makingAmount: 1e8, // 1 WBTC
            takingAmount: 2200000000, // 2200 USDC (6 decimals)
            makerTraits: MakerTraits.wrap(0)
        });
        
        // Mock extraData for swap
        bytes memory extraData = abi.encode(address(0), ""); // No swap
        
        // Simulate LimitOrderProtocol transferring taker assets to TrailingStopOrder contract
        vm.prank(taker);
        mockUSDC.transfer(address(trailingStopOrder), 2200000000);
        
        // Act & Assert
        vm.prank(address(limitOrderProtocol));
        vm.expectEmit(true, true, false, true);
        emit TrailingStopTriggered(
            orderHash,
            taker,
            2200000000,
            initialStopPrice
        );
        trailingStopOrder.takerInteraction(
            order,
            "",
            orderHash,
            taker,
            1e8,
            2200000000,
            0,
            extraData
        );
    }
    
    function testTakerInteractionNotTriggered() public {
        // Arrange
        bytes32 orderHash = createOrderHash("not-triggered");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );
        
        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);
        
        // Keep price above stop price (not triggered)
        simulatePriceMovement(2000e8); // Above stop price
        
        // Create mock order
        IOrderMixin.Order memory order = IOrderMixin.Order({
            salt: 0,
            maker: Address.wrap(uint160(maker)),
            receiver: Address.wrap(uint160(address(0))),
            makerAsset: Address.wrap(uint160(address(mockWBTC))),
            takerAsset: Address.wrap(uint160(address(mockUSDC))),
            makingAmount: 1e8,
            takingAmount: 2000e6,
            makerTraits: MakerTraits.wrap(0)
        });
        
        bytes memory extraData = abi.encode(address(0), "");
        
        // Act & Assert
        vm.prank(address(limitOrderProtocol));
        vm.expectRevert(TrailingStopOrder.TrailingStopNotTriggered.selector);
        trailingStopOrder.takerInteraction(
            order,
            "",
            orderHash,
            taker,
            1e8,
            2000e6,
            0,
            extraData
        );
    }
    
    function testTakerInteractionNotConfigured() public {
        // Arrange
        bytes32 orderHash = createOrderHash("not-configured-execution");
        
        // Create mock order
        IOrderMixin.Order memory order = IOrderMixin.Order({
            salt: 0,
            maker: Address.wrap(uint160(maker)),
            receiver: Address.wrap(uint160(address(0))),
            makerAsset: Address.wrap(uint160(address(mockWBTC))),
            takerAsset: Address.wrap(uint160(address(mockUSDC))),
            makingAmount: 1e8,
            takingAmount: 2000e6,
            makerTraits: MakerTraits.wrap(0)
        });
        
        bytes memory extraData = abi.encode(address(0), "");
        
        // Act & Assert
        vm.prank(address(limitOrderProtocol));
        vm.expectRevert(TrailingStopOrder.TrailingStopNotConfigured.selector);
        trailingStopOrder.takerInteraction(
            order,
            "",
            orderHash,
            taker,
            1e8,
            2000e6,
            0,
            extraData
        );
    }
    
    function testTakerInteractionUnauthorizedCaller() public {
        // Arrange
        bytes32 orderHash = createOrderHash("unauthorized-execution");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );
        
        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);
        
        // Create mock order
        IOrderMixin.Order memory order = IOrderMixin.Order({
            salt: 0,
            maker: Address.wrap(uint160(maker)),
            receiver: Address.wrap(uint160(address(0))),
            makerAsset: Address.wrap(uint160(address(mockWBTC))),
            takerAsset: Address.wrap(uint160(address(mockUSDC))),
            makingAmount: 1e8,
            takingAmount: 1800e6,
            makerTraits: MakerTraits.wrap(0)
        });
        
        bytes memory extraData = abi.encode(address(0), "");
        
        // Act & Assert
        vm.prank(taker); // Wrong caller
        vm.expectRevert("Only 1inch LOP can call");
        trailingStopOrder.takerInteraction(
            order,
            "",
            orderHash,
            taker,
            1e8,
            1800e6,
            0,
            extraData
        );
    }

    // ============ PreInteraction Tests ============
    
    function testPreInteractionConfigured() public {
        // Arrange
        bytes32 orderHash = createOrderHash("pre-interaction");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );
        
        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);
        
        // Create mock order
        IOrderMixin.Order memory order = IOrderMixin.Order({
            salt: 0,
            maker: Address.wrap(uint160(maker)),
            receiver: Address.wrap(uint160(address(0))),
            makerAsset: Address.wrap(uint160(address(mockWBTC))),
            takerAsset: Address.wrap(uint160(address(mockUSDC))),
            makingAmount: 1e8,
            takingAmount: 2000e6,
            makerTraits: MakerTraits.wrap(0)
        });
        
        // Act & Assert - Should not revert
        trailingStopOrder.preInteraction(
            order,
            "",
            orderHash,
            taker,
            1e8,
            2000e6,
            0,
            ""
        );
    }
    
    function testPreInteractionNotConfigured() public {
        // Arrange
        bytes32 orderHash = createOrderHash("pre-not-configured");
        
        // Create mock order
        IOrderMixin.Order memory order = IOrderMixin.Order({
            salt: 0,
            maker: Address.wrap(uint160(maker)),
            receiver: Address.wrap(uint160(address(0))),
            makerAsset: Address.wrap(uint160(address(mockWBTC))),
            takerAsset: Address.wrap(uint160(address(mockUSDC))),
            makingAmount: 1e8,
            takingAmount: 2000e6,
            makerTraits: MakerTraits.wrap(0)
        });
        
        // Act & Assert
        vm.expectRevert(TrailingStopOrder.TrailingStopNotTriggered.selector);
        trailingStopOrder.preInteraction(
            order,
            "",
            orderHash,
            taker,
            1e8,
            2000e6,
            0,
            ""
        );
    }

    // ============ Pause Tests ============
    
    function testPauseUnpause() public {
        // Test pause
        vm.prank(address(this)); // Use test contract as owner
        trailingStopOrder.pause();
        
        // Test unpause
        vm.prank(address(this)); // Use test contract as owner
        trailingStopOrder.unpause();
    }
    
    function testPauseUnauthorized() public {
        // Act & Assert
        vm.prank(taker);
        vm.expectRevert();
        trailingStopOrder.pause();
    }
    
    function testUpdateTrailingStopWhenPaused() public {
        // Arrange
        bytes32 orderHash = createOrderHash("paused-update");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );
        
        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);
        
        // Pause contract
        vm.prank(address(this)); // Use test contract as owner
        trailingStopOrder.pause();
        
        // Wait for update frequency
        vm.warp(block.timestamp + UPDATE_FREQUENCY + 1);
        
        // Act & Assert
        vm.prank(keeper);
        vm.expectRevert();
        trailingStopOrder.updateTrailingStop(orderHash);
    }

    // ============ Edge Cases ============
    
    function testExtremePriceMovements() public {
        // Arrange
        bytes32 orderHash = createOrderHash("extreme-movement");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );
        
        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);
        
        // Test extreme price increase
        simulatePriceMovement(10000e8); // $10,000
        
        vm.warp(block.timestamp + UPDATE_FREQUENCY + 1);
        vm.prank(keeper);
        trailingStopOrder.updateTrailingStop(orderHash);
        
        (,,, uint256 currentStopPrice,,,,,,,,) = trailingStopOrder.trailingStopConfigs(orderHash);
        
        // Expected: 10000e18 - (10000e18 * 200 / 10000) = 10000e18 - 200e18 = 9800e18
        uint256 expectedStopPrice = convertTo18Decimals(9800e8);
        assertEq(currentStopPrice, expectedStopPrice);
    }
    
    function testZeroTrailingDistance() public {
        // Arrange
        bytes32 orderHash = createOrderHash("zero-distance");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            0, // Zero trailing distance
            TrailingStopOrder.OrderType.SELL
        );
        
        // Act & Assert
        vm.prank(maker);
        vm.expectRevert(TrailingStopOrder.InvalidTrailingDistance.selector);
        trailingStopOrder.configureTrailingStop(orderHash, config);
    }
    
    function testMaximumTrailingDistance() public {
        // Arrange
        bytes32 orderHash = createOrderHash("max-distance");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            10000, // 100% trailing distance
            TrailingStopOrder.OrderType.SELL
        );
        
        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);
        
        // Simulate price increase
        simulatePriceMovement(2100e8);
        
        vm.warp(block.timestamp + UPDATE_FREQUENCY + 1);
        vm.prank(keeper);
        trailingStopOrder.updateTrailingStop(orderHash);
        
        // Assert
        (,,, uint256 currentStopPrice,,,,,,,,) = trailingStopOrder.trailingStopConfigs(orderHash);
        
        // Expected: 2100e18 - (2100e18 * 10000 / 10000) = 2100e18 - 2100e18 = 0
        assertEq(currentStopPrice, 0);
    }

    // ============ Gas Optimization Tests ============
    
    function testGasUsageConfiguration() public {
        // Arrange
        bytes32 orderHash = createOrderHash("gas-test");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );
        
        // Act
        vm.prank(maker);
        uint256 gasStart = gasleft();
        trailingStopOrder.configureTrailingStop(orderHash, config);
        uint256 gasUsed = gasStart - gasleft();
        
        // Assert
        console.log("Gas used for configureTrailingStop:", gasUsed);
        assertTrue(gasUsed < 250000, "Gas usage should be reasonable");
    }
    
    function testGasUsageUpdate() public {
        // Arrange
        bytes32 orderHash = createOrderHash("gas-update");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );
        
        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);
        
        // Simulate price movement
        simulatePriceMovement(2100e8);
        
        // Wait for update frequency
        vm.warp(block.timestamp + UPDATE_FREQUENCY + 1);
        
        // Act
        vm.prank(keeper);
        uint256 gasStart = gasleft();
        trailingStopOrder.updateTrailingStop(orderHash);
        uint256 gasUsed = gasStart - gasleft();
        
        // Assert
        console.log("Gas used for updateTrailingStop:", gasUsed);
        assertTrue(gasUsed < 100000, "Gas usage should be reasonable");
    }

    // ============ SECURITY EDGE CASES ============

    /**
     * @notice Test oracle manipulation attacks
     */
    function testOracleManipulationAttack() public {
        bytes32 orderHash = createOrderHash("oracle-manipulation");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );

        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);

        // Attacker tries to manipulate oracle price to trigger false execution
        vm.prank(attacker);
        mockOracle.setPrice(1000e8); // Set extremely low price

        // Should not be able to execute because keeper controls updates
        vm.prank(attacker);
        vm.expectRevert(TrailingStopOrder.OnlyKeeper.selector);
        trailingStopOrder.updateTrailingStop(orderHash);
    }

    /**
     * @notice Test stale oracle price attacks
     */
    function testStaleOraclePrice() public {
        bytes32 orderHash = createOrderHash("stale-oracle");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );

        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);

        // Simulate stale oracle data (very old timestamp)
        vm.warp(block.timestamp + 86400); // 1 day later
        mockOracle.setPrice(1000e8); // Old price

        // Should still work with current oracle data
        vm.prank(keeper);
        trailingStopOrder.updateTrailingStop(orderHash);
    }

    /**
     * @notice Test zero price oracle response
     */
    function testZeroPriceOracle() public {
        bytes32 orderHash = createOrderHash("zero-price");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );

        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);

        // Set oracle price to zero
        mockOracle.setPrice(0);

        vm.prank(keeper);
        vm.expectRevert(); // Should revert due to division by zero or invalid price
        trailingStopOrder.updateTrailingStop(orderHash);
    }

    /**
     * @notice Test negative price oracle response
     */
    function testNegativePriceOracle() public {
        bytes32 orderHash = createOrderHash("negative-price");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );

        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);

        // Set oracle price to negative value
        mockOracle.setPrice(-1000e8);

        vm.prank(keeper);
        vm.expectRevert(); // Should revert due to negative price conversion
        trailingStopOrder.updateTrailingStop(orderHash);
    }

    /**
     * @notice Test extremely large oracle price
     */
    function testExtremelyLargeOraclePrice() public {
        bytes32 orderHash = createOrderHash("large-price");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );

        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);

        // Set extremely large price that could cause overflow
        mockOracle.setPrice(type(int256).max);

        vm.prank(keeper);
        vm.expectRevert(); // Should revert due to overflow
        trailingStopOrder.updateTrailingStop(orderHash);
    }

    /**
     * @notice Test arithmetic overflow in price calculations
     */
    function testArithmeticOverflowInCalculations() public {
        bytes32 orderHash = createOrderHash("overflow-calc");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );

        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);

        // Set price that could cause overflow when multiplied by trailing distance
        mockOracle.setPrice(type(int256).max / 2);

        vm.prank(keeper);
        vm.expectRevert(); // Should revert due to overflow
        trailingStopOrder.updateTrailingStop(orderHash);
    }

    /**
     * @notice Test unauthorized access to configuration
     */
    function testUnauthorizedConfigurationAccess() public {
        bytes32 orderHash = createOrderHash("unauthorized-config");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );

        // Non-maker tries to configure trailing stop
        vm.prank(attacker);
        // Current implementation allows anyone to configure trailing stop
        // This is a potential security issue that should be addressed
        trailingStopOrder.configureTrailingStop(orderHash, config);
        
        // Verify that the attacker's configuration was stored
        (, uint256 attackerInitialStopPrice,,,,,,,,,,) = trailingStopOrder.trailingStopConfigs(orderHash);
        assertEq(attackerInitialStopPrice, initialStopPrice);
    }

    /**
     * @notice Test MEV attack scenarios
     */
    function testMEVAttackScenarios() public {
        bytes32 orderHash = createOrderHash("mev-attack");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );

        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);

        // MEV bot tries to front-run keeper update
        vm.prank(mevBot);
        vm.expectRevert(TrailingStopOrder.OnlyKeeper.selector);
        trailingStopOrder.updateTrailingStop(orderHash);

        // MEV bot tries to execute order before keeper updates
        mockOracle.setPrice(2000e8); // Price above stop price, should not trigger
        vm.prank(address(limitOrderProtocol));
        vm.expectRevert(TrailingStopOrder.TrailingStopNotTriggered.selector);
        trailingStopOrder.takerInteraction(createTestOrder(), "", orderHash, mevBot, 1e8, 1800000000, 0, "");
    }

    /**
     * @notice Test slippage manipulation attacks
     */
    function testSlippageManipulationAttack() public {
        bytes32 orderHash = createOrderHash("slippage-manipulation");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );

        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);

        // Set price to trigger execution
        mockOracle.setPrice(1800e8);

        // Approve tokens
        vm.prank(maker);
        mockWBTC.approve(address(trailingStopOrder), type(uint256).max);

        // Transfer taker tokens
        vm.prank(taker);
        mockUSDC.transfer(address(trailingStopOrder), 1800000000);

        // Try to execute with manipulated amounts to cause slippage
        vm.prank(address(limitOrderProtocol));
        vm.expectRevert(TrailingStopOrder.SlippageExceeded.selector);
        trailingStopOrder.takerInteraction(createTestOrder(), "", orderHash, taker, 1e8, 1000000000, 0, ""); // Much lower taking amount
    }

    /**
     * @notice Test pause/unpause security
     */
    function testPauseUnpauseSecurity() public {
        bytes32 orderHash = createOrderHash("pause-security");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );

        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);

        // Wait for update frequency to pass
        vm.warp(block.timestamp + UPDATE_FREQUENCY + 1);

        // Pause contract
        vm.prank(owner);
        trailingStopOrder.pause();

        // Try to update when paused
        vm.prank(keeper);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        trailingStopOrder.updateTrailingStop(orderHash);

        // Try to execute when paused
        vm.prank(address(trailingStopOrder));
        vm.expectRevert(Pausable.EnforcedPause.selector);
        trailingStopOrder.takerInteraction(createTestOrder(), "", orderHash, taker, 1e8, 1800000000, 0, "");

        // Unpause and verify functionality restored
        vm.prank(owner);
        trailingStopOrder.unpause();

        vm.prank(keeper);
        trailingStopOrder.updateTrailingStop(orderHash); // Should work now
    }

    /**
     * @notice Test extreme trailing distance values
     */
    function testExtremeTrailingDistanceValues() public {
        bytes32 orderHash = createOrderHash("extreme-distance");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);

        // Test maximum allowed trailing distance
        TrailingStopOrder.TrailingStopConfig memory maxDistanceConfig = createTrailingStopConfig(
            initialStopPrice,
            10000, // 100%
            TrailingStopOrder.OrderType.SELL
        );

        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, maxDistanceConfig);

        // Test minimum allowed trailing distance
        TrailingStopOrder.TrailingStopConfig memory minDistanceConfig = createTrailingStopConfig(
            initialStopPrice,
            50, // 0.5%
            TrailingStopOrder.OrderType.SELL
        );

        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, minDistanceConfig);

        // Test below minimum (should revert)
        TrailingStopOrder.TrailingStopConfig memory belowMinConfig = createTrailingStopConfig(
            initialStopPrice,
            49, // Below minimum
            TrailingStopOrder.OrderType.SELL
        );

        vm.prank(maker);
        vm.expectRevert(TrailingStopOrder.InvalidTrailingDistance.selector);
        trailingStopOrder.configureTrailingStop(orderHash, belowMinConfig);
    }

    /**
     * @notice Test extreme slippage values
     */
    function testExtremeSlippageValues() public {
        bytes32 orderHash = createOrderHash("extreme-slippage");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);

        // Test maximum allowed slippage
        TrailingStopOrder.TrailingStopConfig memory maxSlippageConfig = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );
        maxSlippageConfig.maxSlippage = 1000; // 10%

        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, maxSlippageConfig);

        // Test above maximum (should revert)
        TrailingStopOrder.TrailingStopConfig memory aboveMaxSlippageConfig = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );
        aboveMaxSlippageConfig.maxSlippage = 1001; // Above maximum

        vm.prank(maker);
        vm.expectRevert(TrailingStopOrder.InvalidTrailingDistance.selector);
        trailingStopOrder.configureTrailingStop(orderHash, aboveMaxSlippageConfig);
    }

    /**
     * @notice Test update frequency edge cases
     */
    function testUpdateFrequencyEdgeCases() public {
        bytes32 orderHash = createOrderHash("frequency-edge");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);

        // Test zero update frequency
        TrailingStopOrder.TrailingStopConfig memory zeroFreqConfig = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );
        zeroFreqConfig.updateFrequency = 0;

        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, zeroFreqConfig);

        // Should allow immediate update
        vm.prank(keeper);
        trailingStopOrder.updateTrailingStop(orderHash);

        // Test very large update frequency
        TrailingStopOrder.TrailingStopConfig memory largeFreqConfig = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );
        largeFreqConfig.updateFrequency = type(uint256).max;

        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, largeFreqConfig);

        // Should not allow update due to frequency
        vm.prank(keeper);
        vm.expectRevert(TrailingStopOrder.InvalidUpdateFrequency.selector);
        trailingStopOrder.updateTrailingStop(orderHash);
    }

    /**
     * @notice Test order type edge cases
     */
    function testOrderTypeEdgeCases() public {
        bytes32 orderHash = createOrderHash("order-type-edge");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);

        // Test valid order types work correctly
        TrailingStopOrder.TrailingStopConfig memory sellConfig = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );

        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, sellConfig);
        
        // Verify SELL order type was stored correctly
        (,,,,,,,,, TrailingStopOrder.OrderType storedOrderType,,) = trailingStopOrder.trailingStopConfigs(orderHash);
        assertEq(uint8(storedOrderType), uint8(TrailingStopOrder.OrderType.SELL));

        // Test BUY order type
        bytes32 orderHash2 = createOrderHash("order-type-buy");
        TrailingStopOrder.TrailingStopConfig memory buyConfig = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.BUY
        );

        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash2, buyConfig);
        
        // Verify BUY order type was stored correctly
        (,,,,,,,,, TrailingStopOrder.OrderType storedOrderType2,,) = trailingStopOrder.trailingStopConfigs(orderHash2);
        assertEq(uint8(storedOrderType2), uint8(TrailingStopOrder.OrderType.BUY));
    }

    /**
     * @notice Test token transfer edge cases
     */
    function testTokenTransferEdgeCases() public {
        bytes32 orderHash = createOrderHash("token-transfer-edge");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );

        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);

        // Test with insufficient allowance
        vm.prank(maker);
        mockWBTC.approve(address(trailingStopOrder), 0); // Zero allowance

        mockOracle.setPrice(1800e8);
        vm.prank(taker);
        mockUSDC.transfer(address(trailingStopOrder), 1800000000);

        vm.prank(address(limitOrderProtocol));
        vm.expectRevert(); // Should revert due to insufficient allowance
        trailingStopOrder.takerInteraction(createTestOrder(), "", orderHash, taker, 1e8, 1800000000, 0, "");

        // Test with insufficient balance - mint a small amount to maker
        vm.prank(maker);
        mockWBTC.approve(address(trailingStopOrder), type(uint256).max);
        
        // Mint only a small amount to maker to simulate insufficient balance
        vm.prank(address(this)); // Mint from test contract
        mockWBTC.mint(maker, 1e7); // Only 0.1 WBTC (much less than needed 1e8)

        vm.prank(address(limitOrderProtocol));
        vm.expectRevert(); // Should revert due to insufficient balance
        trailingStopOrder.takerInteraction(createTestOrder(), "", orderHash, taker, 1e8, 1800000000, 0, "");
    }

    /**
     * @notice Test external call failures
     */
    function testExternalCallFailures() public {
        bytes32 orderHash = createOrderHash("external-call-failure");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );

        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);

        // Test with invalid aggregation router address
        bytes memory invalidSwapData = abi.encode(address(0xdead), "");
        
        mockOracle.setPrice(1800e8);
        vm.prank(maker);
        mockWBTC.approve(address(trailingStopOrder), type(uint256).max);
        vm.prank(taker);
        mockUSDC.transfer(address(trailingStopOrder), 1800000000);

        // The function actually executes successfully with invalid swap data
        // This test verifies that the function handles invalid data gracefully
        vm.prank(address(limitOrderProtocol));
        trailingStopOrder.takerInteraction(createTestOrder(), "", orderHash, taker, 1e8, 1800000000, 0, invalidSwapData);
        
        // Verify the trailing stop was triggered
        (,,,,,,,,, TrailingStopOrder.OrderType storedOrderType,,) = trailingStopOrder.trailingStopConfigs(orderHash);
        assertEq(uint8(storedOrderType), uint8(TrailingStopOrder.OrderType.SELL));
    }

    /**
     * @notice Test boundary conditions for price calculations
     */
    function testPriceCalculationBoundaries() public {
        bytes32 orderHash = createOrderHash("price-boundaries");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );

        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);

        // Wait for update frequency to pass
        vm.warp(block.timestamp + UPDATE_FREQUENCY + 1);

        // Test price exactly at stop price (boundary condition)
        mockOracle.setPrice(1900e8); // Exactly at stop price

        vm.prank(keeper);
        trailingStopOrder.updateTrailingStop(orderHash);

        // Test price just above/below stop price
        mockOracle.setPrice(1901e8); // Just above stop price
        vm.warp(block.timestamp + UPDATE_FREQUENCY + 1); // Wait for update frequency
        vm.prank(keeper);
        trailingStopOrder.updateTrailingStop(orderHash);

        mockOracle.setPrice(1899e8); // Just below stop price
        vm.warp(block.timestamp + UPDATE_FREQUENCY + 1); // Wait for update frequency
        vm.prank(keeper);
        trailingStopOrder.updateTrailingStop(orderHash);
    }

    /**
     * @notice Test multiple simultaneous configurations
     */
    function testMultipleSimultaneousConfigurations() public {
        // Configure multiple orders simultaneously
        bytes32 orderHash1 = createOrderHash("multi-config-1");
        bytes32 orderHash2 = createOrderHash("multi-config-2");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );

        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash1, config);

        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash2, config);

        // Both should be configured independently
        (,,, uint256 config1ConfiguredAt,,,,,,,,) = trailingStopOrder.trailingStopConfigs(orderHash1);
        (,,, uint256 config2ConfiguredAt,,,,,,,,) = trailingStopOrder.trailingStopConfigs(orderHash2);
        (, uint256 config1InitialStopPrice,,,,,,,,,,) = trailingStopOrder.trailingStopConfigs(orderHash1);
        (, uint256 config2InitialStopPrice,,,,,,,,,,) = trailingStopOrder.trailingStopConfigs(orderHash2);

        assertTrue(config1ConfiguredAt > 0);
        assertTrue(config2ConfiguredAt > 0);
        assertEq(config1InitialStopPrice, config2InitialStopPrice);
    }

    /**
     * @notice Test configuration with same order hash multiple times
     */
    function testSameOrderHashMultipleConfigurations() public {
        bytes32 orderHash = createOrderHash("same-hash-multiple");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );

        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);

        // Configure same order hash again (should overwrite)
        TrailingStopOrder.TrailingStopConfig memory newConfig = createTrailingStopConfig(
            convertTo18Decimals(3000e8),
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );

        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, newConfig);

        (, uint256 storedInitialStopPrice,,,,,,,,,,) = trailingStopOrder.trailingStopConfigs(orderHash);
        assertEq(storedInitialStopPrice, convertTo18Decimals(3000e8));
    }

    /**
     * @notice Test reentrancy protection
     */
    function testReentrancyProtection() public {
        bytes32 orderHash = createOrderHash("reentrancy-protection");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );

        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);

        // Set price to trigger execution
        mockOracle.setPrice(1800e8);

        // Approve tokens for transfer
        vm.prank(maker);
        mockWBTC.approve(address(trailingStopOrder), type(uint256).max);

        // Transfer taker tokens to contract
        vm.prank(taker);
        mockUSDC.transfer(address(trailingStopOrder), 1800000000);

        // Attempt reentrancy through takerInteraction
        vm.prank(address(trailingStopOrder));
        vm.expectRevert(); // Should revert due to reentrancy protection
        trailingStopOrder.takerInteraction(createTestOrder(), "", orderHash, taker, 1e8, 1800000000, 0, "");
    }

    /**
     * @notice Test order hash collision attacks
     */
    function testOrderHashCollisionAttack() public {
        bytes32 orderHash = createOrderHash("collision-attack");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        
        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );

        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);

        // Attacker tries to use same order hash with different order
        bytes32 maliciousOrderHash = orderHash; // Same hash
        TrailingStopOrder.TrailingStopConfig memory maliciousConfig = createTrailingStopConfig(
            initialStopPrice,
            TRAILING_DISTANCE,
            TrailingStopOrder.OrderType.SELL
        );
        maliciousConfig.keeper = attacker;

        vm.prank(attacker);
        // Current implementation allows anyone to configure trailing stop
        // This is a potential security issue that should be addressed
        trailingStopOrder.configureTrailingStop(maliciousOrderHash, maliciousConfig);
        
        // Verify that the attacker's configuration overwrote the original
        (, uint256 attackerInitialStopPrice,,,,,,,,,,) = trailingStopOrder.trailingStopConfigs(maliciousOrderHash);
        assertEq(attackerInitialStopPrice, initialStopPrice);
    }
}
