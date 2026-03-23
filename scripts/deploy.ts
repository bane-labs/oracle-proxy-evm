import { ethers, upgrades, network } from "hardhat";
import fs from "fs";
import path from "path";
import { getDeployer } from "./utils/wallet";

const isDryRun = process.env.DRY_RUN === "true";

async function main() {
  const deployer = getDeployer(ethers.provider);
  console.log(isDryRun ? "\n=== DRY RUN (no transactions will be sent) ===" : "");
  console.log("Deploying contracts with account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  const bridgeAddress = process.env.BRIDGE_ADDRESS || "0x43732d5509fA9B54A87977e3D9c234810b3F8443";
  const messageBridgeAddress = process.env.MESSAGE_BRIDGE_ADDRESS || "0x1795E681aa56aD07F71E292F52cbB0b7245544FA";

  console.log("Bridge Address:", bridgeAddress);
  console.log("Message Bridge Address:", messageBridgeAddress);

  let executionManagerAddress: string = process.env.EXECUTION_MANAGER_ADDRESS || "";
  if (!executionManagerAddress) {
    console.log("ExecutionManager address not provided, querying from MessageBridge...");
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

  const n3OracleProxyAddress = process.env.N3_ORACLE_PROXY_ADDRESS || "";
  if (!n3OracleProxyAddress || n3OracleProxyAddress === ethers.ZeroAddress) {
    throw new Error("N3 Oracle Proxy address is required. Set N3_ORACLE_PROXY_ADDRESS (20-byte Neo contract hash as 0x-prefixed hex).");
  }
  console.log("N3 Oracle Proxy Address:", n3OracleProxyAddress);

  const ownerAddress = process.env.OWNER_ADDRESS || deployer.address;
  console.log("Owner Address:", ownerAddress);

  const subsidizedGasEnv = process.env.SUBSIDIZED_GAS || "";

  if (isDryRun) {
    await dryRun(deployer.address);
    return;
  }

  console.log("\nDeploying OracleProxy (UUPS proxy)...");
  const OracleProxy = await ethers.getContractFactory("OracleProxy", deployer);

  const proxy = await upgrades.deployProxy(
    OracleProxy,
    [bridgeAddress, messageBridgeAddress, executionManagerAddress, n3OracleProxyAddress, ownerAddress],
    { kind: "uups", initializer: "initialize" }
  );
  await proxy.waitForDeployment();
  const oracleProxyAddress = await proxy.getAddress();
  const implAddress = await upgrades.erc1967.getImplementationAddress(oracleProxyAddress);
  console.log("OracleProxy proxy deployed to:          ", oracleProxyAddress);
  console.log("OracleProxy implementation deployed to: ", implAddress);

  const code = await ethers.provider.getCode(oracleProxyAddress);
  if (code === "0x") {
    throw new Error("Contract deployment failed - no code at address");
  }
  console.log("Contract code verified at address");

  let subsidizedGas = "";
  if (subsidizedGasEnv) {
    console.log("\nSetting subsidized gas to:", subsidizedGasEnv, "wei");
    const tx = await (proxy as any).setSubsidizedGas(subsidizedGasEnv);
    await tx.wait();
    subsidizedGas = subsidizedGasEnv;
    console.log("Subsidized gas set successfully");
  } else {
    subsidizedGas = (await (proxy as any).subsidizedGas()).toString();
    console.log("\nSubsidized gas (default):", subsidizedGas, "wei");
  }

  const networkInfo = await ethers.provider.getNetwork();
  const networkName = network.name || `chain-${networkInfo.chainId}`;

  const addresses = {
    oracleProxyEvm: oracleProxyAddress,
    bridge: bridgeAddress,
    messageBridge: messageBridgeAddress,
    executionManager: executionManagerAddress,
    n3OracleProxy: n3OracleProxyAddress,
    owner: ownerAddress,
    subsidizedGas: subsidizedGas,
    deployer: deployer.address,
    network: networkName,
    chainId: networkInfo.chainId.toString()
  };

  const addressesPath = path.join(__dirname, "../deployment-addresses.json");
  fs.writeFileSync(addressesPath, JSON.stringify(addresses, null, 2));
  console.log("\nDeployment addresses saved to:", addressesPath);

  console.log("\n=== Deployment Summary ===");
  console.log("OracleProxy (proxy):         ", oracleProxyAddress);
  console.log("OracleProxy (implementation):", implAddress);
  console.log("Owner:", ownerAddress);
  console.log("Bridge:", bridgeAddress);
  console.log("MessageBridge:", messageBridgeAddress);
  console.log("ExecutionManager:", executionManagerAddress);
  console.log("N3 Oracle Proxy:", n3OracleProxyAddress);
  console.log("Subsidized Gas:", subsidizedGas, "wei");
}

async function dryRun(deployerAddress: string) {
  const nonce = await ethers.provider.getTransactionCount(deployerAddress);

  // Predict addresses for several consecutive nonces so you can see which
  // nonce produces which address. The actual order depends on whether the
  // OZ upgrades plugin uses CREATE or CREATE2 for the implementation on
  // this network — verify against a testnet deployment before going live.
  const lookahead = 5;
  console.log("\n=== Dry Run — Predicted CREATE Addresses ===");
  console.log("Current deployer nonce:", nonce);
  console.log("");
  for (let i = 0; i < lookahead; i++) {
    const n = nonce + i;
    const addr = ethers.getCreateAddress({ from: deployerAddress, nonce: n });
    console.log(`  nonce ${n} → ${addr}`);
  }
  console.log("\nNote: OZ hardhat-upgrades may deploy the implementation via CREATE2");
  console.log("(not consuming a deployer nonce) depending on the network. Check the");
  console.log("nonce script after a testnet deploy to confirm the actual order.");
  console.log("\nNo transactions were sent.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
