# ETH Global Delhi 2025 - Trailing Stop Order System

This repository contains a Trailing Stop Order implementation for ETH Global Delhi 2025 hackathon, featuring seamless integration with 1inch Protocol and Chainlink Automation.

## Project Overview

This project implements an automated trailing stop order system that allows users to set stop-loss orders that dynamically adjust based on price movements, providing better risk management for DeFi trading.

## Project Structure

- `src/` - Main source code including trailing stop order implementation
- `test/` - Comprehensive test suite for trailing stop functionality  
- `script/` - Deployment and utility scripts
- `lib/` - External dependencies (Forge, OpenZeppelin, Solidity Utils)

### Key Components

- **TrailingStopOrder.sol**: Main contract implementing trailing stop logic
- **TrailingStopKeeper.sol**: Chainlink Automation keeper for order execution
- **LimitOrderProtocol.sol**: 1inch protocol integration
- **OrderLib.sol**: Order management utilities

## Features

- **Trailing Stop Orders**: Automated stop-loss orders that trail price movements
- **1inch Integration**: Seamless integration with 1inch protocol for optimal trade execution
- **Chainlink Automation**: Automated order execution using Chainlink Keepers
- **Comprehensive Testing**: Full test coverage for all functionality
- **Gas Optimization**: Efficient smart contract design for minimal gas costs

## Getting Started

### Prerequisites

- Node.js and npm
- Foundry (Forge, Cast, Anvil)
- Git

### Installation

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd delhihackathon
   ```

2. Install dependencies:
   ```bash
   npm install
   ```

3. Install Foundry dependencies:
   ```bash
   forge install
   ```

### Usage

#### Build
```bash
forge build
```

#### Test
```bash
forge test
```

#### Run specific tests
```bash
forge test --match-contract TrailingStopOrderComprehensiveTest
```

#### Format code
```bash
forge fmt
```

#### Deploy contracts
```bash
forge script script/TrailingStopDemo.s.sol:TrailingStopDemoScript \
  --rpc-url <your_rpc_url> \
  --private-key <your_private_key> \
  --broadcast \
  --verify
```

## Helper Scripts

### Register Upkeep

Register the TrailingStopKeeper with Chainlink Automation on Sepolia:

```bash
forge script script/RegisterUpkeep.s.sol:RegisterUpkeepScript \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY \
  --broadcast \
  --verify \
  -vvvv
```

**Environment Variables Required:**
- `PRIVATE_KEY`: Your wallet private key
- `TRAILING_STOP_ORDER_ADDRESS`: (Optional) Address of deployed TrailingStopOrder contract
- `KEEPER_ADDRESS`: (Optional) Address of deployed TrailingStopKeeper contract

### Update Check Data

Update the check data for existing upkeep:

```bash
forge script script/UpdateCheckData.s.sol:UpdateCheckDataScript \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY \
  --broadcast \
  --verify \
  -vvvv
```

**Environment Variables Required:**
- `PRIVATE_KEY`: Your wallet private key
- `UPKEEP_ID`: The upkeep ID to update
- `ORDER_HASHES`: Comma-separated list of order hashes to monitor

## Technologies

- **1inch Protocol**: DEX aggregation and optimal trade execution
- **Chainlink Automation**: Automated smart contract execution
- **Ethereum**: Blockchain platform
- **Solidity**: Smart contract programming language
- **Foundry**: Development framework and testing suite
- **Web3**: Decentralized web technologies

## Architecture

The system consists of three main components:

1. **TrailingStopOrder Contract**: Manages order creation, updates, and execution
2. **TrailingStopKeeper Contract**: Chainlink Automation keeper that monitors and executes orders
3. **1inch Integration**: Handles optimal trade execution through 1inch protocol

## Testing

The project includes comprehensive tests covering:
- Order creation and management
- Trailing stop logic
- Integration with 1inch protocol
- Chainlink Automation functionality
- Edge cases and error handling

Run all tests:
```bash
forge test -vv
```

## License

MIT

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## Support

For questions or support, please open an issue in the repository.