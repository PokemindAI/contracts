import type {HardhatUserConfig} from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";
import "hardhat-deploy"
import "dotenv/config"

const MAINNET_RPC_URL = process.env.MAINNET_RPC_URL || "https://eth-mainnet.g.alchemy.com/v2/your-api-key"
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY || "api-key"

// Import MNEMONIC or single private key (PK takes precedence)
const MNEMONIC = process.env.MNEMONIC || "your mnemonic"
const PRIVATE_KEY = process.env.PRIVATE_KEY

const config: HardhatUserConfig = {
    solidity: {
        version: "0.8.28",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200
            }
        }
    },
    defaultNetwork: "hardhat",
    networks: {
        hardhat: {
            forking: {
                url: MAINNET_RPC_URL
            }
        },
        localhost: {
            url: "http://127.0.0.1:8545",
        },
    },
    paths: {
        sources: "./src",
        tests: "./test",
        cache: "./cache",
        artifacts: "./artifacts"
    },
    namedAccounts: {
        deployer: {
            default: 0, // here this will by default take the first account as deployer
            mainnet: 0, // similarly on mainnet it will take the first account as deployer.
        },
        owner: {
            default: 0,
        },
    },
};

export default config;