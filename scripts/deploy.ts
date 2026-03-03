import { ethers } from "hardhat";
import fs from "fs";
import path from "path";
import { getDeployer } from "./utils/wallet";

async function main() {
  // Use the same wallet loading pattern as bridge-evm-contracts
  const deployer = getDeployer(ethers.provider);
  console.log("Deploying contracts with account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  // Get addresses from environment or use defaults
  const bridgeAddress = process.env.BRIDGE_ADDRESS || "0x43732d5509fA9B54A87977e3D9c234810b3F8443";
  const messageBridgeAddress = process.env.MESSAGE_BRIDGE_ADDRESS || "0x1795E681aa56aD07F71E292F52cbB0b7245544FA";

  console.log("Bridge Address:", bridgeAddress);
  console.log("Message Bridge Address:", messageBridgeAddress);

  // Get ExecutionManager address - try environment variable first, then query from MessageBridge
  let executionManagerAddress: string = process.env.EXECUTION_MANAGER_ADDRESS || "";
  if (!executionManagerAddress) {
    console.log("ExecutionManager address not provided, querying from MessageBridge...");
    // Query executionManager() from MessageBridge contract
    // Note: executionManager() returns IExecutionManager interface, but when called via ethers it returns the address as a string
    const executionManagerABI = [
      "function executionManager() external view returns (address)"
    ];
    const messageBridgeContract = new ethers.Contract(messageBridgeAddress, executionManagerABI, deployer);
    executionManagerAddress = await messageBridgeContract.executionManager() as string;
    console.log("ExecutionManager address from MessageBridge:", executionManagerAddress);
  } else {
    console.log("ExecutionManager Address (from env):", executionManagerAddress);
  }

  if (!executionManagerAddress || executionManagerAddress === ethers.ZeroAddress) {
    throw new Error("ExecutionManager address is required. Set EXECUTION_MANAGER_ADDRESS environment variable or ensure MessageBridge has an ExecutionManager set.");
  }

  // Deploy ExampleBridge
  console.log("\nDeploying ExampleBridge...");
  const ExampleBridge = await ethers.getContractFactory("ExampleBridge");
  
  console.log("Sending deployment transaction...");
  const deployTx = await ExampleBridge.connect(deployer).deploy(bridgeAddress, messageBridgeAddress, executionManagerAddress);
  console.log("Deployment transaction sent, waiting for confirmation...");
  const txHash = deployTx.deploymentTransaction()?.hash;
  console.log("Transaction hash:", txHash);

  // Wait for deployment
  await deployTx.waitForDeployment();
  const exampleBridgeAddress = await deployTx.getAddress();
  console.log("ExampleBridge deployed to:", exampleBridgeAddress);
  
  // Verify deployment by checking code
  const code = await ethers.provider.getCode(exampleBridgeAddress);
  if (code === "0x") {
    throw new Error("Contract deployment failed - no code at address");
  }
  console.log("Contract code verified at address");

  // Save deployment addresses
  const addresses = {
    exampleBridge: exampleBridgeAddress,
    bridge: bridgeAddress,
    messageBridge: messageBridgeAddress,
    executionManager: executionManagerAddress,
    deployer: deployer.address,
    network: "neoxDevnet"
  };

  const addressesPath = path.join(__dirname, "../deployment-addresses.json");
  fs.writeFileSync(addressesPath, JSON.stringify(addresses, null, 2));
  console.log("\nDeployment addresses saved to:", addressesPath);

  console.log("\n=== Deployment Summary ===");
  console.log("ExampleBridge:", exampleBridgeAddress);
  console.log("Bridge:", bridgeAddress);
  console.log("MessageBridge:", messageBridgeAddress);
  console.log("ExecutionManager:", executionManagerAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
