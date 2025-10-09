import hre from "hardhat";
import fs from "node:fs";
import path from "node:path";
import { keccak256, JsonRpcProvider } from "ethers";

function strip0x(hex: string) { return hex?.startsWith("0x") ? hex.slice(2) : hex; }
function add0x(hex: string) { return hex?.startsWith("0x") ? hex : ("0x" + hex); }

// Strip Solidity metadata (CBOR) from end of runtime bytecode
function stripMetadata(runtimeHex: string) {
  const hex = strip0x(runtimeHex);
  if (!hex || hex.length < 4) return add0x(hex || "");
  // last 2 bytes = metadata length in bytes
  const lenBytesHex = hex.slice(-4);
  const metadataLen = parseInt(lenBytesHex, 16) * 2; // bytes -> hex chars
  const totalLen = hex.length;
  const cut = totalLen - (metadataLen + 4);
  if (metadataLen <= 0 || cut <= 0) return add0x(hex);
  return add0x(hex.slice(0, cut));
}

async function main() {
  const address = process.env.ADDR as string;
  if (!address) throw new Error("Provide ADDR=0x... env var");

  const artifactPath = path.join(
    hre.config.paths.artifacts,
    "contracts/forge/ALFAForge.sol/ALFAForge.json"
  );
  console.log("Artifact:", artifactPath);
  const artifactRaw = fs.readFileSync(artifactPath, "utf8");
  const artifact = JSON.parse(artifactRaw);
  const localRuntime: string = artifact.deployedBytecode?.object || artifact.deployedBytecode || artifact.bytecode?.deployedObject || "";
  if (!localRuntime) throw new Error("Local deployedBytecode not found in artifact");

  // Use a direct JsonRpcProvider; don't rely on hre.network or nested config shapes
  const rpcUrl = process.env.BSC_RPC_URL || "https://bsc-dataseed1.bnbchain.org";
  const provider = new JsonRpcProvider(rpcUrl);
  const chainRuntime: string = await provider.getCode(address);
  if (!chainRuntime || chainRuntime === "0x") {
    throw new Error(`No code at ${address} (url: ${rpcUrl})`);
  }

  const localStripped = stripMetadata(localRuntime);
  const chainStripped = stripMetadata(chainRuntime);

  console.log('localRuntime:\n', localRuntime);
  console.log('chainRuntime:\n', chainRuntime);

  const eqFull = strip0x(localRuntime).toLowerCase() === strip0x(chainRuntime).toLowerCase();
  const eqStripped = strip0x(localStripped).toLowerCase() === strip0x(chainStripped).toLowerCase();

  // Find first differing nibble (hex char) and show a small diff window
  function firstDiffIndex(a: string, b: string) {
    const A = strip0x(a).toLowerCase();
    const B = strip0x(b).toLowerCase();
    const n = Math.min(A.length, B.length);
    for (let i = 0; i < n; i++) {
      if (A[i] !== B[i]) return i; // nibble index
    }
    return A.length === B.length ? -1 : n;
  }

  const diffNibble = firstDiffIndex(localStripped, chainStripped);
  const diffByte = diffNibble === -1 ? -1 : Math.floor(diffNibble / 2);

  // Try to map diff to immutable references from the artifact (if available)
  type ImmRange = { key: string; start: number; length: number; end: number };
  const immRefsRaw = artifact.deployedBytecode?.immutableReferences || {};
  const immRanges: ImmRange[] = Object.entries(immRefsRaw).flatMap(([key, arr]: [string, any[]]) =>
    (arr || []).map((r: any) => ({ key, start: r.start, length: r.length, end: r.start + r.length - 1 }))
  );
  const hit = diffByte >= 0 ? immRanges.find(r => diffByte >= r.start && diffByte <= r.end) : undefined;

  if (diffByte >= 0) {
    const windowBytes = 32; // show +/- 32 bytes around the diff
    const A = strip0x(localStripped);
    const B = strip0x(chainStripped);
    const start = Math.max(0, (diffByte - windowBytes) * 2);
    const end = Math.min(A.length, (diffByte + windowBytes) * 2);
    const markPos = diffByte * 2 - start; // nibble offset within window

    console.log("\nFirst difference at byte offset:", diffByte, "(nibble:", diffNibble, ")");
    if (hit) console.log("Diff falls within immutable ref:", hit);

    const aWin = A.slice(start, end);
    const bWin = B.slice(start, end);
    console.log("Local window:", add0x(aWin));
    console.log("Chain window:", add0x(bWin));

    // Visual marker line (space up to markPos, then ^)
    console.log("Marker       :", " ".repeat(Math.max(0, markPos)) + "^");
  } else {
    console.log("\nNo differences found in stripped bytecode.");
  }

  const keccak = (hex: string) => keccak256(add0x(strip0x(hex).toLowerCase()));

  console.log("\n=== Bytecode Comparison ===");
  console.log("Address:", address);
  console.log("Compiler:", artifact.compiler?.version, "optimizer:", artifact.settings?.optimizer);
  console.log("viaIR:", artifact.settings?.viaIR, "evmVersion:", artifact.settings?.evmVersion);
  console.log("Local runtime length (bytes):", strip0x(localRuntime).length / 2);
  console.log("Chain runtime length (bytes):", strip0x(chainRuntime).length / 2);
  console.log("Equal (full)    :", eqFull);
  console.log("Equal (stripped):", eqStripped);
  console.log("Local full   keccak:", keccak(localRuntime));
  console.log("Chain full   keccak:", keccak(chainRuntime));
  console.log("Local strip  keccak:", keccak(localStripped));
  console.log("Chain strip  keccak:", keccak(chainStripped));

  // Print last 64 bytes to spot metadata differences
  const tail = 64 * 2; // 128 hex chars
  console.log("\nLocal tail:", add0x(strip0x(localRuntime).slice(-tail)));
  console.log("Chain tail:", add0x(strip0x(chainRuntime).slice(-tail)));
}

main().catch((e) => { console.error(e); process.exit(1); });
