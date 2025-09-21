require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
require('hardhat-ignore-warnings');
require("hardhat-contract-sizer");

const accounts = require('../accounts');
const account = accounts.alfa;

const networks = {
  localhost: {
    url: "http://127.0.0.1:8545"
  },
  bsc: {
    url: "https://bsc-dataseed1.bnbchain.org",
    chainId: 56,
    gasPrice: 1600000000,
    accounts: [account.privateKey]
  }
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
  networks: networks,
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
      // {
      //   network: "bsc",
      //   chainId: 56,
      //   urls: {
      //     apiURL: "https://api.etherscan.io/v2/api?chainid=56",
      //     browserURL: "https://bscscan.com"
      //   }
      // },
    ]
  }
};
