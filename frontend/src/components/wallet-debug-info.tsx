import { useAccount } from 'wagmi'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Info } from 'lucide-react'

export function WalletDebugInfo() {
  const { address, connector, isConnected, chainId } = useAccount()

  if (!isConnected) return null

  return (
    <Card className="border border-gray-200 shadow-sm">
      <CardHeader>
        <CardTitle className="flex items-center space-x-2">
          <Info className="w-4 h-4" />
          Wallet Debug Info
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-2">
        <p className="text-sm">
          <strong>Address:</strong> {address}
        </p>
        <p className="text-sm">
          <strong>Connector ID:</strong> {connector?.id}
        </p>
        <p className="text-sm">
          <strong>Connector Name:</strong> {connector?.name}
        </p>
        <p className="text-sm">
          <strong>Connector Type:</strong> {connector?.type}
        </p>
        <p className="text-sm">
          <strong>Chain ID:</strong> {chainId}
        </p>
        <p className="text-sm">
          <strong>Is Connected:</strong> {isConnected ? 'Yes' : 'No'}
        </p>
        {chainId === 128123 && (
          <p className="text-sm text-green-600">
            ✅ Connected to Etherlink Testnet
          </p>
        )}
      </CardContent>
    </Card>
  )
}