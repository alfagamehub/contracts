// scripts/dump-solc-input.js
const fs = require("fs");
const path = require("path");
const hre = require("hardhat");

/**
 * Usage:
 *   node scripts/dump-solc-input.js contracts/forge/ALFAForge.sol:ALFAForge
 *   # или просто node scripts/dump-solc-input.js (тогда возьмёт первый FQN из списка)
 */
async function main() {
  const fqNameArg = process.argv[2]; // "file.sol:ContractName"
  
  // Если не передали FQN — возьмём первый подходящий
  const all = await hre.artifacts.getAllFullyQualifiedNames();
  const fqName = fqNameArg || all[0];
  
  const buildInfo = await hre.artifacts.getBuildInfo(fqName);
  if (!buildInfo) {
    throw new Error(
      `Build info не найден для ${fqName}. ` +
      `Убедись, что контракт компилировался: npx hardhat compile`
    );
  }
  
  // Это и есть Solidity Standard JSON Input (как ждёт Etherscan/BscScan)
  const outPath = path.resolve("solc-input.json");
  fs.writeFileSync(outPath, JSON.stringify(buildInfo.input, null, 2));
  console.log("✅ solc-input.json записан:", outPath);
  console.log("solcVersion:", buildInfo.solcVersion);
  console.log("contracts in build-info:", Object.keys(buildInfo.output.contracts || {}).length);
}

main().catch((e) => {
  console.error("Ошибка:", e.message);
  process.exit(1);
});