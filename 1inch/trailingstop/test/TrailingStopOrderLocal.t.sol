// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {TrailingStopOrder} from "../src/extensions/TrailingStopOrder.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title MockChainlinkOracle
 * @notice Mock Chainlink oracle for local testing
 */
contract MockChainlinkOracle is AggregatorV3Interface {
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
 * @title TrailingStopOrderLocalTest
 * @notice Test suite for TrailingStopOrder contract on local testnet
 * @dev This test file uses mock oracles and local testing environment
 */
contract TrailingStopOrderLocalTest is Test {
    // ============ State Variables ============

    TrailingStopOrder public trailingStopOrder;
    MockChainlinkOracle public ethUsdOracle;
    MockChainlinkOracle public btcUsdOracle;

    // Test accounts
    address public maker;
    address public taker;
    address public admin;

    // Test constants
    uint256 constant INITIAL_ETH_PRICE = 2000e8; // $2000 in 8 decimals
    uint256 constant INITIAL_BTC_PRICE = 45000e8; // $45000 in 8 decimals
    uint256 constant INITIAL_STOP_PRICE = 1900e18; // $1900 in 18 decimals (wei)
    uint256 constant TRAILING_DISTANCE = 50e18; // $50 in 18 decimals (wei)

    // ============ Events ============

    // ============ Setup ============

    function setUp() public {
        // Deploy mock oracles
        ethUsdOracle = new MockChainlinkOracle(8, "ETH / USD");
        btcUsdOracle = new MockChainlinkOracle(8, "BTC / USD");

        // Set initial prices
        ethUsdOracle.setPrice(int256(INITIAL_ETH_PRICE));
        btcUsdOracle.setPrice(int256(INITIAL_BTC_PRICE));

        // Deploy TrailingStopOrder contract
        trailingStopOrder = new TrailingStopOrder();

        // Setup test accounts
        maker = makeAddr("maker");
        taker = makeAddr("taker");
        admin = makeAddr("admin");

        // Fund test accounts with ETH
        vm.deal(maker, 100 ether);
        vm.deal(taker, 100 ether);
        vm.deal(admin, 100 ether);
    }

    // ============ Helper Functions ============

    /**
     * @notice Helper function to create a valid order hash for testing
     * @param orderId Unique identifier for the order
     * @return orderHash The generated order hash
     */
    function createOrderHash(string memory orderId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(orderId));
    }

    /**
     * @notice Helper function to create a trailing stop config
     * @param oracleAddress Address of the Chainlink oracle
     * @param initialStopPrice Initial stop price in wei
     * @param trailingDistance Trailing distance in wei
     * @return config The trailing stop configuration
     */
    function createTrailingStopConfig(address oracleAddress, uint256 initialStopPrice, uint256 trailingDistance)
        internal
        pure
        returns (TrailingStopOrder.TrailingStopConfig memory config)
    {
        config.makerAssetOracle = AggregatorV3Interface(oracleAddress);
        config.initialStopPrice = initialStopPrice;
        config.trailingDistance = trailingDistance;
        config.currentStopPrice = initialStopPrice; // Will be set by contract
    }

    /**
     * @notice Helper function to get current price from mock oracle
     * @param oracleAddress Address of the mock oracle
     * @return price Current price from oracle
     * @return decimals Number of decimals for the price
     */
    function getOraclePrice(address oracleAddress) internal view returns (uint256 price, uint8 decimals) {
        MockChainlinkOracle oracle = MockChainlinkOracle(oracleAddress);
        (, int256 answer,,,) = oracle.latestRoundData();
        decimals = oracle.decimals();
        price = uint256(answer);
    }

    /**
     * @notice Helper function to simulate price movement
     * @param oracleAddress Address of the mock oracle
     * @param newPrice New price to set
     */
    function simulatePriceMovement(address oracleAddress, uint256 newPrice) internal {
        MockChainlinkOracle(oracleAddress).setPrice(int256(newPrice));
    }

    /**
     * @notice Helper function to convert price from 8 decimals to 18 decimals
     * @param price8Dec Price in 8 decimals
     * @return price18Dec Price in 18 decimals
     */
    function convertTo18Decimals(uint256 price8Dec) internal pure returns (uint256 price18Dec) {
        return price8Dec * 1e10; // Add 10 more decimals
    }

    /**
     * @notice Helper function to convert price from 18 decimals to 8 decimals
     * @param price18Dec Price in 18 decimals
     * @return price8Dec Price in 8 decimals
     */
    function convertTo8Decimals(uint256 price18Dec) internal pure returns (uint256 price8Dec) {
        return price18Dec / 1e10; // Remove 10 decimals
    }

    // ============ Test Placeholders ============

    /**
     * @notice Test trailing stop configuration with valid parameters on local testnet
     * @dev Tests the configureTrailingStop function with mock oracles
     */
    function testConfigureTrailingStopLocal() public {
        // Arrange
        bytes32 orderHash = createOrderHash("local-test-order-1");
        uint256 initialStopPrice = convertTo18Decimals(1900e8); // $1900 in 18 decimals
        uint256 trailingDistance = convertTo18Decimals(50e8); // $50 in 18 decimals

        TrailingStopOrder.TrailingStopConfig memory config =
            createTrailingStopConfig(address(ethUsdOracle), initialStopPrice, trailingDistance);

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
            uint256 updateFrequency
        ) = trailingStopOrder.trailingStopConfigs(orderHash);

        assertEq(address(oracle), address(ethUsdOracle));
        assertEq(storedInitialStopPrice, initialStopPrice);
        assertEq(storedTrailingDistance, trailingDistance);
        assertEq(storedCurrentStopPrice, initialStopPrice);
    }

    /**
     * @notice Test trailing stop configuration with invalid oracle address on local testnet
     * @dev Tests error handling for zero address oracle
     */
    function testConfigureTrailingStopInvalidOracleLocal() public {
        // Arrange
        bytes32 orderHash = createOrderHash("local-test-order-2");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        uint256 trailingDistance = convertTo18Decimals(50e8);

        TrailingStopOrder.TrailingStopConfig memory config = createTrailingStopConfig(
            address(0), // Invalid oracle address
            initialStopPrice,
            trailingDistance
        );

        // Act & Assert
        vm.prank(maker);
        vm.expectRevert(TrailingStopOrder.InvalidMakerAssetOracle.selector);
        trailingStopOrder.configureTrailingStop(orderHash, config);
    }

    /**
     * @notice Test trailing stop configuration with invalid initial stop price on local testnet
     * @dev Tests error handling for zero initial stop price
     */
    function testConfigureTrailingStopInvalidPriceLocal() public {
        // Arrange
        bytes32 orderHash = createOrderHash("local-test-order-3");
        uint256 initialStopPrice = 0; // Invalid price
        uint256 trailingDistance = convertTo18Decimals(50e8);

        TrailingStopOrder.TrailingStopConfig memory config =
            createTrailingStopConfig(address(ethUsdOracle), initialStopPrice, trailingDistance);

        // Act & Assert
        vm.prank(maker);
        vm.expectRevert(TrailingStopOrder.InvalidTrailingDistance.selector);
        trailingStopOrder.configureTrailingStop(orderHash, config);
    }

    /**
     * @notice Test trailing stop configuration event emission on local testnet
     * @dev Tests that the correct event is emitted with proper parameters
     */
    function testConfigureTrailingStopEventEmissionLocal() public {
        // Arrange
        bytes32 orderHash = createOrderHash("local-test-order-4");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        uint256 trailingDistance = convertTo18Decimals(50e8);

        TrailingStopOrder.TrailingStopConfig memory config =
            createTrailingStopConfig(address(ethUsdOracle), initialStopPrice, trailingDistance);

        // Act & Assert
        vm.prank(maker);
        vm.expectEmit(true, true, false, true);
        emit TrailingStopOrder.TrailingStopConfigUpdated(
            maker, address(ethUsdOracle), initialStopPrice, trailingDistance
        );
        trailingStopOrder.configureTrailingStop(orderHash, config);
    }

    /**
     * @notice Test trailing stop configuration with BTC oracle on local testnet
     * @dev Tests configuration with different mock oracle (BTC/USD)
     */
    function testConfigureTrailingStopWithBTCOracleLocal() public {
        // Arrange
        bytes32 orderHash = createOrderHash("local-test-order-5");
        uint256 initialStopPrice = convertTo18Decimals(44000e8); // $44000 in 18 decimals
        uint256 trailingDistance = convertTo18Decimals(1000e8); // $1000 in 18 decimals

        TrailingStopOrder.TrailingStopConfig memory config =
            createTrailingStopConfig(address(btcUsdOracle), initialStopPrice, trailingDistance);

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
            uint256 updateFrequency
        ) = trailingStopOrder.trailingStopConfigs(orderHash);

        assertEq(address(oracle), address(btcUsdOracle));
        assertEq(storedInitialStopPrice, initialStopPrice);
        assertEq(storedTrailingDistance, trailingDistance);
        assertEq(storedCurrentStopPrice, initialStopPrice);
    }

    /**
     * @notice Test trailing stop configuration update on local testnet
     * @dev Tests that configuration can be updated for the same order hash
     */
    function testConfigureTrailingStopUpdateLocal() public {
        // Arrange
        bytes32 orderHash = createOrderHash("local-test-order-6");
        uint256 initialStopPrice1 = convertTo18Decimals(1900e8);
        uint256 trailingDistance1 = convertTo18Decimals(50e8);
        uint256 initialStopPrice2 = convertTo18Decimals(2000e8);
        uint256 trailingDistance2 = convertTo18Decimals(100e8);

        TrailingStopOrder.TrailingStopConfig memory config1 =
            createTrailingStopConfig(address(ethUsdOracle), initialStopPrice1, trailingDistance1);

        TrailingStopOrder.TrailingStopConfig memory config2 =
            createTrailingStopConfig(address(btcUsdOracle), initialStopPrice2, trailingDistance2);

        // Act
        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config1);

        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config2);

        // Assert
        (
            AggregatorV3Interface oracle,
            uint256 storedInitialStopPrice,
            uint256 storedTrailingDistance,
            uint256 storedCurrentStopPrice,
            uint256 configuredAt,
            uint256 lastUpdateAt,
            uint256 updateFrequency
        ) = trailingStopOrder.trailingStopConfigs(orderHash);

        assertEq(address(oracle), address(btcUsdOracle));
        assertEq(storedInitialStopPrice, initialStopPrice2);
        assertEq(storedTrailingDistance, trailingDistance2);
        assertEq(storedCurrentStopPrice, initialStopPrice2);
    }

    /**
     * @notice Test trailing stop configuration with different users on local testnet
     * @dev Tests that different users can configure different orders
     */
    function testConfigureTrailingStopDifferentUsersLocal() public {
        // Arrange
        bytes32 orderHash1 = createOrderHash("user1-order");
        bytes32 orderHash2 = createOrderHash("user2-order");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        uint256 trailingDistance = convertTo18Decimals(50e8);

        TrailingStopOrder.TrailingStopConfig memory config =
            createTrailingStopConfig(address(ethUsdOracle), initialStopPrice, trailingDistance);

        // Act
        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash1, config);

        vm.prank(taker);
        trailingStopOrder.configureTrailingStop(orderHash2, config);

        // Assert
        (
            AggregatorV3Interface oracle1,
            uint256 storedInitialStopPrice1,
            ,
            ,
            uint256 configuredAt1,
            uint256 lastUpdateAt1,
            uint256 updateFrequency1
        ) = trailingStopOrder.trailingStopConfigs(orderHash1);
        (
            AggregatorV3Interface oracle2,
            uint256 storedInitialStopPrice2,
            ,
            ,
            uint256 configuredAt2,
            uint256 lastUpdateAt2,
            uint256 updateFrequency2
        ) = trailingStopOrder.trailingStopConfigs(orderHash2);

        assertEq(address(oracle1), address(ethUsdOracle));
        assertEq(address(oracle2), address(ethUsdOracle));
        assertEq(storedInitialStopPrice1, initialStopPrice);
        assertEq(storedInitialStopPrice2, initialStopPrice);
    }

    /**
     * @notice Test trailing stop configuration gas usage on local testnet
     * @dev Tests gas efficiency of configuration function
     */
    function testConfigureTrailingStopGasUsageLocal() public {
        // Arrange
        bytes32 orderHash = createOrderHash("gas-test-order");
        uint256 initialStopPrice = convertTo18Decimals(1900e8);
        uint256 trailingDistance = convertTo18Decimals(50e8);

        TrailingStopOrder.TrailingStopConfig memory config =
            createTrailingStopConfig(address(ethUsdOracle), initialStopPrice, trailingDistance);

        // Act
        vm.prank(maker);
        uint256 gasStart = gasleft();
        trailingStopOrder.configureTrailingStop(orderHash, config);
        uint256 gasUsed = gasStart - gasleft();

        // Assert
        console.log("Gas used for configureTrailingStop:", gasUsed);
        assertTrue(gasUsed < 200000, "Gas usage should be reasonable");
    }

    /**
     * @notice Placeholder for testing trailing stop price updates on local testnet
     * @dev Add your test logic here
     */
    function testUpdateTrailingStopPriceLocal() public {
        // TODO: Implement test for price update logic on local testnet
        // Test cases to consider:
        // 1. Price increase scenario with mock oracle
        // 2. Price decrease scenario with mock oracle
        // 3. Trailing distance calculations
        // 4. Stop price adjustments
        // 5. Edge cases with extreme price movements
    }

    /**
     * @notice Placeholder for testing order execution with trailing stop on local testnet
     * @dev Add your test logic here
     */
    function testOrderExecutionWithTrailingStopLocal() public {
        // TODO: Implement test for order execution on local testnet
        // Test cases to consider:
        // 1. Order execution when price is above stop price
        // 2. Order execution when price is below stop price
        // 3. Partial order execution scenarios
        // 4. Order cancellation scenarios
        // 5. Gas optimization for execution
    }

    /**
     * @notice Placeholder for testing edge cases on local testnet
     * @dev Add your test logic here
     */
    function testEdgeCasesLocal() public {
        // TODO: Implement test for edge cases on local testnet
        // Test cases to consider:
        // 1. Mock oracle price feed failures
        // 2. Extreme price movements simulation
        // 3. Gas optimization scenarios
        // 4. Reentrancy protection
        // 5. Integer overflow/underflow protection
    }

    /**
     * @notice Placeholder for testing integration with 1inch protocol on local testnet
     * @dev Add your test logic here
     */
    function test1inchIntegrationLocal() public {
        // TODO: Implement test for 1inch protocol integration on local testnet
        // Test cases to consider:
        // 1. Order matching with 1inch (mocked)
        // 2. Fee calculations
        // 3. Slippage protection
        // 4. Protocol compatibility
        // 5. Gas efficiency comparisons
    }

    /**
     * @notice Placeholder for testing mock oracle functionality
     * @dev Add your test logic here
     */
    function testMockOracleFunctionality() public {
        // TODO: Implement test for mock oracle functionality
        // Test cases to consider:
        // 1. Price setting and retrieval
        // 2. Round data updates
        // 3. Decimal precision handling
        // 4. Timestamp updates
        // 5. Oracle state consistency
    }

    // ============ Fuzz Tests ============

    /**
     * @notice Placeholder for fuzz testing on local testnet
     * @dev Add your fuzz test logic here
     */
    function testFuzzTrailingStopConfigLocal(uint256 initialStopPrice, uint256 trailingDistance) public {
        // TODO: Implement fuzz test for trailing stop configuration on local testnet
        // Test with various input combinations
        // Ensure proper bounds checking
    }

    /**
     * @notice Placeholder for fuzz testing price movements
     * @dev Add your fuzz test logic here
     */
    function testFuzzPriceMovements(uint256 priceChange) public {
        // TODO: Implement fuzz test for price movements
        // Test various price change scenarios
        // Ensure trailing stop logic handles all cases
    }

    // ============ Invariant Tests ============

    /**
     * @notice Placeholder for invariant testing on local testnet
     * @dev Add your invariant test logic here
     */
    function testInvariantTrailingStopLogicLocal() public {
        // TODO: Implement invariant test for trailing stop logic on local testnet
        // Ensure invariants are maintained across all operations
        // Test with mock oracles and local environment
    }

    // ============ Gas Optimization Tests ============

    /**
     * @notice Placeholder for gas optimization testing
     * @dev Add your gas optimization test logic here
     */
    function testGasOptimization() public {
        // TODO: Implement gas optimization tests
        // Test cases to consider:
        // 1. Gas usage for configuration
        // 2. Gas usage for price updates
        // 3. Gas usage for order execution
        // 4. Comparison with mainnet gas costs
    }

    // ============ Integration Tests ============

    /**
     * @notice Placeholder for integration testing
     * @dev Add your integration test logic here
     */
    function testIntegrationScenarios() public {
        // TODO: Implement integration tests
        // Test cases to consider:
        // 1. End-to-end trailing stop workflow
        // 2. Multiple orders with different configurations
        // 3. Oracle price feed updates
        // 4. Contract state consistency
    }
}
