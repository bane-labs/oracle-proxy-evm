import { ethers } from "hardhat";

async function main() {
  const oracleProxyAddr = "0xF4A2D63b598F3c0b8095FBec64e012605f481DB8";
  const provider = ethers.provider;
  
  const iface = new ethers.Interface([
    "function getOracleResult(uint256 _requestId) external view returns (bytes memory result, bool exists)"
  ]);
  
  const requestId = 4;
  const data = iface.encodeFunctionData("getOracleResult", [requestId]);
  
  console.log(`Calling getOracleResult(${requestId}) on OracleProxy...`);
  console.log("Contract address:", oracleProxyAddr);
  
  const result = await provider.call({ to: oracleProxyAddr, data });
  
  if (result === "0x") {
    console.log("No result data returned");
    return;
  }
  
  const decoded = iface.decodeFunctionResult("getOracleResult", result);
  const oracleResult = decoded[0];
  const exists = decoded[1];
  
  console.log("\n=== Result ===");
  console.log("exists:", exists);
  
  if (exists) {
    console.log("result length:", ethers.getBytes(oracleResult).length, "bytes");
    console.log("result hex:", oracleResult);
    
    // Try to decode as UTF-8 string
    try {
      const utf8Result = ethers.toUtf8String(oracleResult);
      console.log("\nresult (UTF-8):");
      console.log(utf8Result);
    } catch {
      console.log("\nresult is not valid UTF-8");
    }
  } else {
    console.log("No oracle result found for requestId", requestId);
  }
}

main().catch(console.error);
