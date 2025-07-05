import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useReadContract, useAccount } from 'wagmi'
import { CONTRACTS, VAULT_ABI, FLOW_VRF_YIELD_STRATEGY_ABI } from '@/lib/contracts'
import { formatTokenAmount, formatAddress } from '@/lib/utils'
import { TrendingUp, Trophy, Clock, Users } from 'lucide-react'
import { useEffect, useState } from 'react'

export function Dashboard() {
  const { address } = useAccount()
  const [timeLeft, setTimeLeft] = useState({
    days: 7,
    hours: 0,
    minutes: 0,
    seconds: 0
  })

  // Read Total Value Locked from Vault contract
  const { data: totalAssets, refetch: refetchTotalAssets } = useReadContract({
    address: CONTRACTS.VAULT,
    abi: VAULT_ABI,
    functionName: 'totalAssets',
  })

  // Read Current Prize Pool from FlowVrfYieldStrategy contract
  const { data: prizePool, refetch: refetchPrizePool } = useReadContract({
    address: CONTRACTS.FLOW_VRF_YIELD_STRATEGY,
    abi: FLOW_VRF_YIELD_STRATEGY_ABI,
    functionName: 'getBalance',
  })

  // Read Previous Winner from FlowVrfYieldStrategy contract
  const { data: lastWinner, refetch: refetchLastWinner } = useReadContract({
    address: CONTRACTS.FLOW_VRF_YIELD_STRATEGY,
    abi: FLOW_VRF_YIELD_STRATEGY_ABI,
    functionName: 'lastWinner',
  })

  // Read total deposited amount from strategy
  const { data: totalDeposited } = useReadContract({
    address: CONTRACTS.FLOW_VRF_YIELD_STRATEGY,
    abi: FLOW_VRF_YIELD_STRATEGY_ABI,
    functionName: 'totalDeposited',
  })

  // Check if strategy is paused
  const { data: isPaused } = useReadContract({
    address: CONTRACTS.FLOW_VRF_YIELD_STRATEGY,
    abi: FLOW_VRF_YIELD_STRATEGY_ABI,
    functionName: 'paused',
  })

  // Countdown timer effect - Set to next Friday 8 PM UTC
  useEffect(() => {
    const getNextDrawTime = () => {
      const now = new Date()
      const nextFriday = new Date(now)

      // Get next Friday
      const daysUntilFriday = (5 - now.getDay() + 7) % 7
      if (daysUntilFriday === 0 && now.getHours() >= 20) {
        // If it's Friday after 8 PM, get next Friday
        nextFriday.setDate(now.getDate() + 7)
      } else {
        nextFriday.setDate(now.getDate() + daysUntilFriday)
      }
      
      // Set to 8 PM UTC
      nextFriday.setHours(20, 0, 0, 0)
      return nextFriday
    }

    const targetDate = getNextDrawTime()

    const timer = setInterval(() => {
      const now = new Date().getTime()
      const distance = targetDate.getTime() - now

      if (distance > 0) {
        setTimeLeft({
          days: Math.floor(distance / (1000 * 60 * 60 * 24)),
          hours: Math.floor((distance % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60)),
          minutes: Math.floor((distance % (1000 * 60 * 60)) / (1000 * 60)),
          seconds: Math.floor((distance % (1000 * 60)) / 1000)
        })
      } else {
        // Reset to next week's draw
        const newTarget = getNextDrawTime()
        setTimeLeft({
          days: Math.floor((newTarget.getTime() - now) / (1000 * 60 * 60 * 24)),
          hours: Math.floor(((newTarget.getTime() - now) % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60)),
          minutes: Math.floor(((newTarget.getTime() - now) % (1000 * 60 * 60)) / (1000 * 60)),
          seconds: Math.floor(((newTarget.getTime() - now) % (1000 * 60)) / 1000)
        })
      }
    }, 1000)

    return () => clearInterval(timer)
  }, [])

  // Auto-refresh data every 30 seconds
  useEffect(() => {
    const interval = setInterval(() => {
      refetchTotalAssets()
      refetchPrizePool()
      refetchLastWinner()
    }, 30000)

    return () => clearInterval(interval)
  }, [refetchTotalAssets, refetchPrizePool, refetchLastWinner])

  const stats = [
    {
      title: 'Total Value Locked',
      value: totalAssets ? `$${formatTokenAmount(totalAssets, 6)}` : '$0.00',
      icon: TrendingUp,
      color: 'text-green-600',
      bgColor: 'bg-green-50',
      description: 'Total USDC deposited in the vault',
      status: isPaused ? 'Paused' : 'Active'
    },
    {
      title: 'Current Prize Pool',
      value: prizePool ? `$${formatTokenAmount(prizePool, 6)}` : '$0.00',
      icon: Trophy,
      color: 'text-yellow-600',
      bgColor: 'bg-yellow-50',
      description: 'Yield accumulated for the next draw',
      growth: totalDeposited && prizePool ?
        `+$${formatTokenAmount(prizePool, 6)} this period` : undefined
    },
    {
      title: 'Next Draw In',
      value: `${timeLeft.days}d ${timeLeft.hours}h ${timeLeft.minutes}m`,
      icon: Clock,
      color: 'text-blue-600',
      bgColor: 'bg-blue-50',
      description: 'Every Friday at 8 PM UTC',
      subtitle: timeLeft.days === 0 && timeLeft.hours < 1 ?
        `${timeLeft.minutes}m ${timeLeft.seconds}s` : undefined
    },
    {
      title: 'Previous Winner',
      value: lastWinner && lastWinner !== '0x0000000000000000000000000000000000000000'
        ? formatAddress(lastWinner as string)
        : 'No winner yet',
      icon: Users,
      color: 'text-purple-600',
      bgColor: 'bg-purple-50',
      description: 'Address of the last lottery winner',
      link: lastWinner && lastWinner !== '0x0000000000000000000000000000000000000000'
        ? `https://evm-testnet.flowscan.io/address/${lastWinner}` : undefined
    }
  ]

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
      {stats.map((stat, index) => (
        <Card key={index} className="border border-gray-200 shadow-sm hover:shadow-md transition-shadow duration-200">
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium text-gray-600">
              {stat.title}
            </CardTitle>
            <div className={`p-2 rounded-lg ${stat.bgColor}`}>
              <stat.icon className={`h-5 w-5 ${stat.color}`} />
            </div>
          </CardHeader>
          <CardContent>
            <div className="space-y-1">
              <div className={`text-2xl font-bold ${stat.color}`}>
                {stat.value}
              </div>
              {stat.subtitle && (
                <div className="text-lg font-semibold text-gray-600">
                  {stat.subtitle}
                </div>
              )}
              {stat.growth && (
                <div className="text-sm font-medium text-green-600">
                  {stat.growth}
                </div>
              )}
              {stat.status && (
                <div className={`text-sm font-medium ${stat.status === 'Active' ? 'text-green-600' : 'text-red-600'}`}>
                  Status: {stat.status}
                </div>
              )}
              <p className="text-xs text-gray-500">
                {stat.description}
              </p>
              {stat.link && (
                <a
                  href={stat.link}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-xs text-blue-500 hover:text-blue-700 underline"
                >
                  View on FlowScan
                </a>
              )}
            </div>
          </CardContent>
        </Card>
      ))}
    </div>
  )
}