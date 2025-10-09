import type { HardhatUserConfig } from "hardhat/config";

import hardhatIgnitionViem from "@nomicfoundation/hardhat-ignition-viem";
import hardhatVerify from "@nomicfoundation/hardhat-verify";
import hardhatEthers from "@nomicfoundation/hardhat-ethers";
import accounts from "../accounts.js";

type Account = {
  address: string;
  privateKey: string;
}
type Accounts = {
  alfa: Account,
  bscscan?: string,
}

const alfaAccount = accounts?.alfa;
const bscAccounts = alfaAccount?.privateKey ? [alfaAccount?.privateKey] : undefined;

const config: HardhatUserConfig = {
  plugins: [hardhatEthers, hardhatVerify, hardhatIgnitionViem],
  solidity: {
    profiles: {
      default: {
        version: "0.8.24",
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    },
  },
  networks: {
    hardhatMainnet: {
      type: "edr-simulated",
      chainType: "l1",
    },
    hardhatOp: {
      type: "edr-simulated",
      chainType: "op",
    },
    bsc: {
      type: "http",
      url: "https://bsc-dataseed1.bnbchain.org",
      chainId: 56,
      gasPrice: 100000000,
      ...(bscAccounts ? { accounts: bscAccounts } : {}),
    },
  },
  verify: {
    etherscan: {
      apiKey: accounts.bscscan,
      customChains: [
        {
          network: "bsc",
          chainId: 56,
          urls: {
            apiURL: "https://api.bscscan.com/api",
            browserURL: "https://bscscan.com"
          }
        },
      ]
    }
  },
};

export default config;
