# ETH Global Delhi 2025 - Trailing Stop Order System

This repository contains a Trailing Stop Order implementation for ETH Global Delhi 2025 hackathon, featuring seamless integration with 1inch Protocol and Chainlink Automation.

## 🎯 What is a Trailing Stop Order?

A trailing stop order is an advanced trading strategy that automatically adjusts your stop-loss price as the market moves in your favor. It "trails" behind the current market price, protecting your profits while allowing for continued upside potential.

### Key Benefits:
- **Risk Management**: Automatically protects against sudden price reversals
- **Profit Protection**: Locks in gains as prices move favorably
- **Emotion-Free Trading**: Executes automatically without manual intervention
- **Flexible Strategy**: Works for both buying and selling scenarios

## 🔄 How Trailing Stop Price Adjustment Works

### Core Mechanism: Dynamic Stop Price Calculation

The trailing stop system continuously recalculates the stop price based on current market conditions:

#### **For SELL Orders (Profit Protection)**
```
Stop Price = Current Market Price - Trailing Distance
```
- **Direction**: Stop price only moves UP (never down)
- **Purpose**: Protects profits as price rises
- **Trigger**: Executes when price falls below the trailing stop

#### **For BUY Orders (Entry Protection)**
```
Stop Price = Current Market Price + Trailing Distance
```
- **Direction**: Stop price only moves DOWN (never up)
- **Purpose**: Protects against price increases
- **Trigger**: Executes when price rises above the trailing stop

### Example 1: SELL Order - ETH/USDC (Profit Protection)

**Scenario**: You hold 5 ETH and want to sell it for USDC, protecting your profits as ETH price rises.

#### Initial Setup:
- **Current ETH Price**: $2,000
- **Your Holdings**: 5 ETH
- **Trailing Distance**: 3% (60 basis points)
- **Initial Stop Price**: $2,000 - ($2,000 × 3%) = $1,940

#### Price Movement Simulation:

**Day 1: ETH rises to $2,100**
```
Current Price: $2,100
New Stop Price: $2,100 - ($2,100 × 3%) = $2,037
Previous Stop: $1,940
Result: Stop price moved UP from $1,940 to $2,037 ✅
```

**Day 2: ETH rises to $2,200**
```
Current Price: $2,200
New Stop Price: $2,200 - ($2,200 × 3%) = $2,134
Previous Stop: $2,037
Result: Stop price moved UP from $2,037 to $2,134 ✅
```

**Day 3: ETH rises to $2,300**
```
Current Price: $2,300
New Stop Price: $2,300 - ($2,300 × 3%) = $2,231
Previous Stop: $2,134
Result: Stop price moved UP from $2,134 to $2,231 ✅
```

**Day 4: ETH drops to $2,150**
```
Current Price: $2,150
Previous Stop: $2,231
Result: Price ($2,150) < Stop Price ($2,231) → ORDER TRIGGERS! 🚨
Execution: Sell 5 ETH at ~$2,150 = $10,750 USDC
```

**Key Point**: The stop price never moved down from $2,231, protecting your profit even though ETH dropped from $2,300 to $2,150.

### Example 2: BUY Order - ETH/USDC (Entry Protection)

**Scenario**: You want to buy ETH with USDC, but only when ETH price drops significantly.

#### Initial Setup:
- **Current ETH Price**: $2,000
- **Your Capital**: 10,000 USDC
- **Trailing Distance**: 3% (60 basis points)
- **Initial Stop Price**: $2,000 + ($2,000 × 3%) = $2,060

#### Price Movement Simulation:

**Day 1: ETH drops to $1,900**
```
Current Price: $1,900
New Stop Price: $1,900 + ($1,900 × 3%) = $1,957
Previous Stop: $2,060
Result: Stop price moved DOWN from $2,060 to $1,957 ✅
```

**Day 2: ETH drops to $1,800**
```
Current Price: $1,800
New Stop Price: $1,800 + ($1,800 × 3%) = $1,854
Previous Stop: $1,957
Result: Stop price moved DOWN from $1,957 to $1,854 ✅
```

**Day 3: ETH drops to $1,700**
```
Current Price: $1,700
New Stop Price: $1,700 + ($1,700 × 3%) = $1,751
Previous Stop: $1,854
Result: Stop price moved DOWN from $1,854 to $1,751 ✅
```

**Day 4: ETH rises to $1,800**
```
Current Price: $1,800
Previous Stop: $1,751
Result: Price ($1,800) > Stop Price ($1,751) → ORDER TRIGGERS! 🚨
Execution: Buy ETH at ~$1,800 with 10,000 USDC = ~5.56 ETH
```

**Key Point**: The stop price never moved up from $1,751, ensuring you buy ETH at a good price even though it rose from $1,700 to $1,800.

### Example 3: Cross-Asset Trading - BTC/ETH

**Scenario**: You want to buy BTC with ETH, protecting against ETH/BTC ratio increases.

#### Initial Setup:
- **Current BTC Price**: 15 ETH per BTC
- **Your Capital**: 100 ETH
- **Trailing Distance**: 2% (20 basis points)
- **Initial Stop Price**: 15 + (15 × 2%) = 15.3 ETH per BTC

#### Price Movement Simulation:

**Day 1: BTC drops to 14.5 ETH per BTC**
```
Current Rate: 14.5 ETH per BTC
New Stop Price: 14.5 + (14.5 × 2%) = 14.79 ETH per BTC
Previous Stop: 15.3 ETH per BTC
Result: Stop price moved DOWN from 15.3 to 14.79 ✅
```

**Day 2: BTC drops to 14.0 ETH per BTC**
```
Current Rate: 14.0 ETH per BTC
New Stop Price: 14.0 + (14.0 × 2%) = 14.28 ETH per BTC
Previous Stop: 14.79 ETH per BTC
Result: Stop price moved DOWN from 14.79 to 14.28 ✅
```

**Day 3: BTC rises to 14.5 ETH per BTC**
```
Current Rate: 14.5 ETH per BTC
Previous Stop: 14.28 ETH per BTC
Result: Rate (14.5) > Stop Price (14.28) → ORDER TRIGGERS! 🚨
Execution: Buy BTC at 14.5 ETH per BTC with 100 ETH = ~6.9 BTC
```

## 🔑 Key Principles of Trailing Stop Logic

### 1. **One-Way Movement Rule**
- **SELL Orders**: Stop price only moves UP (never down)
- **BUY Orders**: Stop price only moves DOWN (never up)
- **Why**: This ensures the stop price always moves in the user's favor

### 2. **Trailing Distance Calculation**
```solidity
// For SELL orders
newStopPrice = currentPrice - (currentPrice * trailingDistance / 10000)

// For BUY orders  
newStopPrice = currentPrice + (currentPrice * trailingDistance / 10000)
```

### 3. **Trigger Conditions**
```solidity
// For SELL orders
if (currentPrice <= stopPrice) {
    executeOrder(); // Sell at current price
}

// For BUY orders
if (currentPrice >= stopPrice) {
    executeOrder(); // Buy at current price
}
```

### 4. **Profit Protection Mechanism**
- **SELL Orders**: As price rises, stop price rises too, locking in higher profits
- **BUY Orders**: As price drops, stop price drops too, ensuring better entry prices
- **Result**: Users get better prices while being protected from adverse movements

## 📊 Visual Representation

### SELL Order Trailing Stop:
```
Price Movement: $2000 → $2100 → $2200 → $2300 → $2150
Stop Price:     $1940 → $2037 → $2134 → $2231 → $2231 (TRIGGER!)
                ↑      ↑      ↑      ↑      ↑
                Moves  Moves  Moves  Moves  Stays
                UP     UP     UP     UP     (protects profit)
```

### BUY Order Trailing Stop:
```
Price Movement: $2000 → $1900 → $1800 → $1700 → $1800
Stop Price:     $2060 → $1957 → $1854 → $1751 → $1751 (TRIGGER!)
                ↑      ↑      ↑      ↑      ↑
                Moves  Moves  Moves  Moves  Stays
                DOWN   DOWN   DOWN   DOWN   (ensures good entry)
```

This trailing stop mechanism ensures that users always get favorable prices while being protected from sudden adverse price movements.

## 🏗️ How It Works

### Core Components

1. **TrailingStopOrder Contract**: Manages order creation, updates, and execution
2. **TrailingStopKeeper Contract**: Chainlink Automation keeper that monitors and executes orders
3. **1inch Integration**: Handles optimal trade execution through 1inch protocol
4. **Price Oracles**: Chainlink price feeds for real-time market data

### Architecture Flow

```
User Creates Order → TrailingStopOrder Contract → Chainlink Keeper Monitors → Price Movement Detected → Order Executed via 1inch
```

## 📊 Trading Scenarios & Examples

### Scenario 1: BUY ORDER - ETH/USDC Pair

**Situation**: You want to buy ETH with USDC, but only when ETH price drops significantly (DCA strategy with protection).

#### Example Setup:
- **Token Pair**: ETH/USDC
- **Initial ETH Price**: $2,000
- **Your Capital**: 10,000 USDC
- **Strategy**: Buy ETH as price drops, protect against sudden recovery

#### Configuration:
```solidity
TrailingStopConfig memory config = TrailingStopConfig({
    initialStopPrice: 2060e8,        // $2,060 (3% above $2,000)
    trailingDistance: 300,            // 3% trailing distance
    orderType: OrderType.BUY,          // Buy order
    makerAsset: USDC,                 // You're selling USDC
    takerAsset: ETH,                  // You're buying ETH
    makingAmount: 10000e6,            // 10,000 USDC
    takingAmount: 5e18                // ~5 ETH (at $2,000)
});
```

#### Price Movement Simulation:

**Phase 1: Price Drops (Accumulation)**
```
Starting Price: $2,000
Drop 1: $2,000 → $1,980 (-$20) → BUY 1,200 USDC worth of ETH
Drop 2: $1,980 → $1,950 (-$30) → BUY 1,400 USDC worth of ETH  
Drop 3: $1,950 → $1,910 (-$40) → BUY 1,600 USDC worth of ETH
Drop 4: $1,910 → $1,860 (-$50) → BUY 1,800 USDC worth of ETH
Drop 5: $1,860 → $1,800 (-$60) → BUY 2,000 USDC worth of ETH
```

**Phase 2: Price Recovery (Stop Trigger)**
```
Recovery 1: $1,800 → $1,850 (+$50) → Still below stop price
Recovery 2: $1,850 → $1,925 (+$75) → Still below stop price  
Recovery 3: $1,925 → $2,025 (+$100) → TRIGGERS STOP ORDER!
```

**Result**: You accumulated ETH at average price ~$1,900, then the trailing stop protected you from further price increases.

### Scenario 2: SELL ORDER - ETH/USDC Pair

**Situation**: You hold ETH and want to sell it for USDC, but only when ETH price rises significantly (profit-taking with protection).

#### Example Setup:
- **Token Pair**: ETH/USDC  
- **Initial ETH Price**: $2,000
- **Your Holdings**: 5 ETH
- **Strategy**: Sell ETH as price rises, protect against sudden drops

#### Configuration:
```solidity
TrailingStopConfig memory config = TrailingStopConfig({
    initialStopPrice: 1940e8,        // $1,940 (3% below $2,000)
    trailingDistance: 300,            // 3% trailing distance
    orderType: OrderType.SELL,        // Sell order
    makerAsset: ETH,                  // You're selling ETH
    takerAsset: USDC,                 // You're buying USDC
    makingAmount: 5e18,               // 5 ETH
    takingAmount: 10000e6             // ~10,000 USDC (at $2,000)
});
```

#### Price Movement Simulation:

**Phase 1: Price Rises (Profit Taking)**
```
Starting Price: $2,000
Rise 1: $2,000 → $2,050 (+$50) → SELL 1 ETH for ~$2,050
Rise 2: $2,050 → $2,100 (+$50) → SELL 1 ETH for ~$2,100
Rise 3: $2,100 → $2,150 (+$50) → SELL 1 ETH for ~$2,150
Rise 4: $2,150 → $2,200 (+$50) → SELL 1 ETH for ~$2,200
Rise 5: $2,200 → $2,250 (+$50) → SELL 1 ETH for ~$2,250
```

**Phase 2: Price Drops (Stop Trigger)**
```
Drop 1: $2,250 → $2,200 (-$50) → Still above stop price
Drop 2: $2,200 → $2,150 (-$50) → Still above stop price
Drop 3: $2,150 → $2,100 (-$50) → Still above stop price
Drop 4: $2,100 → $2,050 (-$50) → Still above stop price
Drop 5: $2,050 → $1,990 (-$60) → TRIGGERS STOP ORDER!
```

**Result**: You sold ETH at average price ~$2,150, then the trailing stop protected you from further price decreases.

### Scenario 3: BUY ORDER - BTC/ETH Pair

**Situation**: You want to buy BTC with ETH, using ETH as collateral.

#### Example Setup:
- **Token Pair**: BTC/ETH
- **Initial BTC Price**: 15 ETH per BTC
- **Your Capital**: 100 ETH
- **Strategy**: Buy BTC as ETH/BTC ratio improves

#### Configuration:
```solidity
TrailingStopConfig memory config = TrailingStopConfig({
    initialStopPrice: 1545e8,        // 15.45 ETH (3% above 15 ETH)
    trailingDistance: 300,            // 3% trailing distance
    orderType: OrderType.BUY,          // Buy order
    makerAsset: ETH,                  // You're selling ETH
    takerAsset: BTC,                  // You're buying BTC
    makingAmount: 100e18,              // 100 ETH
    takingAmount: 6666666666666666666 // ~6.67 BTC (at 15 ETH per BTC)
});
```

#### Price Movement Simulation:

**Phase 1: BTC Price Drops (Better Exchange Rate)**
```
Starting Rate: 15 ETH per BTC
Drop 1: 15.0 → 14.7 ETH per BTC → BUY 2.04 BTC with 30 ETH
Drop 2: 14.7 → 14.4 ETH per BTC → BUY 2.08 BTC with 30 ETH
Drop 3: 14.4 → 14.1 ETH per BTC → BUY 2.13 BTC with 30 ETH
Drop 4: 14.1 → 13.8 ETH per BTC → BUY 2.17 BTC with 30 ETH
Drop 5: 13.8 → 13.5 ETH per BTC → BUY 2.22 BTC with 30 ETH
```

**Phase 2: BTC Price Rises (Stop Trigger)**
```
Rise 1: 13.5 → 13.8 ETH per BTC → Still below stop price
Rise 2: 13.8 → 14.1 ETH per BTC → Still below stop price
Rise 3: 14.1 → 14.4 ETH per BTC → Still below stop price
Rise 4: 14.4 → 14.7 ETH per BTC → Still below stop price
Rise 5: 14.7 → 15.0 ETH per BTC → TRIGGERS STOP ORDER!
```

**Result**: You bought BTC at average rate ~14.2 ETH per BTC, then the trailing stop protected you from further rate increases.

## 🚀 Getting Started

### Prerequisites

- Node.js and npm
- Foundry (Forge, Cast, Anvil)
- Git
- Ethereum wallet with Sepolia ETH

### Installation

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd delhihackathon
   ```

2. Install dependencies:
   ```bash
   npm install
   forge install
   ```

3. Set up environment variables:
   ```bash
   cp .env.example .env
   # Edit .env with your private key and API keys
   ```

### Running Examples

#### 1. Buy Order Scenario (ETH/USDC)
```bash
forge script script/BuyOrderScenario.s.sol:BuyOrderScenarioScript \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  -vvvv
```

**What this demonstrates:**
- 5 gradual price drops ($20, $30, $40, $50, $60)
- Smart condition checking before each buy
- DCA strategy with trailing stop protection
- Price recovery simulation with stop trigger

#### 2. Sell Order Scenario (ETH/USDC)
```bash
forge script script/SellOrderScenario.s.sol:SellOrderScenarioScript \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  -vvvv
```

**What this demonstrates:**
- 5 gradual price rises ($50, $75, $100, $125, $150)
- Profit-taking strategy with trailing stop protection
- Price drop simulation with stop trigger

#### 3. Comprehensive Demo (All Scenarios)
```bash
forge script script/TrailingStopDemo.s.sol:TrailingStopDemoScript \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  -vvvv
```

## 🔧 Configuration Parameters

### Trailing Stop Configuration

```solidity
struct TrailingStopConfig {
    address makerAssetOracle;        // Price oracle for maker asset
    address takerAssetOracle;        // Price oracle for taker asset
    uint256 initialStopPrice;        // Initial stop price (in oracle decimals)
    uint256 trailingDistance;        // Trailing distance in basis points (e.g., 300 = 3%)
    uint256 currentStopPrice;        // Current stop price (updates dynamically)
    uint256 configuredAt;            // Timestamp when configured
    uint256 lastUpdateAt;            // Last update timestamp
    uint256 updateFrequency;         // Update frequency in seconds
    uint256 maxSlippage;             // Maximum slippage tolerance
    uint256 maxPriceDeviation;       // Maximum price deviation
    uint256 twapWindow;              // TWAP window in seconds
    address keeper;                  // Keeper address
    address orderMaker;             // Order maker address
    OrderType orderType;            // BUY or SELL
    uint8 makerAssetDecimals;        // Maker asset decimals
    uint8 takerAssetDecimals;       // Taker asset decimals
}
```

### Key Parameters Explained

- **trailingDistance**: How closely the stop price follows the market price (300 = 3%)
- **initialStopPrice**: Starting stop price (3% above/below current price)
- **updateFrequency**: How often the keeper checks for updates (60 seconds)
- **maxSlippage**: Maximum acceptable slippage (50 = 0.5%)
- **maxPriceDeviation**: Maximum price deviation from oracle (100 = 1%)

## 📈 Trading Strategies

### 1. Dollar Cost Averaging (DCA) with Protection
- **Use Case**: Accumulating assets during price drops
- **Setup**: Buy orders with trailing stop protection
- **Benefit**: Reduces average cost while protecting against sudden reversals

### 2. Profit Taking with Protection
- **Use Case**: Selling assets during price rises
- **Setup**: Sell orders with trailing stop protection
- **Benefit**: Maximizes profits while protecting against sudden drops

### 3. Cross-Asset Trading
- **Use Case**: Trading between different token pairs
- **Setup**: Custom oracle configurations for different assets
- **Benefit**: Diversified trading strategies across multiple markets

## 🧪 Testing

Run comprehensive tests:
```bash
forge test -vv
```

Run specific test suites:
```bash
forge test --match-contract TrailingStopOrderComprehensiveTest
forge test --match-contract OrderFillMainnetTest
```

## 🔗 Integration

### 1inch Protocol Integration
- Automatic DEX aggregation for optimal trade execution
- Support for multiple DEXs and liquidity sources
- Gas optimization through 1inch routing

### Chainlink Automation
- Automated order monitoring and execution
- Reliable price feed integration
- Decentralized keeper network

### Supported Networks
- Ethereum Mainnet
- Ethereum Sepolia (Testnet)
- Polygon
- Arbitrum
- Optimism

## 📊 Performance Metrics

### Gas Optimization
- Order creation: ~150,000 gas
- Order update: ~80,000 gas
- Order execution: ~200,000 gas
- Keeper check: ~50,000 gas

### Supported Token Pairs
- ETH/USDC
- ETH/USDT
- BTC/ETH
- WBTC/USDC
- Custom token pairs with oracle support

## 🛡️ Security Features

- **Oracle Validation**: Multiple price feed validation
- **Slippage Protection**: Configurable slippage limits
- **Reentrancy Guards**: Protection against reentrancy attacks
- **Access Controls**: Role-based access management
- **Emergency Pause**: Circuit breaker functionality

## 📚 Additional Resources

- [1inch Protocol Documentation](https://docs.1inch.io/)
- [Chainlink Automation Documentation](https://docs.chain.link/automation/)
- [Trailing Stop Orders Explained](https://www.investopedia.com/terms/t/trailingstop.asp)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## 📄 License

MIT License - see LICENSE file for details

## 🆘 Support

For questions or support:
- Open an issue in the repository
- Join our Discord community
- Check the documentation wiki

---

**Built for ETH Global Delhi 2025** 🚀