import { createConfig, http } from 'wagmi'
import { metaMask, injected, walletConnect } from 'wagmi/connectors'

// Etherlink Testnet configuration
const etherlinkTestnet = {
  id: 128123,
  name: 'Etherlink Testnet',
  nativeCurrency: {
    decimals: 18,
    name: 'Tez',
    symbol: 'XTZ',
  },
  rpcUrls: {
    default: {
      http: ['https://node.ghostnet.etherlink.com'],
    },
    public: {
      http: ['https://node.ghostnet.etherlink.com'],
    },
  },
  blockExplorers: {
    default: {
      name: 'Etherlink Testnet Explorer',
      url: 'https://testnet.explorer.etherlink.com',
    },
  },
  testnet: true,
} as const

// Define the chains array
const chains = [etherlinkTestnet] as const;

export const config = createConfig({
  chains,
  connectors: [
    metaMask({
      dappMetadata: {
        name: 'Etherlink Prize Savings',
        url: 'https://etherlink-prize-savings.vercel.app',
      },
    }),
    injected({
      target: 'metaMask',
    }),
    walletConnect({
      projectId: import.meta.env.VITE_WALLETCONNECT_PROJECT_ID || 'demo-project-id',
      metadata: {
        name: 'Etherlink Prize Savings',
        description: 'No-Loss Lottery on Etherlink',
        url: 'https://etherlink-prize-savings.vercel.app',
        icons: ['https://etherlink-prize-savings.vercel.app/icon.png'],
      },
    }),
  ],
  transports: {
    [etherlinkTestnet.id]: http('https://node.ghostnet.etherlink.com', {
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

// Helper function to add Etherlink Testnet to MetaMask
export const addEtherlinkTestnetToMetaMask = async () => {
  if (typeof window !== 'undefined' && window.ethereum) {
    try {
      await window.ethereum.request({
        method: 'wallet_addEthereumChain',
        params: [
          {
            chainId: '0x1F4DB', // 128123 in hex
            chainName: 'Etherlink Testnet',
            nativeCurrency: {
              name: 'Tez',
              symbol: 'XTZ',
              decimals: 18,
            },
            rpcUrls: ['https://node.ghostnet.etherlink.com'],
            blockExplorerUrls: ['https://testnet.explorer.etherlink.com'],
            iconUrls: ['https://assets.coingecko.com/coins/images/976/small/Tezos-logo.png'],
          },
        ],
      })
      return true
    } catch (error) {
      console.error('Failed to add Etherlink Testnet to MetaMask:', error)
      return false
    }
  }
  return false
}

// Helper function to switch to Etherlink Testnet
export const switchToEtherlinkTestnet = async () => {
  if (typeof window !== 'undefined' && window.ethereum) {
    try {
      await window.ethereum.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: '0x1F4DB' }], // 128123 in hex
      })
      return true
    } catch (error: any) {
      // Chain not added to MetaMask
      if (error.code === 4902) {
        return await addEtherlinkTestnetToMetaMask()
      }
      console.error('Failed to switch to Etherlink Testnet:', error)
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