import { HardhatUserConfig, vars } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import '@typechain/hardhat'
import '@openzeppelin/hardhat-upgrades'

// Note: Accounts are loaded from wallet files in scripts, not from config
// This matches the pattern used in bridge-evm-contracts
const NEOX_DEVNET_RPC_URL = vars.has("NEOX_DEVNET_RPC_URL") ? vars.get("NEOX_DEVNET_RPC_URL") : "http://localhost:8562";
const NEOX_DEVNET_CHAIN_ID = vars.has("NEOX_DEVNET_CHAIN_ID") ? parseInt(vars.get("NEOX_DEVNET_CHAIN_ID")) : 2312051126;
const NEOX_DEVNET_GAS_PRICE = vars.has("NEOX_DEVNET_GAS_PRICE") ? parseInt(vars.get("NEOX_DEVNET_GAS_PRICE")) : 4000000000;

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.25",
    settings: {
      evmVersion: "shanghai",
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true,
    },
  },
  networks: {
    neoxDevnet: {
      url: NEOX_DEVNET_RPC_URL,
      chainId: NEOX_DEVNET_CHAIN_ID,
      gasPrice: NEOX_DEVNET_GAS_PRICE,
      timeout: 300000, // 5 minutes
      confirmations: 1,
    },
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
};

export default config;
