# Alfa Protocol BNB Smart Contracts

This repository contains the on-chain components for the AlfaGame project, implemented with the Hardhat development framework.

## Overview

The contracts are designed for deployment to EVM-compatible networks with a focus on the **BNB Smart Chain** ecosystem. They include core game logic, utility libraries, and deployment scripts used to manage the AlfaGame protocol lifecycle.

## Getting Started

1. Install dependencies:
   ```bash
   npm install
   ```
2. Compile the contracts:
   ```bash
   npx hardhat compile
   ```
3. Run the test suite:
   ```bash
   npx hardhat test
   ```

## Project Structure

- `contracts/` – Solidity source files.
- `scripts/` – Hardhat deployment and maintenance scripts.
- `test/` – Automated tests written in JavaScript/TypeScript.
- `docs/` – Additional protocol documentation.

## Configuration

Update `hardhat.config.js` with the appropriate RPC endpoints, private keys, and network identifiers before deploying to testnet or mainnet. Remember to secure any sensitive credentials with environment variables or a secrets manager.

## Contributing

Contributions are welcome! Please open an issue describing the proposed change and submit a pull request once the fix or feature is ready.

## License

This project is licensed under the terms of the MIT License. See [LICENSE](LICENSE) for details.
