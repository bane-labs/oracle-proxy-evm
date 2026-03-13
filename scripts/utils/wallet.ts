import { Wallet } from "ethers";
import { Provider } from "ethers";
import fs from "fs";
import { ethers } from "hardhat";

// Wallet resolution priority (all configured via .env):
//   1. DEPLOYER_PRIVATE_KEY  – raw private key (highest priority)
//   2. DEPLOYER_WALLET_FILE  – path to an encrypted keystore JSON
//   3. wallets/deployer.json – default keystore (devnet fallback)

export function getDeployer(provider: Provider): Wallet {
    if (process.env.DEPLOYER_PRIVATE_KEY) {
        return new ethers.Wallet(process.env.DEPLOYER_PRIVATE_KEY).connect(provider);
    }

    const walletFile = process.env.DEPLOYER_WALLET_FILE || "wallets/deployer.json";
    const password = process.env.BRIDGE_DEPLOYER_PASSWORD || "";

    return getWalletFromFile(walletFile, password).connect(provider);
}

function getWalletFromFile(filename: string, password: string): Wallet {
    const buf = fs.readFileSync(filename);
    return ethers.Wallet.fromEncryptedJsonSync(buf.toString(), password) as Wallet;
}
