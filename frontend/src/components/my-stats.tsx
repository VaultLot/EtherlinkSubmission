import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Progress } from '@/components/ui/progress'
import { useAccount, useReadContract } from 'wagmi'
import { CONTRACTS, VAULT_ABI, LOTTERY_EXTENSION_ABI } from '@/lib/contracts'
import { formatTokenAmount } from '@/lib/utils'
import { User, Percent, Trophy, TrendingUp } from 'lucide-react'
import { useEffect } from 'react'

export function MyStats() {
  const { address } = useAccount()

  // Read user's vault shares balance
  const { data: sharesBalance, refetch: refetchSharesBalance } = useReadContract({
    address: CONTRACTS.VAULT,
    abi: VAULT_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
  })

  // Read total supply of shares
  const { data: totalSupply } = useReadContract({
    address: CONTRACTS.VAULT,
    abi: VAULT_ABI,
    functionName: 'totalSupply',
  })

  // Read total assets in vault
  const { data: totalAssets } = useReadContract({
    address: CONTRACTS.VAULT,
    abi: VAULT_ABI,
    functionName: 'totalAssets',
  })

  // Convert shares to assets to get user's actual deposit value
  const { data: userAssets } = useReadContract({
    address: CONTRACTS.VAULT,
    abi: VAULT_ABI,
    functionName: 'convertToAssets',
    args: sharesBalance ? [sharesBalance] : undefined,
  })

  // Read user's lottery information from lottery extension
  const { data: userLotteryInfo } = useReadContract({
    address: CONTRACTS.LOTTERY_EXTENSION,
    abi: LOTTERY_EXTENSION_ABI,
    functionName: 'getUserLotteryInfo',
    args: address ? [address] : undefined,
  })

  // Read current prize pool
  const { data: lotteryInfo } = useReadContract({
    address: CONTRACTS.LOTTERY_EXTENSION,
    abi: LOTTERY_EXTENSION_ABI,
    functionName: 'getLotteryInfo',
  })

  const prizePool = lotteryInfo ? lotteryInfo[0] : BigInt(0) // prizePool

  // Parse user lottery info
  const userLotteryDeposit = userLotteryInfo ? userLotteryInfo[0] : BigInt(0) // currentDeposit
  const winProbability = userLotteryInfo ? Number(userLotteryInfo[1]) / 100 : 0 // winProbability in percentage
  const lifetimeRewards = userLotteryInfo ? userLotteryInfo[2] : BigInt(0) // lifetimeRewards
  const isLotteryActive = userLotteryInfo ? userLotteryInfo[3] : false // isActive

  // Auto-refresh every 30 seconds
  useEffect(() => {
    const interval = setInterval(() => {
      refetchSharesBalance()
    }, 30000)

    return () => clearInterval(interval)
  }, [refetchSharesBalance])

  if (!address) {
    return (
      <Card className="border border-gray-200 shadow-sm">
        <CardContent className="flex items-center justify-center py-12">
          <p className="text-gray-500">Connect your wallet to view your stats</p>
        </CardContent>
      </Card>
    )
  }

  // Calculate user's deposit amount
  const userDeposit = userAssets ? formatTokenAmount(userAssets, 6) : '0.00' // USDC has 6 decimals
  const totalValue = totalAssets ? formatTokenAmount(totalAssets, 6) : '0.00'

  // Calculate potential winnings (entire prize pool if user wins)
  const potentialWinnings = prizePool

  const hasDeposits = sharesBalance && sharesBalance > 0n

  // Fix vault shares display by multiplying by E12
  const displayShares = sharesBalance ? sharesBalance * BigInt(10 ** 12) : BigInt(0)

  return (
    <Card className="border border-gray-200 shadow-sm">
      <CardHeader>
        <CardTitle className="flex items-center space-x-2">
          <User className="w-5 h-5 text-blue-600" />
          <span>My Stats</span>
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-6">
        {!hasDeposits ? (
          <div className="text-center py-8">
            <div className="text-gray-400 mb-4">
              <Trophy className="w-16 h-16 mx-auto" />
            </div>
            <h3 className="text-lg font-semibold text-gray-700 mb-2">No Deposits Yet</h3>
            <p className="text-gray-500 text-sm">
              Make your first deposit to start earning yield and enter the lottery!
            </p>
          </div>
        ) : (
          <>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <div className="flex justify-between items-center">
                  <span className="text-sm font-medium text-gray-600">Your Deposit</span>
                  <div className="text-right">
                    <div className="text-lg font-bold text-green-600">${userDeposit}</div>
                    <div className="text-xs text-gray-500">USDC</div>
                  </div>
                </div>
              </div>

              <div className="space-y-2">
                <div className="flex justify-between items-center">
                  <span className="text-sm font-medium text-gray-600">Vault Shares</span>
                  <div className="text-right">
                    <div className="text-lg font-bold text-gray-900">
                      {displayShares ? formatTokenAmount(displayShares, 18, 4) : '0.0000'}
                    </div>
                    <div className="text-xs text-gray-500">shares</div>
                  </div>
                </div>
              </div>
            </div>

            <div className="space-y-3">
              <div className="flex justify-between items-center">
                <span className="text-sm font-medium text-gray-600">Your Winning Chance</span>
                <div className="flex items-center space-x-2">
                  <Percent className="w-4 h-4 text-purple-600" />
                  <span className="text-lg font-bold text-purple-600">
                    {winProbability.toFixed(4)}%
                  </span>
                </div>
              </div>
              <Progress 
                value={Math.min(winProbability, 100)} 
                className="h-2"
              />
              <div className="text-xs text-gray-500">
                Based on your share of the total lottery pool ({userLotteryDeposit ? formatTokenAmount(userLotteryDeposit, 6) : '0.00'} USDC deposited)
              </div>
            </div>

            {prizePool && prizePool > 0n && (
              <div className="space-y-2">
                <div className="flex justify-between items-center">
                  <span className="text-sm font-medium text-gray-600">If You Win Next Draw</span>
                  <div className="flex items-center space-x-2">
                    <Trophy className="w-4 h-4 text-yellow-600" />
                    <span className="text-lg font-bold text-yellow-600">
                      ${formatTokenAmount(potentialWinnings, 6)} USDC
                    </span>
                  </div>
                </div>
                <div className="text-xs text-gray-500">
                  Current prize pool: ${formatTokenAmount(prizePool, 6)} USDC
                </div>
              </div>
            )}

            {lifetimeRewards > 0n && (
              <div className="space-y-2">
                <div className="flex justify-between items-center">
                  <span className="text-sm font-medium text-gray-600">Lifetime Rewards</span>
                  <div className="flex items-center space-x-2">
                    <TrendingUp className="w-4 h-4 text-green-600" />
                    <span className="text-lg font-bold text-green-600">
                      +${formatTokenAmount(lifetimeRewards, 6)} USDC
                    </span>
                  </div>
                </div>
                <div className="text-xs text-gray-500">
                  Total prizes won from lottery draws
                </div>
              </div>
            )}

            <div className="bg-gradient-to-r from-blue-50 to-purple-50 rounded-lg p-4 border border-blue-100">
              <div className="text-sm font-medium text-gray-800 mb-2">
                💡 How Prize Draws Work
              </div>
              <div className="text-xs text-gray-600 space-y-1">
                <p>• Higher deposits = better winning chances</p>
                <p>• Draws happen every Friday at 8 PM UTC</p>
                <p>• Winners get the entire prize pool</p>
                <p>• Your deposits are always safe - withdraw anytime</p>
                <p>• Only yield goes to prizes, never your principal</p>
              </div>
            </div>

            {isLotteryActive && (
              <div className="bg-green-50 border border-green-200 rounded-lg p-3">
                <div className="text-sm font-medium text-green-800">
                  🎲 You're entered in the next lottery draw!
                </div>
                <div className="text-xs text-green-600 mt-1">
                  Lottery deposit: ${userLotteryDeposit ? formatTokenAmount(userLotteryDeposit, 6) : '0.00'} USDC
                </div>
              </div>
            )}
          </>
        )}
      </CardContent>
    </Card>
  )
}