import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import '@typechain/hardhat'
import '@openzeppelin/hardhat-upgrades'
import 'dotenv/config'

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
      url: process.env.NEOX_DEVNET_RPC_URL || "http://localhost:8562",
      chainId: parseInt(process.env.NEOX_DEVNET_CHAIN_ID || "2312051126"),
      gasPrice: parseInt(process.env.NEOX_DEVNET_GAS_PRICE || "4000000000"),
      timeout: 300000, // 5 minutes
      confirmations: 1,
    },
    neoxTestnet: {
      url: process.env.NEOX_TESTNET_RPC_URL || "https://testnet.rpc.banelabs.org",
      chainId: parseInt(process.env.NEOX_TESTNET_CHAIN_ID || "12227332"),
      gasPrice: parseInt(process.env.NEOX_TESTNET_GAS_PRICE || "4000000000"),
      timeout: 300000, // 5 minutes
      confirmations: 1,
    },
    neoxMainnet: {
      url: process.env.NEOX_MAINNET_RPC_URL || "https://mainnet-1.rpc.banelabs.org",
      chainId: parseInt(process.env.NEOX_MAINNET_CHAIN_ID || "47763"),
      gasPrice: parseInt(process.env.NEOX_MAINNET_GAS_PRICE || "4000000000"),
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
