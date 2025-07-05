import { useAccount } from 'wagmi'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Info } from 'lucide-react'

export function WalletDebugInfo() {
  const { address, connector, isConnected, chainId } = useAccount()

  if (!isConnected) return null

  return (
    <Card className="border border-blue-200 bg-blue-50">
      <CardHeader>
        <CardTitle className="flex items-center space-x-2 text-sm">
          <Info className="w-4 h-4 text-blue-600" />
          <span>Wallet Debug Info</span>
        </CardTitle>
      </CardHeader>
      <CardContent className="text-xs space-y-2">
        <div><strong>Address:</strong> {address}</div>
        <div><strong>Connector ID:</strong> {connector?.id}</div>
        <div><strong>Connector Name:</strong> {connector?.name}</div>
        <div><strong>Connector Type:</strong> {connector?.type}</div>
        <div><strong>Chain ID:</strong> {chainId}</div>
        <div><strong>Is Connected:</strong> {isConnected ? 'Yes' : 'No'}</div>
      </CardContent>
    </Card>
  )
}