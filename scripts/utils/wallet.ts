import { Wallet } from "ethers";
import { Provider } from "ethers";
import fs from "fs";
import { ethers } from "hardhat";
import { vars } from "hardhat/config";

// Get password from hardhat vars (defaults to empty string for devnet)
export const DEPLOYER_PASSWORD = vars.get('BRIDGE_DEPLOYER_PASSWORD', '');

export function getDeployer(provider: Provider): Wallet {
    return getWalletFromFile("wallets/deployer.json", DEPLOYER_PASSWORD).connect(provider);
}

function getWalletFromFile(filename: string, password: string): Wallet {
    var buf = fs.readFileSync(filename);
    return ethers.Wallet.fromEncryptedJsonSync(buf.toString(), password) as Wallet;
}
