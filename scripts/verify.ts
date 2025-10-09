import hre from "hardhat";
import { verifyContract } from "@nomicfoundation/hardhat-verify/verify";
import constructorArgs from "./args/alfaForge.args.js";

await verifyContract(
  {
    address: "0x920df4022b90Eb846B8193c64c13C7260c02E37a",
    constructorArgs,
    provider: "etherscan",
  },
  hre,
);