# CAPShield Tokens Deployment Guide

This guide provides step-by-step instructions for deploying the CAPX and ANGEL token contracts.

---

## Prerequisites

### Required Software

- Node.js v16 or higher
- npm or yarn package manager

### Required Accounts/Contracts

- **Deployer Account**: An account with sufficient native tokens (ETH/BNB/MATIC) to pay for gas
- **Multisig Contract**: A deployed multisig wallet (e.g., Gnosis Safe) that will be the admin
  - ⚠️ **CRITICAL**: The admin MUST be a contract, not an EOA (Externally Owned Account)
  - This ensures no single person has full control over the tokens
- **Treasury Address**: Address that will receive 1% transfer fees from CAPX
- **DAO Address**: Address for DAO governance and minting operations

### Multisig Setup

If you don't have a multisig wallet yet:

**For Testnet:**

- Use Gnosis Safe: https://app.safe.global/

**For Mainnet:**

- Deploy a Gnosis Safe via https://app.safe.global/
- Configure with appropriate signers and threshold
- Recommended: 3-of-5 or 4-of-7 multisig

---

## Environment Setup

### 1. Install Dependencies

```bash
npm install
```

### 2. Configure Environment Variables

Copy the example environment file:

```bash
cp .env.example .env
```

Edit `.env` with your actual values:

```bash
# Deployer private key (DO NOT share or commit this!)
PRIVATE_KEY=your_private_key_here

# Multisig contract address (MUST be a contract)
MULTISIG_ADDRESS=0x1234567890123456789012345678901234567890

# Treasury address (receives 1% fees from CAPX transfers)
TREASURY_ADDRESS=0x1234567890123456789012345678901234567890

# DAO address (for governance and DAO minting)
DAO_ADDRESS=0x1234567890123456789012345678901234567890

# Block explorer API keys (for verification)
ETHERSCAN_API_KEY=your_etherscan_api_key
BSCSCAN_API_KEY=your_bscscan_api_key
```

### 3. Fund Deployer Account

Ensure your deployer account has sufficient funds:

| Network     | Required Amount | Faucet/Source                             |
| ----------- | --------------- | ----------------------------------------- |
| Sepolia     | ~0.05 ETH       | https://sepoliafaucet.com/                |
| Mumbai      | ~0.1 MATIC      | https://mumbaifaucet.com/                 |
| BSC Testnet | ~0.05 BNB       | https://testnet.bnbchain.org/faucet-smart |
| BSC Mainnet | ~0.01 BNB       | Buy on exchange                           |

---

## Deployment

### Using NPM Scripts (Recommended)

**Deploy to Sepolia (Ethereum Testnet):**

```bash
npm run deploy:sepolia
```

**Deploy to Mumbai (Polygon Testnet):**

```bash
npm run deploy:mumbai
```

**Deploy to BSC Testnet:**

```bash
npm run deploy:bscTestnet
```

**Deploy to BSC Mainnet:**

```bash
npm run deploy:bscMainnet
```

### Using Hardhat Directly

```bash
npx hardhat run scripts/deploy.js --network <network-name>
```

Replace `<network-name>` with:

- `sepolia` - Ethereum Sepolia testnet
- `mumbai` - Polygon Mumbai testnet
- `bscTestnet` - BSC testnet
- `bscMainnet` - BSC mainnet

---

## What Happens During Deployment

1. **Validation Phase**

   - Checks all required environment variables are set
   - Validates addresses are in correct format
   - Verifies MULTISIG_ADDRESS is a contract (not an EOA)

2. **Deployment Phase**

   - Deploys CAPX token with treasury, DAO, and multisig addresses
   - Deploys ANGEL token with multisig address
   - Both contracts verify multisig is a contract during construction

3. **Verification Phase**

   - Checks token names, symbols, and decimals
   - Verifies max supply values
   - Confirms multisig has DEFAULT_ADMIN_ROLE on both tokens
   - Displays all deployment information

4. **Output Phase**
   - Saves deployment info to `deployments/deployment-<network>-<timestamp>.json`
   - Prints contract verification commands
   - Shows summary of deployed contracts

---

## Expected Output

```
==========================================
CAPShield Tokens Deployment
==========================================
Network: sepolia
Chain ID: 11155111
Deployer: 0x1234...5678
Balance: 0.1 ETH
==========================================

Configuration:
  Multisig (Admin): 0xabcd...efgh
  Treasury: 0x1111...2222
  DAO: 0x3333...4444

✓ Verified: Multisig address is a contract

Deploying CAPX Token (CAPY - Shield Token)...
✓ CAPX (ERC-20) deployed to: 0x5555...6666
  Transaction: 0xabcd...1234

Deploying ANGEL Token (SEED - Community Token)...
✓ ANGEL (ERC-20) deployed to: 0x7777...8888
  Transaction: 0xefgh...5678

Verifying deployments...
CAPX Token:
  Name: CAPShield Token
  Symbol: CAPY
  Decimals: 18
  Max Supply: 100000000.0 CAPY
  Treasury: 0x1111...2222
  DAO: 0x3333...4444
  Multisig has DEFAULT_ADMIN_ROLE: true

ANGEL Token:
  Name: AngleSeed Token
  Symbol: SEED
  Decimals: 18
  Max Supply: 10000000000.0 SEED
  Multisig has DEFAULT_ADMIN_ROLE: true

✓ All tokens correctly configured with multisig admin

✓ Deployment info saved to: deployments/deployment-sepolia-1234567890.json

==========================================
Contract Verification Commands (Etherscan Sepolia)
==========================================

CAPX Token:
npx hardhat verify --network sepolia 0x5555...6666 "0x1111...2222" "0x3333...4444" "0xabcd...efgh"

ANGEL Token:
npx hardhat verify --network sepolia 0x7777...8888 "0xabcd...efgh"

==========================================
Deployment Complete!
==========================================
```

---

## Contract Verification

After deployment, copy the verification commands from the output and run them:

**CAPX Token:**

```bash
npx hardhat verify --network sepolia <CAPX_ADDRESS> "<TREASURY_ADDRESS>" "<DAO_ADDRESS>" "<MULTISIG_ADDRESS>"
```

**ANGEL Token:**

```bash
npx hardhat verify --network sepolia <ANGEL_ADDRESS> "<MULTISIG_ADDRESS>"
```

---
