require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
require("hardhat-ignore-warnings");
require("hardhat-contract-sizer");

const fs = require("fs");
const path = require("path");

const hardhatDownloadModule = require("hardhat/internal/util/download");
const originalDownload = hardhatDownloadModule.download;

const SOLC_MIRROR_URL =
  process.env.SOLC_BIN_MIRROR ??
  "https://raw.githubusercontent.com/ethereum/solc-bin/gh-pages";

hardhatDownloadModule.download = async (url, filePath, ...rest) => {
  if (url.startsWith("https://binaries.soliditylang.org")) {
    const mirrorUrl = `${SOLC_MIRROR_URL}${url.substring(
      "https://binaries.soliditylang.org".length
    )}`;
    return originalDownload(mirrorUrl, filePath, ...rest);
  }

  return originalDownload(url, filePath, ...rest);
};

const accountsPath = path.join(__dirname, "..", "accounts.js");
let accounts = {};
if (fs.existsSync(accountsPath)) {
  // eslint-disable-next-line global-require, import/no-dynamic-require
  accounts = require(accountsPath);
}

const alfaAccount = accounts.alfa ?? {};
const bscAccounts = alfaAccount.privateKey ? [alfaAccount.privateKey] : undefined;

const networks = {
  localhost: {
    url: "http://127.0.0.1:8545",
  },
  bsc: {
    url: "https://bsc-dataseed1.bnbchain.org",
    chainId: 56,
    gasPrice: 1600000000,
    ...(bscAccounts ? {accounts: bscAccounts} : {}),
  },
};

module.exports = {
  solidity: {
    version: "0.8.24",
    settings: {
      viaIR: false,
      optimizer: {
        enabled: true,
        runs: 1
      },
      evmVersion: 'cancun',
    }
  },
  networks,
  etherscan: {
    enabled: true,
    apiKey: accounts.bscscan,
    customChains: [
      {
        network: "skaletest",
        chainId: 37084624,
        urls: {
          apiURL: "https://testnet.skalenodes.com/v1/lanky-ill-funny-testnet/api",
          browserURL: "https://lanky-ill-funny-testnet.explorer.testnet.skalenodes.com"
        }
      },
      {
        network: "bsc",
        chainId: 56,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=56",
          browserURL: "https://bscscan.com"
        }
      },
    ]
  }
};
