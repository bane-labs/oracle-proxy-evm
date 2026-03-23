import { ethers } from "hardhat";
import { getDeployer } from "./utils/wallet";

async function main() {
    const provider = ethers.provider;
    const deployer = getDeployer(provider);
    const nonce = await provider.getTransactionCount(deployer.address);
    console.log(`Deployer address: ${deployer.address}`);
    console.log(`Transaction count (nonce): ${nonce}`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
