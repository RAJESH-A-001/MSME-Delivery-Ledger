import { defineConfig } from "hardhat/config";
import HardhatToolboxMochaEthers from "@nomicfoundation/hardhat-toolbox-mocha-ethers";

/**
 * Hardhat 3 configuration — MSME Delivery & Acceptance Ledger
 *
 * Key Hardhat 3 changes from v2:
 * - Requires ESM (type: "module" in package.json)
 * - Uses defineConfig() helper
 * - Plugins registered in the plugins array
 * - Local network uses type: "edr-simulated" (replaces implicit HardhatNetwork)
 * - Remote networks use type: "http"
 */
export default defineConfig({
  plugins: [HardhatToolboxMochaEthers],

  solidity: {
    version: "0.8.19",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    // Local in-process blockchain simulation (EDR)
    hardhat: {
      type: "edr-simulated",
      chainType: "l1",
    },

    // Sepolia testnet — configure via .env (never hardcode keys)
    // sepolia: {
    //   type: "http",
    //   url: process.env.ETHEREUM_RPC_URL,
    //   accounts: [process.env.DEPLOYER_PRIVATE_KEY],
    // },
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
});
