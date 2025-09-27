## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/<ScriptName>.s.sol:<ScriptName>Script --rpc-url <your_rpc_url> --private-key <your_private_key>
```

## Helper Scripts

### Register Upkeep

Register the TrailingStopKeeper with Chainlink Automation on Sepolia:

```shell
$ forge script script/RegisterUpkeep.s.sol:RegisterUpkeepScript \
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

```shell
$ forge script script/UpdateCheckData.s.sol:UpdateCheckDataScript \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY \
  --broadcast \
  --verify \
  -vvvv
```

**Environment Variables Required:**
- `PRIVATE_KEY`: Your wallet private key
- `UPKEEP_ID`: The upkeep ID to update
- `ORDER_HASHES`: Comma-separated list of order hashes to monitor

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
