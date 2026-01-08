# CAPShield Smart Contracts

Gas-optimized BEP-20 tokens for the CAPShield ecosystem on BNB Smart Chain, built with a hybrid Solady + OpenZeppelin architecture.

## Token Details

### CAPY Token (Shield Token)

- **Name**: CAPShield Token
- **Symbol**: CAPY
- **Decimals**: 18
- **Hard Cap**: 100,000,000 (Immutable)
- **Type**: Utility Token with Transfer Fees

**Features:**

- Role-based minting (Team, Treasury, DAO)
- Revenue-based minting formula
- 1% burn + 1% treasury fee on transfers
- Fee exemptions for Treasury and DAO
- Pause/unpause functionality
- Multisig-only admin

### SEED Token (Community Token)

- **Name**: CAPShield Community Token
- **Symbol**: SEED
- **Decimals**: 18
- **Hard Cap**: 10,000,000,000 (Immutable)
- **Type**: Reward Token

**Features:**

- Reward minting role
- No transfer fees
- Pause/unpause functionality
- Multisig-only admin

## Architecture

Built with a hybrid approach for maximum security and gas efficiency on BNB Smart Chain:

- **Solady**: Gas-optimized ERC20/BEP-20 and OwnableRoles (bitmap-based)
- **OpenZeppelin**: Battle-tested Pausable contract
- **Solidity 0.8.30**: Latest features (custom errors, named mappings)

**Gas Savings (BSC):**

- CAPY deployment: 1,886,089 gas (6.3% of block limit)
- SEED deployment: 1,278,504 gas (4.3% of block limit)
- ~30-40% savings vs pure OpenZeppelin implementation
- Lower transaction costs on BSC vs Ethereum

## Security Features

1. **Multisig Enforcement**: Admin MUST be a contract (multisig), not an EOA

   - Enforced at deployment
   - Enforced on ownership transfer
   - Ownership cannot be renounced

2. **Hard Cap Protection**: Immutable supply cap with burn tracking

   - Burning tokens doesn't free mint capacity
   - `totalMinted` tracker prevents bypass

3. **Role-Based Access Control**: Bitmap-optimized roles for gas efficiency

   - CAPY: TEAM_MINTER, TREASURY_MINTER, DAO_MINTER
   - SEED: REWARD_MINTER

4. **Emergency Pause**: Admin can pause all transfers and minting

## Testing

Comprehensive test suite with 77 tests covering all functionality:

```bash
npm test
```

**Test Coverage:**

- CAPY Token: 46 tests
- SEED Token: 31 tests
- All edge cases and security scenarios

**Test Categories:**

1. Deployment & Initial State
2. Access Control
3. Hard Cap Enforcement
4. Role-Based Minting
5. Revenue-Based Minting (CAPY)
6. Transfer Hooks & Fees (CAPY)
7. Fee Exemptions (CAPY)
8. Pause & Emergency Stop
9. Burn Logic
10. Admin Functions
11. Ownership Security
12. Event Logging

## Contract Structure

```
contracts/
├── CAPY.sol              # Shield Token (main contract)
├── SEED.sol              # Community Token (main contract)
├── interfaces/
│   ├── ICAPY.sol         # CAPY interface
│   └── ISEED.sol         # SEED interface
└── test/
    └── MockMultisig.sol  # Mock multisig for testing
```
