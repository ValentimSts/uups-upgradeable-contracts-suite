# UUPS Upgradeable Contracts Suite

Upgradeable smart contracts using the UUPS (Universal Upgradeable Proxy Standard) pattern.

## Features

- UUPS proxy pattern with ERC1967 storage
- V1 base vault with deposit/withdraw
- V2 upgrade with fees, pause, batch operations
- Storage gaps for safe upgrades

## Structure

```
solidity/   - Solidity implementation
vyper/      - Vyper implementation
```

## Quick Start

```bash
cd solidity && npm install && npx hardhat test
cd vyper && pip install -r requirements.txt && npx hardhat test
```
