import { useState, useEffect } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { useAccount, useReadContract, useWriteContract } from 'wagmi'
import { CONTRACTS, VAULT_ABI, MOCK_USDC_ABI } from '@/lib/contracts'
import { formatTokenAmount, parseTokenAmount } from '@/lib/utils'
import { toast } from 'sonner'
import { Loader2, DollarSign, Coins, Shield, Users, Wallet } from 'lucide-react'

export function DepositWithdraw() {
  const { address, connector } = useAccount()
  const [depositAmount, setDepositAmount] = useState('')
  const [withdrawAmount, setWithdrawAmount] = useState('')
  const [isApproving, setIsApproving] = useState(false)
  const [isDepositing, setIsDepositing] = useState(false)
  const [isWithdrawing, setIsWithdrawing] = useState(false)
  const [isFauceting, setIsFauceting] = useState(false)

  const { writeContract } = useWriteContract({
    mutation: {
      onSuccess: (hash) => {
        console.log('Transaction successful with hash:', hash)
      },
      onError: (error) => {
        console.error('Transaction failed:', error)
      }
    }
  })

  // Debug logging
  useEffect(() => {
    if (connector) {
      console.log('Current connector:', {
        id: connector.id,
        name: connector.name,
        type: connector.type
      })
    }
  }, [connector])

  // Read user's USDC balance
  const { data: usdcBalance, refetch: refetchUsdcBalance } = useReadContract({
    address: CONTRACTS.MOCK_USDC,
    abi: MOCK_USDC_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
  })

  // Read user's vault shares balance
  const { data: sharesBalance, refetch: refetchSharesBalance } = useReadContract({
    address: CONTRACTS.VAULT,
    abi: VAULT_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
  })

  // Read user's USDC allowance for the vault
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: CONTRACTS.MOCK_USDC,
    abi: MOCK_USDC_ABI,
    functionName: 'allowance',
    args: address ? [address, CONTRACTS.VAULT] : undefined,
  })

  // Convert shares to assets to get actual deposit value
  const { data: userAssets } = useReadContract({
    address: CONTRACTS.VAULT,
    abi: VAULT_ABI,
    functionName: 'convertToAssets',
    args: sharesBalance ? [sharesBalance] : undefined,
  })

  const handleApprove = async () => {
    if (!depositAmount || !address || !connector) return

    try {
      setIsApproving(true)
      
      const maxAmount = parseTokenAmount("1000000", 6)

      console.log('=== APPROVAL TRANSACTION ===')
      console.log('Using address:', address)
      console.log('Using connector:', connector.name, connector.id)
      console.log('Contract:', CONTRACTS.MOCK_USDC)
      console.log('Amount:', maxAmount.toString())

      await writeContract({
        address: CONTRACTS.MOCK_USDC,
        abi: MOCK_USDC_ABI,
        functionName: 'approve',
        args: [CONTRACTS.VAULT, maxAmount],
      })

      toast.success(`Approval transaction submitted from ${address.slice(0, 6)}...${address.slice(-4)}`)
      
      setTimeout(() => {
        refetchAllowance()
        setIsApproving(false)
      }, 3000)
    } catch (error: any) {
      console.error('Approval failed:', error)
      toast.error(error?.message || 'Approval failed')
      setIsApproving(false)
    }
  }

  const handleDeposit = async () => {
    if (!depositAmount || !address || !connector) return

    try {
      setIsDepositing(true)
      const amount = parseTokenAmount(depositAmount, 6)

      console.log('=== DEPOSIT TRANSACTION ===')
      console.log('Using address:', address)
      console.log('Using connector:', connector.name, connector.id)
      console.log('Contract:', CONTRACTS.VAULT)
      console.log('Amount:', amount.toString())

      await writeContract({
        address: CONTRACTS.VAULT,
        abi: VAULT_ABI,
        functionName: 'deposit',
        args: [amount, address],
      })

      toast.success(`Deposit transaction submitted from ${address.slice(0, 6)}...${address.slice(-4)}`)
      
      setTimeout(() => {
        refetchUsdcBalance()
        refetchSharesBalance()
        refetchAllowance()
        setDepositAmount('')
        setIsDepositing(false)
      }, 3000)
    } catch (error: any) {
      console.error('Deposit failed:', error)
      toast.error(error?.message || 'Deposit failed')
      setIsDepositing(false)
    }
  }

  const handleWithdraw = async () => {
    if (!withdrawAmount || !address || !connector) return

    try {
      setIsWithdrawing(true)
      const amount = parseTokenAmount(withdrawAmount, 18)

      console.log('=== WITHDRAW TRANSACTION ===')
      console.log('Using address:', address)
      console.log('Using connector:', connector.name, connector.id)
      console.log('Contract:', CONTRACTS.VAULT)
      console.log('Amount:', amount.toString())

      await writeContract({
        address: CONTRACTS.VAULT,
        abi: VAULT_ABI,
        functionName: 'redeem',
        args: [amount, address, address],
      })

      toast.success(`Withdrawal transaction submitted from ${address.slice(0, 6)}...${address.slice(-4)}`)
      
      setTimeout(() => {
        refetchUsdcBalance()
        refetchSharesBalance()
        setWithdrawAmount('')
        setIsWithdrawing(false)
      }, 3000)
    } catch (error: any) {
      console.error('Withdrawal failed:', error)
      toast.error(error?.message || 'Withdrawal failed')
      setIsWithdrawing(false)
    }
  }

  const handleFaucet = async () => {
    if (!address || !connector) return

    try {
      setIsFauceting(true)
      const amount = parseTokenAmount('1000', 6)

      console.log('=== FAUCET TRANSACTION ===')
      console.log('Using address:', address)
      console.log('Using connector:', connector.name, connector.id)
      console.log('Contract:', CONTRACTS.MOCK_USDC)
      console.log('Amount:', amount.toString())
      console.log('Expected recipient:', address)

      await writeContract({
        address: CONTRACTS.MOCK_USDC,
        abi: MOCK_USDC_ABI,
        functionName: 'faucet',
        args: [],
      })

      toast.success(`Faucet transaction submitted from ${address.slice(0, 6)}...${address.slice(-4)}`)
      
      setTimeout(() => {
        refetchUsdcBalance()
        setIsFauceting(false)
      }, 3000)
    } catch (error: any) {
      console.error('Faucet failed:', error)
      toast.error(error?.message || 'Faucet failed')
      setIsFauceting(false)
    }
  }

  const setMaxDeposit = () => {
    if (usdcBalance) {
      setDepositAmount(formatTokenAmount(usdcBalance, 6))
    }
  }

  const setMaxWithdraw = () => {
    if (sharesBalance) {
      setWithdrawAmount(formatTokenAmount(sharesBalance, 18))
    }
  }

  const isPositiveBigInt = (value: bigint | undefined): boolean => {
    return value !== undefined && value > 0n
  }

  if (!address) {
    return (
      <Card className="border border-gray-200 shadow-sm">
        <CardContent className="flex flex-col items-center justify-center py-12 space-y-4">
          <div className="text-center space-y-4">
            <div className="w-16 h-16 bg-gradient-to-r from-blue-500 to-purple-500 rounded-full flex items-center justify-center mx-auto">
              <Wallet className="w-8 h-8 text-white" />
            </div>
            <div>
              <h3 className="text-lg font-semibold text-gray-800 mb-2">
                Connect Your Wallet
              </h3>
              <p className="text-gray-500 text-sm">
                Connect your wallet to start saving and earning with Etherlink Prize Savings
              </p>
            </div>

            <div className="bg-blue-50 border border-blue-200 rounded-lg p-4 max-w-sm">
              <div className="flex items-center space-x-3">
                <Shield className="w-6 h-6 text-blue-600" />
                <div className="text-left">
                  <p className="text-sm font-medium text-blue-800">
                    Secure & Fast
                  </p>
                  <p className="text-xs text-blue-600">
                    Low fees on Etherlink testnet
                  </p>
                </div>
              </div>
            </div>
          </div>
        </CardContent>
      </Card>
    )
  }

  const needsApproval = depositAmount && allowance !== undefined &&
    parseTokenAmount(depositAmount, 6) > allowance

  return (
    <Card className="border border-gray-200 shadow-sm">
      <CardHeader>
        <CardTitle className="flex items-center justify-between">
          <div className="flex items-center space-x-2">
            <DollarSign className="w-5 h-5 text-green-600" />
            <span>Deposit & Withdraw</span>
          </div>
          <div className="flex items-center space-x-2 text-sm">
            <div className="flex items-center space-x-1 text-green-600">
              <Wallet className="w-4 h-4" />
              <span>Connected</span>
            </div>
          </div>
        </CardTitle>
        <div className="text-xs text-gray-500">
          Connected via: {connector?.name || 'Unknown'}
        </div>
      </CardHeader>
      <CardContent>
        <Tabs defaultValue="deposit" className="space-y-6">
          <TabsList className="grid w-full grid-cols-2">
            <TabsTrigger value="deposit" className="flex items-center space-x-2">
              <DollarSign className="w-4 h-4" />
              <span>Deposit</span>
            </TabsTrigger>
            <TabsTrigger value="withdraw" className="flex items-center space-x-2">
              <Coins className="w-4 h-4" />
              <span>Withdraw</span>
            </TabsTrigger>
          </TabsList>

          <TabsContent value="deposit" className="space-y-4">
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <Label htmlFor="deposit-amount">Amount to Deposit (USDC)</Label>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={setMaxDeposit}
                  className="h-6 px-2 text-xs"
                >
                  MAX
                </Button>
              </div>
              <Input
                id="deposit-amount"
                type="number"
                placeholder="0.00"
                value={depositAmount}
                onChange={(e) => setDepositAmount(e.target.value)}
                className="text-lg"
                min="0"
                step="0.01"
              />
              <div className="flex justify-between text-sm text-gray-500">
                <span>Your USDC Balance:</span>
                <span>{usdcBalance ? formatTokenAmount(usdcBalance, 6) : '0.00'} USDC</span>
              </div>
              {isPositiveBigInt(userAssets) && (
                <div className="flex justify-between text-sm text-gray-500">
                  <span>Your Deposited Value:</span>
                  <span>{formatTokenAmount(userAssets!, 6)} USDC</span>
                </div>
              )}
            </div>

            <Button
              onClick={handleFaucet}
              disabled={isFauceting}
              variant="outline"
              className="w-full border-gray-300 hover:border-gray-400 mb-4"
            >
              {isFauceting ? (
                <>
                  <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                  Getting Test USDC...
                </>
              ) : (
                'Get Test USDC (Faucet)'
              )}
            </Button>

            <div className="flex space-x-2">
              {needsApproval && (
                <Button
                  onClick={handleApprove}
                  disabled={!depositAmount || isApproving}
                  variant="outline"
                  className="flex-1 border-gray-300 hover:border-gray-400"
                >
                  {isApproving ? (
                    <>
                      <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                      Approving...
                    </>
                  ) : (
                    'Approve USDC'
                  )}
                </Button>
              )}
              <Button
                onClick={handleDeposit}
                disabled={!depositAmount || isDepositing || needsApproval || Number(depositAmount) <= 0}
                className={`${needsApproval ? 'flex-1' : 'w-full'} bg-green-600 hover:bg-green-700 text-white`}
              >
                {isDepositing ? (
                  <>
                    <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                    Depositing...
                  </>
                ) : (
                  'Deposit'
                )}
              </Button>
            </div>

            <div className="bg-green-50 border-green-200 border rounded-lg p-3">
              <div className="flex items-center space-x-2 text-sm text-green-700">
                <Shield className="w-4 h-4" />
                <span className="font-medium">
                  Powered by Etherlink
                </span>
              </div>
              <p className="text-xs text-green-600 mt-1">
                Your deposits earn yield automatically while you're eligible for weekly prize draws using secure smart contracts.
              </p>
            </div>
          </TabsContent>

          <TabsContent value="withdraw" className="space-y-4">
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <Label htmlFor="withdraw-amount">Amount to Withdraw (Shares)</Label>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={setMaxWithdraw}
                  className="h-6 px-2 text-xs"
                >
                  MAX
                </Button>
              </div>
              <Input
                id="withdraw-amount"
                type="number"
                placeholder="0.00"
                value={withdrawAmount}
                onChange={(e) => setWithdrawAmount(e.target.value)}
                className="text-lg"
                min="0"
                step="0.000001"
              />
              <div className="flex justify-between text-sm text-gray-500">
                <span>Your Vault Shares:</span>
                <span>{sharesBalance ? formatTokenAmount(sharesBalance, 18) : '0.00'} shares</span>
              </div>
              {withdrawAmount && userAssets != null && isPositiveBigInt(sharesBalance) && (
                <div className="flex justify-between text-sm text-green-600">
                  <span>You will receive approx:</span>
                  <span>
                    {formatTokenAmount(
                      (parseTokenAmount(withdrawAmount, 18) * userAssets!) / sharesBalance!, 
                      6
                    )} USDC
                  </span>
                </div>
              )}
            </div>

            <Button
              onClick={handleWithdraw}
              disabled={!withdrawAmount || isWithdrawing || Number(withdrawAmount) <= 0}
              className="w-full bg-red-500 hover:bg-red-600 text-white"
            >
              {isWithdrawing ? (
                <>
                  <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                  Withdrawing...
                </>
              ) : (
                'Withdraw'
              )}
            </Button>

            <div className="bg-amber-50 border border-amber-200 rounded-lg p-3">
              <div className="flex items-center space-x-2 text-sm text-amber-700">
                <Users className="w-4 h-4" />
                <span className="font-medium">No-Loss Guarantee</span>
              </div>
              <p className="text-xs text-amber-600 mt-1">
                You can withdraw your deposits at any time. Only the yield goes to prizes, never your principal amount.
              </p>
            </div>
          </TabsContent>
        </Tabs>
      </CardContent>
    </Card>
  )
}