# UUPS Upgradeable Contract Suite - Solidity

Upgradeable smart contracts using OpenZeppelin's UUPS (Universal Upgradeable Proxy Standard) pattern.

## Contracts

### OrangeUpgradeableVault.sol (V1)
Base upgradeable ETH vault with deposit/withdraw functionality.
- UUPS proxy pattern with ERC1967 storage
- Custom errors for gas efficiency
- Storage gaps for upgrade safety

### OrangeUpgradeableVaultV2.sol
Enhanced vault demonstrating safe upgrade patterns.
- Withdrawal fee system (basis points)
- Pause/unpause capability
- Batch withdrawals
- Fee collection by owner

## Setup

```bash
npm install
```

## Test

```bash
npx hardhat test
```

## Key Features

- **UUPS Pattern**: Upgrade logic in implementation, not proxy
- **Reinitializer**: V2 uses `reinitializer(2)` for safe migration
- **Storage Gaps**: `__gap[48]` preserves layout compatibility
- **Custom Errors**: Gas-efficient error handling

## Test Coverage

- 46 tests covering initialization, deposits, withdrawals, upgrades, fees, pausing, and batch operations

After setting the variable, you can run the deployment with the Sepolia network:

```shell
npx hardhat ignition deploy --network sepolia ignition/modules/Counter.ts
```
