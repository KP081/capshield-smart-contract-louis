// scripts/deploy.js
const { ethers, network } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  const [deployer] = await ethers.getSigners();

  // Get network-specific info
  const networkInfo = {
    bscTestnet: { symbol: "BNB", tokenStandard: "BEP-20", explorer: "BscScan Testnet" },
    bscMainnet: { symbol: "BNB", tokenStandard: "BEP-20", explorer: "BscScan" },
    sepolia: { symbol: "ETH", tokenStandard: "ERC-20", explorer: "Etherscan Sepolia" },
    mumbai: { symbol: "MATIC", tokenStandard: "ERC-20", explorer: "PolygonScan Mumbai" },
    hardhat: { symbol: "ETH", tokenStandard: "ERC-20", explorer: "Local" },
  };

  const currentNetwork = networkInfo[network.name] || { symbol: "ETH", tokenStandard: "ERC-20", explorer: "Explorer" };

  console.log("==========================================");
  console.log("CAPShield Token Deployment");
  console.log("==========================================");
  console.log("Network:", network.name);
  console.log("Chain ID:", network.config.chainId);
  console.log("Deployer:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), currentNetwork.symbol);
  console.log("==========================================\n");

  // CONFIGURATION
  // IMPORTANT: Update these addresses before deployment
  const MULTISIG_ADDRESS = process.env.MULTISIG_ADDRESS || "";
  const TREASURY_ADDRESS = process.env.TREASURY_ADDRESS || "";
  const DAO_ADDRESS = process.env.DAO_ADDRESS || "";

  // Validate configuration
  if (!MULTISIG_ADDRESS || !ethers.isAddress(MULTISIG_ADDRESS)) {
    throw new Error("Invalid or missing MULTISIG_ADDRESS. Set via environment variable.");
  }
  if (!TREASURY_ADDRESS || !ethers.isAddress(TREASURY_ADDRESS)) {
    throw new Error("Invalid or missing TREASURY_ADDRESS. Set via environment variable.");
  }
  if (!DAO_ADDRESS || !ethers.isAddress(DAO_ADDRESS)) {
    throw new Error("Invalid or missing DAO_ADDRESS. Set via environment variable.");
  }

  console.log("Configuration:");
  console.log("  Multisig (Admin):", MULTISIG_ADDRESS);
  console.log("  Treasury:", TREASURY_ADDRESS);
  console.log("  DAO:", DAO_ADDRESS);
  console.log("");

  // Verify multisig is a contract
  const multisigCode = await ethers.provider.getCode(MULTISIG_ADDRESS);
  if (multisigCode === "0x") {
    throw new Error(
      `MULTISIG_ADDRESS (${MULTISIG_ADDRESS}) is not a contract! ` +
      "Admin MUST be a multisig contract for security. Deployment aborted."
    );
  }
  console.log("✓ Verified: Multisig address is a contract\n");

  // Deploy CAPX Token
  console.log("Deploying CAPX Token (Shield Token)...");
  const CAPX = await ethers.getContractFactory("CAPX");
  const capx = await CAPX.deploy(MULTISIG_ADDRESS, TREASURY_ADDRESS, DAO_ADDRESS);
  await capx.waitForDeployment();
  const capxAddress = await capx.getAddress();
  console.log(`✓ CAPX (${currentNetwork.tokenStandard}) deployed to:`, capxAddress);
  console.log("  Transaction:", capx.deploymentTransaction().hash);
  console.log("");

  // Deploy AngelSEED Token
  console.log("Deploying AngelSEED Token (Community Token)...");
  const AngelSEED = await ethers.getContractFactory("AngelSEED");
  const angelSeed = await AngelSEED.deploy(MULTISIG_ADDRESS);
  await angelSeed.waitForDeployment();
  const angelSeedAddress = await angelSeed.getAddress();
  console.log(`✓ AngelSEED (${currentNetwork.tokenStandard}) deployed to:`, angelSeedAddress);
  console.log("  Transaction:", angelSeed.deploymentTransaction().hash);
  console.log("");

  // Verify deployments
  console.log("Verifying deployments...");

  const capxName = await capx.name();
  const capxSymbol = await capx.symbol();
  const capxDecimals = await capx.decimals();
  const capxMaxSupply = await capx.getMaxSupply();
  const capxOwner = await capx.owner();
  const capxIsMultisig = await capx.isOwnerMultisig();

  const angelSeedName = await angelSeed.name();
  const angelSeedSymbol = await angelSeed.symbol();
  const angelSeedDecimals = await angelSeed.decimals();
  const angelSeedMaxSupply = await angelSeed.getMaxSupply();
  const angelSeedOwner = await angelSeed.owner();
  const angelSeedIsMultisig = await angelSeed.isOwnerMultisig();

  console.log("CAPX Token:");
  console.log("  Name:", capxName);
  console.log("  Symbol:", capxSymbol);
  console.log("  Decimals:", capxDecimals);
  console.log("  Max Supply:", ethers.formatUnits(capxMaxSupply, 18), "CAPX");
  console.log("  Owner:", capxOwner);
  console.log("  Owner is Multisig:", capxIsMultisig);
  console.log("");

  console.log("AngelSEED Token:");
  console.log("  Name:", angelSeedName);
  console.log("  Symbol:", angelSeedSymbol);
  console.log("  Decimals:", angelSeedDecimals);
  console.log("  Max Supply:", ethers.formatUnits(angelSeedMaxSupply, 18), "AngelSEED");
  console.log("  Owner:", angelSeedOwner);
  console.log("  Owner is Multisig:", angelSeedIsMultisig);
  console.log("");

  // Validate multisig enforcement
  if (!capxIsMultisig || !angelSeedIsMultisig) {
    console.error("⚠️  WARNING: One or more tokens do not have a multisig owner!");
  } else {
    console.log("✓ All tokens correctly configured with multisig admin");
  }
  console.log("");

  // Create deployment info
  const deploymentInfo = {
    network: network.name,
    chainId: network.config.chainId,
    deployer: deployer.address,
    timestamp: new Date().toISOString(),
    contracts: {
      CAPX: {
        address: capxAddress,
        name: capxName,
        symbol: capxSymbol,
        decimals: Number(capxDecimals),
        maxSupply: capxMaxSupply.toString(),
        owner: capxOwner,
        isOwnerMultisig: capxIsMultisig,
        deploymentTx: capx.deploymentTransaction().hash,
        constructorArgs: [MULTISIG_ADDRESS, TREASURY_ADDRESS, DAO_ADDRESS],
      },
      AngelSEED: {
        address: angelSeedAddress,
        name: angelSeedName,
        symbol: angelSeedSymbol,
        decimals: Number(angelSeedDecimals),
        maxSupply: angelSeedMaxSupply.toString(),
        owner: angelSeedOwner,
        isOwnerMultisig: angelSeedIsMultisig,
        deploymentTx: angelSeed.deploymentTransaction().hash,
        constructorArgs: [MULTISIG_ADDRESS],
      },
    },
    config: {
      multisig: MULTISIG_ADDRESS,
      treasury: TREASURY_ADDRESS,
      dao: DAO_ADDRESS,
    },
  };

  // Save deployment info
  const deploymentsDir = path.join(__dirname, "..", "deployments");
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir);
  }

  const filename = `deployment-${network.name}-${Date.now()}.json`;
  const filepath = path.join(deploymentsDir, filename);
  fs.writeFileSync(filepath, JSON.stringify(deploymentInfo, null, 2));
  console.log("✓ Deployment info saved to:", filepath);
  console.log("");

  // Output verification commands
  console.log("==========================================");
  console.log(`Contract Verification Commands (${currentNetwork.explorer})`);
  console.log("==========================================");
  console.log("");
  console.log("CAPX Token:");
  console.log(`npx hardhat verify --network ${network.name} ${capxAddress} "${MULTISIG_ADDRESS}" "${TREASURY_ADDRESS}" "${DAO_ADDRESS}"`);
  console.log("");
  console.log("AngelSEED Token:");
  console.log(`npx hardhat verify --network ${network.name} ${angelSeedAddress} "${MULTISIG_ADDRESS}"`);
  console.log("");
  console.log("==========================================");
  console.log("Deployment Complete!");
  console.log("==========================================");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Deployment failed:");
    console.error(error);
    process.exit(1);
  });
