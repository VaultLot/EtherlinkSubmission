import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { useAccount, useReadContract } from 'wagmi'
import { CONTRACTS, LOTTERY_EXTENSION_ABI } from '@/lib/contracts'
import { formatTokenAmount, formatAddress } from '@/lib/utils'
import { Trophy, Clock, ExternalLink, TrendingUp } from 'lucide-react'
import { useState, useEffect } from 'react'

interface LotteryEvent {
  id: string
  winner: string
  amount: string
  blockNumber: number
  timestamp: number
  txHash: string
}

export function LotteryHistory() {
  const { address } = useAccount()
  const [recentWins, setRecentWins] = useState<LotteryEvent[]>([])

  // Read last winner
  const { data: lastWinner } = useReadContract({
    address: CONTRACTS.LOTTERY_EXTENSION,
    abi: LOTTERY_EXTENSION_ABI,
    functionName: 'lastWinner',
  })

  // Read last payout
  const { data: lastPayout } = useReadContract({
    address: CONTRACTS.LOTTERY_EXTENSION,
    abi: LOTTERY_EXTENSION_ABI,
    functionName: 'lastPayout',
  })

  // Read current prize pool
  const { data: lotteryInfo } = useReadContract({
    address: CONTRACTS.LOTTERY_EXTENSION,
    abi: LOTTERY_EXTENSION_ABI,
    functionName: 'getLotteryInfo',
  })

  const prizePool = lotteryInfo ? lotteryInfo[0] : BigInt(0) // prizePool

  // Helper function to check if BigInt is greater than zero
  const isPositiveBigInt = (value: bigint | undefined): boolean => {
    return value !== undefined && value > 0n
  }

  // Mock data for demonstration - in a real app, you'd fetch from events
  useEffect(() => {
    const mockWins: LotteryEvent[] = []
    
    // If we have a last winner and payout, create a mock entry
    if (lastWinner && 
        lastWinner !== '0x0000000000000000000000000000000000000000' && 
        lastPayout && 
        lastPayout > 0n) {
      mockWins.push({
        id: '1',
        winner: lastWinner as string,
        amount: formatTokenAmount(lastPayout, 6),
        blockNumber: 1234567,
        timestamp: Date.now() - 7 * 24 * 60 * 60 * 1000, // 1 week ago
        txHash: '0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890'
      })
    }

    // Add some additional mock data for demonstration
    if (mockWins.length > 0) {
      mockWins.push(
        {
          id: '2',
          winner: '0x2234567890123456789012345678901234567891',
          amount: '234.50',
          blockNumber: 1234000,
          timestamp: Date.now() - 14 * 24 * 60 * 60 * 1000, // 2 weeks ago
          txHash: '0xbcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567891'
        },
        {
          id: '3',
          winner: '0x3234567890123456789012345678901234567892',
          amount: '189.25',
          blockNumber: 1233500,
          timestamp: Date.now() - 21 * 24 * 60 * 60 * 1000, // 3 weeks ago
          txHash: '0xcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567892'
        }
      )
    }

    setRecentWins(mockWins)
  }, [lastWinner, lastPayout])

  const formatTimestamp = (timestamp: number) => {
    const date = new Date(timestamp)
    const now = new Date()
    const diffInMs = now.getTime() - date.getTime()
    const diffInDays = Math.floor(diffInMs / (1000 * 60 * 60 * 24))

    if (diffInDays === 0) return 'Today'
    if (diffInDays === 1) return 'Yesterday'
    if (diffInDays < 7) return `${diffInDays} days ago`
    if (diffInDays < 30) return `${Math.floor(diffInDays / 7)} weeks ago`
    return date.toLocaleDateString()
  }

  const isUserWinner = (winner: string) => {
    return address && winner.toLowerCase() === address.toLowerCase()
  }

  return (
    <Card className="border border-gray-200 shadow-sm">
      <CardHeader>
        <CardTitle className="flex items-center space-x-2">
          <Trophy className="w-5 h-5 text-yellow-600" />
          <span>Recent Winners</span>
        </CardTitle>
      </CardHeader>
      <CardContent>
        {recentWins.length === 0 ? (
          <div className="text-center py-8">
            <div className="text-gray-400 mb-4">
              <Clock className="w-16 h-16 mx-auto" />
            </div>
            <h3 className="text-lg font-semibold text-gray-700 mb-2">No Winners Yet</h3>
            <p className="text-gray-500 text-sm">
              Be the first to win the lottery! The next draw is coming soon.
            </p>
            {isPositiveBigInt(prizePool) && (
              <div className="mt-4 p-3 bg-yellow-50 rounded-lg border border-yellow-200">
                <div className="text-sm font-medium text-yellow-800">
                  Current Prize Pool: ${formatTokenAmount(prizePool!, 6)} USDC
                </div>
              </div>
            )}
          </div>
        ) : (
          <div className="space-y-4">
            {recentWins.map((win, index) => (
              <div
                key={win.id}
                className={`flex items-center justify-between p-4 rounded-lg border transition-colors ${
                  isUserWinner(win.winner)
                    ? 'bg-green-50 border-green-200'
                    : 'bg-gray-50 border-gray-200 hover:bg-gray-100'
                }`}
              >
                <div className="flex items-center space-x-4">
                  <div className={`p-2 rounded-full ${
                    isUserWinner(win.winner) ? 'bg-green-200' : 'bg-yellow-200'
                  }`}>
                    <Trophy className={`w-5 h-5 ${
                      isUserWinner(win.winner) ? 'text-green-600' : 'text-yellow-600'
                    }`} />
                  </div>
                  <div>
                    <div className="flex items-center space-x-2">
                      <span className="font-semibold text-gray-900">
                        {isUserWinner(win.winner) ? 'You Won!' : formatAddress(win.winner)}
                      </span>
                      {index === 0 && (
                        <Badge variant="secondary" className="text-xs">
                          Latest
                        </Badge>
                      )}
                      {isUserWinner(win.winner) && (
                        <Badge variant="default" className="text-xs bg-green-600">
                          Your Win
                        </Badge>
                      )}
                    </div>
                    <div className="text-sm text-gray-500">
                      {formatTimestamp(win.timestamp)} • Block #{win.blockNumber.toLocaleString()}
                    </div>
                  </div>
                </div>
                <div className="text-right">
                  <div className="text-lg font-bold text-green-600">
                    ${win.amount} USDC
                  </div>
                  <a
                    href={`https://testnet.explorer.etherlink.com/tx/${win.txHash}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-xs text-blue-500 hover:text-blue-700 flex items-center justify-end"
                  >
                    View TX <ExternalLink className="w-3 h-3 ml-1" />
                  </a>
                </div>
              </div>
            ))}

            {isPositiveBigInt(prizePool) && (
              <div className="mt-6 p-4 bg-gradient-to-r from-blue-50 to-purple-50 rounded-lg border border-blue-200">
                <div className="flex items-center justify-between">
                  <div>
                    <div className="text-sm font-medium text-gray-800">Next Prize Pool</div>
                    <div className="text-lg font-bold text-blue-600">
                      ${formatTokenAmount(prizePool!, 6)} USDC
                    </div>
                  </div>
                  <div className="text-right">
                    <div className="text-sm text-gray-600">Next Draw</div>
                    <div className="text-sm font-medium text-purple-600">Friday 8 PM UTC</div>
                  </div>
                </div>
                <div className="mt-2 flex items-center text-xs text-gray-600">
                  <TrendingUp className="w-3 h-3 mr-1" />
                  Growing from yield earned on deposits
                </div>
              </div>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  )
}