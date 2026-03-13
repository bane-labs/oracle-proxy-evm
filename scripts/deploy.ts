import { ethers, upgrades, network } from "hardhat";
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

  // N3 Oracle Proxy address (20-byte Hash160 of the Neo contract, as EVM-style address)
  const n3OracleProxyAddress = process.env.N3_ORACLE_PROXY_ADDRESS || "";
  if (!n3OracleProxyAddress || n3OracleProxyAddress === ethers.ZeroAddress) {
    throw new Error("N3 Oracle Proxy address is required. Set N3_ORACLE_PROXY_ADDRESS (20-byte Neo contract hash as 0x-prefixed hex).");
  }
  console.log("N3 Oracle Proxy Address:", n3OracleProxyAddress);

  // Deploy OracleProxy (upgradeable via UUPS)
  console.log("\nDeploying OracleProxy (UUPS proxy)...");
  const OracleProxy = await ethers.getContractFactory("OracleProxy", deployer);

  const proxy = await upgrades.deployProxy(
    OracleProxy,
    [bridgeAddress, messageBridgeAddress, executionManagerAddress, n3OracleProxyAddress, deployer.address],
    { kind: "uups", initializer: "initialize" }
  );
  await proxy.waitForDeployment();
  const exampleBridgeAddress = await proxy.getAddress();
  const implAddress = await upgrades.erc1967.getImplementationAddress(exampleBridgeAddress);
  console.log("OracleProxy proxy deployed to:          ", exampleBridgeAddress);
  console.log("OracleProxy implementation deployed to: ", implAddress);

  // Verify deployment by checking code
  const code = await ethers.provider.getCode(exampleBridgeAddress);
  if (code === "0x") {
    throw new Error("Contract deployment failed - no code at address");
  }
  console.log("Contract code verified at address");

  // Get network info
  const networkInfo = await ethers.provider.getNetwork();
  const networkName = network.name || `chain-${networkInfo.chainId}`;

  // Save deployment addresses
  const addresses = {
    exampleBridge: exampleBridgeAddress,
    bridge: bridgeAddress,
    messageBridge: messageBridgeAddress,
    executionManager: executionManagerAddress,
    n3OracleProxy: n3OracleProxyAddress,
    deployer: deployer.address,
    network: networkName,
    chainId: networkInfo.chainId.toString()
  };

  const addressesPath = path.join(__dirname, "../deployment-addresses.json");
  fs.writeFileSync(addressesPath, JSON.stringify(addresses, null, 2));
  console.log("\nDeployment addresses saved to:", addressesPath);

  console.log("\n=== Deployment Summary ===");
  console.log("OracleProxy (proxy):         ", exampleBridgeAddress);
  console.log("OracleProxy (implementation):", implAddress);
  console.log("Bridge:", bridgeAddress);
  console.log("MessageBridge:", messageBridgeAddress);
  console.log("ExecutionManager:", executionManagerAddress);
  console.log("N3 Oracle Proxy:", n3OracleProxyAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
