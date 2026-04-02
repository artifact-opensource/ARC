import { ethers } from "hardhat";

/**
 * Deploy ArtifactVault — Enterprise Snapshot NFT Contract
 *
 * Usage:
 *   npx hardhat run scripts/deploy-vault.ts --network base-sepolia
 */
async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying ArtifactVault with account:", deployer.address);

    const balance = await ethers.provider.getBalance(deployer.address);
    console.log("Account balance:", ethers.formatEther(balance), "ETH");

    if (balance < ethers.parseEther("0.001")) {
        throw new Error("Insufficient balance for deployment. Need at least 0.001 ETH.");
    }

    const ArtifactVault = await ethers.getContractFactory("ArtifactVault");
    const vault = await ArtifactVault.deploy();
    await vault.waitForDeployment();

    const address = await vault.getAddress();
    const deployTx = vault.deploymentTransaction();

    console.log("ArtifactVault deployed to:", address);
    console.log("Owner:", await vault.owner());
    console.log("TX hash:", deployTx?.hash);
    console.log("Contract name:", await vault.name());
    console.log("Contract symbol:", await vault.symbol());
    console.log("Total snapshots:", (await vault.totalSnapshots()).toString());

    // Save deployment info
    const fs = require("fs");
    const network = await ethers.provider.getNetwork();
    const deployInfo = {
        contract: "ArtifactVault",
        address: address,
        deployer: deployer.address,
        network: network.name,
        chainId: Number(network.chainId),
        txHash: deployTx?.hash || "",
        timestamp: new Date().toISOString()
    };

    const deployDir = "./deployment/vault";
    if (!fs.existsSync(deployDir)) fs.mkdirSync(deployDir, { recursive: true });
    fs.writeFileSync(
        `${deployDir}/deployment.json`,
        JSON.stringify(deployInfo, null, 2)
    );
    console.log("Deployment info saved to", `${deployDir}/deployment.json`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
