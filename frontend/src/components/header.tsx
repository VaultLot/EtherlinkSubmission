import { Button } from '@/components/ui/button'
import { useAccount, useConnect, useDisconnect, useBalance, useChainId, useSwitchChain } from 'wagmi'
import { formatAddress, formatTokenAmount } from '@/lib/utils'
import { Wallet, LogOut, AlertTriangle, ExternalLink, Shield, Users } from 'lucide-react'
import { flowTestnet } from 'wagmi/chains'
import { switchToFlowTestnet } from '@/lib/wagmi'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { useEffect, useState } from 'react'
import * as fcl from "@onflow/fcl"
import "@/lib/fcl-config"

export function Header() {
  const { address, isConnected, connector } = useAccount()
  const { connectors, connect, isPending } = useConnect()
  const { disconnect } = useDisconnect()
  const chainId = useChainId()
  const { switchChain } = useSwitchChain()

  const [fclUser, setFclUser] = useState<any>({ loggedIn: null })

  const { data: balance } = useBalance({
    address,
    chainId: flowTestnet.id,
  })

  // This effect correctly subscribes to FCL user state for UI updates.
  useEffect(() => {
    const unsubscribe = fcl.currentUser.subscribe(setFclUser)
    return () => unsubscribe()
  }, [])

  // FIX: This new effect reacts to changes in the fclUser state.
  // It will run the COA setup logic only when a user successfully logs in via FCL.
  useEffect(() => {
    const setupCOA = async () => {
      // Check if the fclUser object shows a logged-in user with a Flow address
      if (fclUser.loggedIn && fclUser.addr) {
        // We also check isConnected from wagmi to ensure this runs
        // as a result of the wagmi connection flow completing.
        if (isConnected && connector?.id === 'fcl') {
          console.log('FCL user is logged in, setting up COA for:', fclUser.addr)
          try {
            const { ensureCOAExists } = await import('@/lib/utils/coa')
            const coaAddress = await ensureCOAExists(fclUser.addr)
            if (coaAddress) {
              console.log('COA ready:', coaAddress)
            } else {
              console.warn('Failed to set up COA')
            }
          } catch (error) {
            console.error('Error setting up COA:', error)
          }
        }
      }
    }
    setupCOA()
  }, [fclUser, isConnected, connector]) // Dependencies ensure this runs at the right time.

  const isWrongNetwork = isConnected && chainId !== flowTestnet.id

  const isFCLConnected = connector?.name === 'Flow FCL' || connector?.id === 'fcl'

  const fclConnector = connectors.find(c => c.name === 'Flow FCL' || c.id === 'fcl')
  const metaMaskConnector = connectors.find(c => c.id === 'metaMask')

  // The connection handlers are simple triggers. The logic is now in the useEffect.
  const handleConnectFCL = () => {
    if (fclConnector) {
      connect({ connector: fclConnector })
    }
  }

  const handleConnectMetaMask = () => {
    if (metaMaskConnector) {
      connect({ connector: metaMaskConnector })
    }
  }

  const handleSwitchNetwork = async () => {
    try {
      if (switchChain) {
        switchChain({ chainId: flowTestnet.id })
      } else {
        await switchToFlowTestnet()
      }
    } catch (error) {
      console.error('Failed to switch network:', error)
    }
  }

  const getNetworkName = (chainId: number) => {
    switch (chainId) {
      case 1: return 'Ethereum Mainnet'
      case 11155111: return 'Sepolia Testnet'
      case 137: return 'Polygon'
      case 545: return 'Flow Testnet'
      default: return `Chain ${chainId}`
    }
  }

  const getConnectorDisplayName = () => {
    if (isFCLConnected) {
      return 'Flow FCL'
    }
    return connector?.name || 'Unknown'
  }

  return (
    <>
      <header className="border-b bg-white sticky top-0 z-50 shadow-sm">
        <div className="container mx-auto px-4 py-4 flex items-center justify-between">
          <div className="flex items-center space-x-3">
            <div className="w-10 h-10 bg-gradient-to-r from-green-500 to-blue-500 rounded-lg flex items-center justify-center">
              <Wallet className="w-6 h-6 text-white" />
            </div>
            <div>
              <h1 className="text-2xl font-bold text-gray-900">
                Flow Prize Savings
              </h1>
              <div className="flex items-center space-x-2 text-sm text-gray-500">
                <span>No-Loss Lottery • Flow Testnet</span>
                {isFCLConnected && fclUser.loggedIn && (
                  <div className="flex items-center space-x-1 text-blue-600">
                    <Shield className="w-3 h-3" />
                    <span>FCL Connected</span>
                  </div>
                )}
              </div>
            </div>
          </div>

          <div className="flex items-center space-x-4">
            {isConnected && address ? (
              <div className="flex items-center space-x-4">
                {!isWrongNetwork && (
                  <div className="text-right">
                    <div className="flex items-center space-x-2">
                      <div className="text-sm font-medium text-gray-900">
                        {formatAddress(address)}
                      </div>
                      {isFCLConnected && (
                        <div className="flex items-center space-x-1 text-blue-600">
                          <Shield className="w-4 h-4" />
                          <span className="text-xs">FCL</span>
                        </div>
                      )}
                    </div>
                    <div className="text-xs text-gray-500">
                      {balance ? `${formatTokenAmount(balance.value, balance.decimals, 4)} FLOW` : '0 FLOW'}
                      {' • '}{getConnectorDisplayName()}
                    </div>
                  </div>
                )}
                
                {isWrongNetwork ? (
                  <Button
                    onClick={handleSwitchNetwork}
                    variant="destructive"
                    size="sm"
                    className="h-10"
                  >
                    <AlertTriangle className="w-4 h-4 mr-2" />
                    Switch to Flow Testnet
                  </Button>
                ) : (
                  <div className="flex items-center space-x-2">
                    <a
                      href={`https://evm-testnet.flowscan.io/address/${address}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-xs text-blue-500 hover:text-blue-700 flex items-center"
                    >
                      <ExternalLink className="w-3 h-3 mr-1" />
                      View on FlowScan
                    </a>
                  </div>
                )}
                
                <Button
                  onClick={() => disconnect()}
                  variant="outline"
                  size="sm"
                  className="h-10 border-gray-300 hover:border-gray-400"
                >
                  <LogOut className="w-4 h-4 mr-2" />
                  Disconnect
                </Button>
              </div>
            ) : (
              <div className="flex items-center space-x-2">
                <Button
                  onClick={handleConnectFCL}
                  disabled={isPending}
                  className="h-10 bg-gradient-to-r from-blue-500 to-purple-500 hover:from-blue-600 hover:to-purple-600 text-white"
                >
                  <Shield className="w-4 h-4 mr-2" />
                  {isPending && fclConnector?.state === 'connecting' ? 'Connecting...' : 'Connect with Flow'}
                </Button>
                
                <Button
                  onClick={handleConnectMetaMask}
                  disabled={isPending}
                  variant="outline"
                  size="sm"
                  className="h-10 border-gray-300 hover:border-gray-400"
                >
                  <Wallet className="w-4 h-4 mr-2" />
                  {isPending && metaMaskConnector?.state === 'connecting' ? 'Connecting...' : 'Attach EVM'}
                </Button>
              </div>
            )}
          </div>
        </div>
      </header>

      {isWrongNetwork && (
        <Alert className="rounded-none border-l-0 border-r-0 border-yellow-200 bg-yellow-50">
          <AlertTriangle className="h-4 w-4 text-yellow-600" />
          <AlertDescription className="text-yellow-800">
            <div className="flex items-center justify-between">
              <span>
                You're connected to <strong>{getNetworkName(chainId)}</strong>. 
                Please switch to <strong>Flow Testnet</strong> to use this app.
              </span>
              <Button
                onClick={handleSwitchNetwork}
                size="sm"
                variant="outline"
                className="ml-4 border-yellow-300 text-yellow-700 hover:bg-yellow-100"
              >
                Switch Network
              </Button>
            </div>
          </AlertDescription>
        </Alert>
      )}

      {!isFCLConnected && !isConnected && (
        <div className="bg-blue-50 border-b border-blue-200">
          <div className="container mx-auto px-4 py-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center space-x-3">
                <Users className="w-5 h-5 text-blue-600" />
                <div>
                  <p className="text-sm font-medium text-blue-800">
                    Enhanced Flow Experience Available
                  </p>
                  <p className="text-xs text-blue-600">
                    Connect with Flow FCL for seamless Flow ecosystem integration and EVM compatibility
                  </p>
                </div>
              </div>
              <Button
                onClick={handleConnectFCL}
                size="sm"
                className="bg-blue-600 hover:bg-blue-700 text-white"
              >
                <Shield className="w-4 h-4 mr-2" />
                Connect with Flow
              </Button>
            </div>
          </div>
        </div>
      )}

      {isFCLConnected && isConnected && !isWrongNetwork && fclUser.loggedIn && (
        <div className="bg-green-50 border-b border-green-200">
          <div className="container mx-auto px-4 py-2">
            <div className="flex items-center justify-center space-x-2">
              <Shield className="w-4 h-4 text-green-600" />
              <span className="text-sm font-medium text-green-800">
                Connected with Flow FCL • Full Flow Ecosystem Access Enabled
              </span>
            </div>
          </div>
        </div>
      )}
    </>
  )
}