import { createConfig, http } from 'wagmi'
import { flowTestnet } from 'wagmi/chains'
import { fclWagmiAdapter } from '@onflow/fcl-wagmi-adapter'
import { metaMask, walletConnect, injected } from 'wagmi/connectors'
import * as fcl from '@onflow/fcl'

// Enhanced Flow Testnet configuration
const flowTestnetEnhanced = {
  ...flowTestnet,
  rpcUrls: {
    default: {
      http: ['https://testnet.evm.nodes.onflow.org'],
    },
    public: {
      http: ['https://testnet.evm.nodes.onflow.org'],
    },
  },
  blockExplorers: {
    default: {
      name: 'FlowScan',
      url: 'https://evm-testnet.flowscan.io',
    },
  },
} as const

// Define the chains array once to be passed to the config and connectors
const chains = [flowTestnetEnhanced] as const;

export const config = createConfig({
  chains, // Pass the chains array here
  connectors: [
    // Official FCL Wagmi connector with proper configuration
    fclWagmiAdapter({
      user: fcl.currentUser,
      config: fcl.config,
    }),
    metaMask({
      dappMetadata: {
        name: 'Flow Prize Savings',
        url: 'https://flow-prize-savings.vercel.app',
      },
    }),
    injected({
      target: 'metaMask',
    }),
    walletConnect({
      projectId: import.meta.env.VITE_WALLETCONNECT_PROJECT_ID || 'demo-project-id',
      metadata: {
        name: 'Flow Prize Savings',
        description: 'No-Loss Lottery on Flow',
        url: 'https://flow-prize-savings.vercel.app',
        icons: ['https://flow-prize-savings.vercel.app/icon.png'],
      },
    }),
  ],
  transports: {
    [flowTestnetEnhanced.id]: http('https://testnet.evm.nodes.onflow.org', {
      timeout: 30_000, // 30 seconds
      retryCount: 3,
      retryDelay: 1000, // 1 second
    }),
  },
  ssr: false,
  batch: {
    multicall: true,
  },
})

// Helper function to add Flow Testnet to MetaMask
export const addFlowTestnetToMetaMask = async () => {
  if (typeof window !== 'undefined' && window.ethereum) {
    try {
      await window.ethereum.request({
        method: 'wallet_addEthereumChain',
        params: [
          {
            chainId: '0x221', // 545 in hex
            chainName: 'Flow Testnet',
            nativeCurrency: {
              name: 'Flow',
              symbol: 'FLOW',
              decimals: 18,
            },
            rpcUrls: ['https://testnet.evm.nodes.onflow.org'],
            blockExplorerUrls: ['https://evm-testnet.flowscan.io'],
            iconUrls: ['https://assets.coingecko.com/coins/images/13446/small/flow-logo.png'],
          },
        ],
      })
      return true
    } catch (error) {
      console.error('Failed to add Flow Testnet to MetaMask:', error)
      return false
    }
  }
  return false
}

// Helper function to switch to Flow Testnet
export const switchToFlowTestnet = async () => {
  if (typeof window !== 'undefined' && window.ethereum) {
    try {
      await window.ethereum.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: '0x221' }], // 545 in hex
      })
      return true
    } catch (error: any) {
      // Chain not added to MetaMask
      if (error.code === 4902) {
        return await addFlowTestnetToMetaMask()
      }
      console.error('Failed to switch to Flow Testnet:', error)
      return false
    }
  }
  return false
}

declare global {
  interface Window {
    ethereum?: any
  }
}