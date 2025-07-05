import { config } from "@onflow/fcl";

config({
  // Application details
  "app.detail.title": "Flow Prize Savings",
  "app.detail.icon": "https://cdn.sanity.io/images/kts928pd/production/fb3dd18e5938bd78cca39c1a4df02eba65f424df-731x731.png",

  // Flow Access Node for Testnet
  "accessNode.api": "https://rest-testnet.onflow.org",

  // FCL Wallet Discovery endpoint for Testnet
  "discovery.wallet": "https://fcl-discovery.onflow.org/testnet/authn",

  // Account proof configuration
  "fcl.account.proof.vsn": "2.0.0",

  // EVM-specific configurations for COA bridging
  "flow.network": "testnet",
  "fcl.limit": 1000,

  // Enable COA (Cadence Owned Account) support for EVM bridging
  "fcl.eventPollRate": 2500,

  // Configure for EVM compatibility
  "sdk.transport": "HTTP",

  // Service discovery configuration to ensure EVM-compatible wallets are prioritized
  "discovery.authn.endpoint": "https://fcl-discovery.onflow.org/testnet/authn",
  "discovery.authn.include": ["https://fcl-discovery.onflow.org/testnet/authn"],

  // Additional EVM bridge configurations
  "fcl.walletconnect.projectId": import.meta.env.VITE_WALLETCONNECT_PROJECT_ID || "",
});