# Oracle Proxy - EVM Contracts

This directory contains the EVM (Solidity) contracts for the Oracle Proxy, built with Hardhat.

## Project Structure

```
oracle-proxy-evm/
├── contracts/
│   └── OracleProxy.sol        # Main oracle proxy contract
├── scripts/
│   ├── deploy.ts              # Deployment script
│   ├── get-oracle-result.ts   # Script to retrieve oracle results
│   └── utils/
│       └── wallet.ts          # Wallet utilities
├── test/                      # Test files (to be added)
├── hardhat.config.ts          # Hardhat configuration
├── package.json               # Node.js dependencies
└── tsconfig.json              # TypeScript configuration
```

## Setup

1. Install dependencies:
```bash
npm install
```

2. Compile contracts:
```bash
npm run compile
```

## Deployment

### Prerequisites

- Bridge contracts must be deployed (see main project README)
- Update `scripts/deploy.ts` with correct bridge addresses or set environment variables:
  - `BRIDGE_ADDRESS`: Native bridge contract address
  - `MESSAGE_BRIDGE_ADDRESS`: Message bridge contract address

### Deploy to Devnet

```bash
npm run deploy
```

Or with Hardhat directly:
```bash
npx hardhat run scripts/deploy.ts --network neoxDevnet
```

Deployment addresses will be saved to `deployment-addresses.json`.

## Configuration

The Hardhat configuration supports the following environment variables:
- `NEOX_DEVNET_RPC_URL`: RPC URL (default: http://localhost:8562)
- `NEOX_DEVNET_CHAIN_ID`: Chain ID (default: 2312051126)
- `NEOX_DEVNET_GAS_PRICE`: Gas price (default: 4000000000)
- `NEOX_DEVNET_PRIVATE_KEY`: Private key for deployment

## Testing

```bash
npm test
```

## Contract Details

### OracleProxy.sol

Main contract that demonstrates:
- Bridging GAS from NeoX to N3
- Sending Oracle calls via message bridge
- Receiving and storing Oracle results

**Key Functions:**
- `initiateOracleCall()`: Initiates the full bridge flow
- `onOracleResult()`: Receives oracle results from the message bridge
- `getOracleResult()`: Retrieves stored Oracle result
- `hasOracleResult()`: Checks if result exists

## Dependencies

This project includes copies of the necessary interface and library files from `bridge-evm-contracts`:
- `contracts/interfaces/INativeBridge.sol`
- `contracts/interfaces/INativeBridgeExtended.sol`
- `contracts/interfaces/IBridgeManagement.sol`
- `contracts/messageBridge/interfaces/IMessageBridge.sol`
- `contracts/messageBridge/interfaces/IExecutionManager.sol`
- `contracts/messageBridge/AMBStorage.sol`
- `contracts/libraries/AMBTypes.sol`
- `contracts/libraries/BridgeLib.sol`
- `contracts/libraries/NeoSerializerLib.sol`
- `contracts/libraries/NeoTypes.sol`
- `contracts/libraries/StorageTypes.sol`
- `contracts/libraries/VarInt.sol`

These files are copied from the `bridge-evm-contracts` submodule to allow Hardhat to compile the contracts. If the bridge contracts are updated, these files may need to be updated as well.

## Scripts

### Deployment

Deploy the OracleProxy contract:
```bash
npm run deploy
```

### Get Oracle Result

Retrieve an oracle result by request ID:
```bash
npx hardhat run scripts/get-oracle-result.ts --network neoxDevnet
```

Note: Update the contract address and request ID in `get-oracle-result.ts` before running.
