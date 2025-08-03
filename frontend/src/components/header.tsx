import { Button } from '@/components/ui/button'
import { useAccount, useConnect, useDisconnect, useBalance, useChainId, useSwitchChain } from 'wagmi'
import { formatAddress, formatTokenAmount } from '@/lib/utils'
import { Wallet, LogOut, AlertTriangle, ExternalLink } from 'lucide-react'
import { switchToEtherlinkTestnet } from '@/lib/wagmi'
import { Alert, AlertDescription } from '@/components/ui/alert'

const ETHERLINK_TESTNET_ID = 128123

export function Header() {
  const { address, isConnected, connector } = useAccount()
  const { connectors, connect, isPending } = useConnect()
  const { disconnect } = useDisconnect()
  const chainId = useChainId()
  const { switchChain } = useSwitchChain()

  const { data: balance } = useBalance({
    address,
    chainId: ETHERLINK_TESTNET_ID,
  })

  const isWrongNetwork = isConnected && chainId !== ETHERLINK_TESTNET_ID

  const metaMaskConnector = connectors.find(c => c.id === 'metaMask')
  const walletConnectConnector = connectors.find(c => c.id === 'walletConnect')

  const handleConnectMetaMask = () => {
    if (metaMaskConnector) {
      connect({ connector: metaMaskConnector })
    }
  }

  const handleConnectWalletConnect = () => {
    if (walletConnectConnector) {
      connect({ connector: walletConnectConnector })
    }
  }

  const handleSwitchNetwork = async () => {
    try {
      if (switchChain) {
        switchChain({ chainId: ETHERLINK_TESTNET_ID })
      } else {
        await switchToEtherlinkTestnet()
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
      case 128123: return 'Etherlink Testnet'
      default: return `Chain ${chainId}`
    }
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
                Etherlink Prize Savings
              </h1>
              <div className="flex items-center space-x-2 text-sm text-gray-500">
                <span>No-Loss Lottery • Etherlink Testnet</span>
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
                    </div>
                    <div className="text-xs text-gray-500">
                      {balance ? `${formatTokenAmount(balance.value, balance.decimals, 4)} XTZ` : '0 XTZ'}
                      {' • '}{connector?.name || 'Unknown'}
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
                    Switch to Etherlink
                  </Button>
                ) : (
                  <div className="flex items-center space-x-2">
                    <a
                      href={`https://testnet.explorer.etherlink.com/address/${address}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-xs text-blue-500 hover:text-blue-700 flex items-center"
                    >
                      <ExternalLink className="w-3 h-3 mr-1" />
                      View on Explorer
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
                  onClick={handleConnectMetaMask}
                  disabled={isPending}
                  className="h-10 bg-gradient-to-r from-blue-500 to-purple-500 hover:from-blue-600 hover:to-purple-600 text-white"
                >
                  <Wallet className="w-4 h-4 mr-2" />
                  {isPending && metaMaskConnector?.state === 'connecting' ? 'Connecting...' : 'Connect MetaMask'}
                </Button>
                
                <Button
                  onClick={handleConnectWalletConnect}
                  disabled={isPending}
                  variant="outline"
                  size="sm"
                  className="h-10 border-gray-300 hover:border-gray-400"
                >
                  <Wallet className="w-4 h-4 mr-2" />
                  {isPending && walletConnectConnector?.state === 'connecting' ? 'Connecting...' : 'WalletConnect'}
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
                Please switch to <strong>Etherlink Testnet</strong> to use this app.
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
    </>
  )
}