import { ethers } from "hardhat";
import { getDeployer } from "./utils/wallet";
import fs from "fs";
import path from "path";

async function main() {
  const deployer = getDeployer(ethers.provider);
  console.log("Updating contract configuration with account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  // Load deployment addresses
  const addressesPath = path.join(__dirname, "../deployment-addresses.json");
  if (!fs.existsSync(addressesPath)) {
    throw new Error(`Deployment addresses file not found: ${addressesPath}`);
  }

  const addresses = JSON.parse(fs.readFileSync(addressesPath, "utf-8"));
  const proxyAddress = addresses.oracleProxyEvm;

  if (!proxyAddress) {
    throw new Error("Proxy address not found in deployment-addresses.json");
  }

  console.log("Proxy address:", proxyAddress);

  // Get contract instance
  const OracleProxy = await ethers.getContractFactory("OracleProxy", deployer);
  const proxy = OracleProxy.attach(proxyAddress) as any;

  // Check current values
  console.log("\n=== Current Configuration ===");
  const currentBridge = await proxy.bridge();
  const currentMessageBridge = await proxy.messageBridge();
  const currentExecutionManager = await proxy.executionManager();
  const currentN3OracleProxy = await proxy.n3OracleProxyAddress();
  const currentSubsidizedGas: bigint = await proxy.subsidizedGas();
  console.log("Bridge:", currentBridge);
  console.log("Message Bridge:", currentMessageBridge);
  console.log("Execution Manager:", currentExecutionManager);
  console.log("N3 Oracle Proxy:", currentN3OracleProxy);
  console.log("Subsidized Gas:", currentSubsidizedGas.toString(), "wei");

  // Get new values from environment or use current values
  const newBridge = process.env.BRIDGE_ADDRESS || currentBridge;
  const newMessageBridge = process.env.MESSAGE_BRIDGE_ADDRESS || currentMessageBridge;
  const newExecutionManager = process.env.EXECUTION_MANAGER_ADDRESS || currentExecutionManager;
  const newN3OracleProxy = process.env.N3_ORACLE_PROXY_ADDRESS || currentN3OracleProxy;
  const newSubsidizedGas = process.env.SUBSIDIZED_GAS
    ? BigInt(process.env.SUBSIDIZED_GAS)
    : currentSubsidizedGas;

  console.log("\n=== New Configuration ===");
  console.log("Bridge:", newBridge);
  console.log("Message Bridge:", newMessageBridge);
  console.log("Execution Manager:", newExecutionManager);
  console.log("N3 Oracle Proxy:", newN3OracleProxy);
  console.log("Subsidized Gas:", newSubsidizedGas.toString(), "wei");

  // Update execution manager if changed
  if (newExecutionManager.toLowerCase() !== currentExecutionManager.toLowerCase()) {
    console.log("\nUpdating Execution Manager...");
    const tx = await proxy.setExecutionManager(newExecutionManager);
    console.log("Transaction hash:", tx.hash);
    await tx.wait();
    console.log("Execution Manager updated");
  } else {
    console.log("\nExecution Manager unchanged");
  }

  // Update bridge if changed
  if (newBridge.toLowerCase() !== currentBridge.toLowerCase()) {
    console.log("\nUpdating Bridge...");
    const tx = await proxy.setBridge(newBridge);
    console.log("Transaction hash:", tx.hash);
    await tx.wait();
    console.log("Bridge updated");
  } else {
    console.log("\nBridge unchanged");
  }

  // Update message bridge if changed
  if (newMessageBridge.toLowerCase() !== currentMessageBridge.toLowerCase()) {
    console.log("\nUpdating Message Bridge...");
    const tx = await proxy.setMessageBridge(newMessageBridge);
    console.log("Transaction hash:", tx.hash);
    await tx.wait();
    console.log("Message Bridge updated");
  } else {
    console.log("\nMessage Bridge unchanged");
  }

  // Update N3 Oracle Proxy if changed
  if (newN3OracleProxy.toLowerCase() !== currentN3OracleProxy.toLowerCase()) {
    console.log("\nUpdating N3 Oracle Proxy...");
    const tx = await proxy.setN3OracleProxyAddress(newN3OracleProxy);
    console.log("Transaction hash:", tx.hash);
    await tx.wait();
    console.log("N3 Oracle Proxy updated");
  } else {
    console.log("\nN3 Oracle Proxy unchanged");
  }

  // Update subsidized gas if changed
  if (newSubsidizedGas !== currentSubsidizedGas) {
    console.log("\nUpdating Subsidized Gas...");
    const tx = await proxy.setSubsidizedGas(newSubsidizedGas);
    console.log("Transaction hash:", tx.hash);
    await tx.wait();
    console.log("Subsidized Gas updated");
  } else {
    console.log("\nSubsidized Gas unchanged");
  }

  // Verify final values
  console.log("\n=== Final Configuration ===");
  const finalBridge = await proxy.bridge();
  const finalMessageBridge = await proxy.messageBridge();
  const finalExecutionManager = await proxy.executionManager();
  const finalN3OracleProxy = await proxy.n3OracleProxyAddress();
  const finalSubsidizedGas: bigint = await proxy.subsidizedGas();
  console.log("Bridge:", finalBridge);
  console.log("Message Bridge:", finalMessageBridge);
  console.log("Execution Manager:", finalExecutionManager);
  console.log("N3 Oracle Proxy:", finalN3OracleProxy);
  console.log("Subsidized Gas:", finalSubsidizedGas.toString(), "wei");

  // Update deployment addresses file
  addresses.bridge = finalBridge;
  addresses.messageBridge = finalMessageBridge;
  addresses.executionManager = finalExecutionManager;
  addresses.n3OracleProxy = finalN3OracleProxy;
  addresses.subsidizedGas = finalSubsidizedGas.toString();
  addresses.lastConfigUpdate = new Date().toISOString();
  fs.writeFileSync(addressesPath, JSON.stringify(addresses, null, 2));
  console.log("\nDeployment addresses updated in:", addressesPath);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
