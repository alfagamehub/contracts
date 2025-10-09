import fs from "fs";
import path from "path";

const CONTRACT = "contracts/forge/ALFAForge.sol/ALFAForge"; // путь без расширения
const DBG_PATH = path.resolve(`artifacts/${CONTRACT}.dbg.json`);

async function main() {
  if (!fs.existsSync(DBG_PATH)) {
    throw new Error(`.dbg.json не найден: ${DBG_PATH}`);
  }

  const dbg = JSON.parse(fs.readFileSync(DBG_PATH, "utf8"));
  const buildInfoPath = path.resolve(dbg.buildInfo);
  if (!fs.existsSync(buildInfoPath)) {
    throw new Error(`build-info не найден: ${buildInfoPath}`);
  }

  const buildInfo = JSON.parse(fs.readFileSync(buildInfoPath, "utf8"));
  const input = buildInfo.input;

  const outPath = path.resolve("scripts/solc-input.json");
  fs.writeFileSync(outPath, JSON.stringify(input, null, 2));
  console.log(`✅ solc-input.json создан: ${outPath}`);

  // Дополнительно покажем краткую сводку
  console.log("Compiler version:", buildInfo.solcVersion);
  console.log("Optimizer:", input.settings.optimizer);
  console.log("Sources:", Object.keys(input.sources).length);
}

main().catch((e) => {
  console.error("Ошибка:", e);
  process.exit(1);
});