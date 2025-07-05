import React from 'react';
import { Header } from '@/components/header'
import { Dashboard } from '@/components/dashboard'
import { DepositWithdraw } from '@/components/deposit-withdraw'
import { MyStats } from '@/components/my-stats'
import { LotteryHistory } from '@/components/lottery-history'
import { useAccount, useConnect } from 'wagmi'
import { Shield, Wallet } from 'lucide-react'
import { useFCLStatus } from '@/hooks/useFCL'
import Providers from '@/components/providers'

function AppContent() {
  const { isConnected, connector } = useAccount()
  const { connectors } = useConnect()
  const { isFCLConnected, hasFullFCLAccess, fclAddress } = useFCLStatus()

  const fclConnector = connectors.find(c => c.name === 'FCL' || c.id === 'fcl')

  return (
    <div className="min-h-screen bg-gray-50">
      <Header />

      <main className="container mx-auto px-4 py-8">
        {/* Hero Section */}
        <div className="text-center mb-12">
          <div className="max-w-3xl mx-auto">
            <h1 className="text-4xl font-bold text-gray-900 mb-4">
              Flow Prize Savings
            </h1>
            <p className="text-xl text-gray-600 mb-6">
              No-Loss Lottery powered by Flow Native VRF
            </p>
            <p className="text-gray-500">
              Deposit USDC, earn yield, and win weekly prizes. Your deposits are always safe to withdraw.
            </p>
            
            {/* Connection Status Indicator */}
            {hasFullFCLAccess && (
              <div className="mt-4 inline-flex items-center px-4 py-2 bg-blue-50 border border-blue-200 rounded-full">
                <div className="w-2 h-2 bg-blue-500 rounded-full mr-2"></div>
                <Shield className="w-4 h-4 text-blue-600 mr-2" />
                <span className="text-sm text-blue-700">
                  Connected with Flow FCL • Full Ecosystem Access
                </span>
                {fclAddress && (
                  <span className="text-xs text-blue-600 ml-2">
                    ({fclAddress.slice(0, 8)}...)
                  </span>
                )}
              </div>
            )}
            
            {isConnected && !isFCLConnected && (
              <div className="mt-4 inline-flex items-center px-4 py-2 bg-gray-50 border border-gray-200 rounded-full">
                <div className="w-2 h-2 bg-gray-500 rounded-full mr-2"></div>
                <Wallet className="w-4 h-4 text-gray-600 mr-2" />
                <span className="text-sm text-gray-700">
                  Connected with {connector?.name || 'EVM Wallet'}
                </span>
              </div>
            )}
          </div>
        </div>

        {/* Main Dashboard */}
        <Dashboard />

        {/* Main Content Grid */}
        <div className="grid lg:grid-cols-3 gap-8">
          {/* Left Column - Deposit/Withdraw */}
          <div className="lg:col-span-1">
            <DepositWithdraw />
          </div>

          {/* Middle Column - My Stats */}
          <div className="lg:col-span-1">
            <MyStats />
          </div>

          {/* Right Column - Lottery History */}
          <div className="lg:col-span-1">
            <LotteryHistory />
          </div>
        </div>

        {/* Additional Information Section */}
        <div className="mt-12 grid md:grid-cols-2 lg:grid-cols-3 gap-6">
          <div className="bg-white rounded-lg p-6 border border-gray-200 shadow-sm">
            <h3 className="text-lg font-semibold text-gray-900 mb-3">How It Works</h3>
            <ul className="space-y-2 text-sm text-gray-600">
              <li>• Deposit USDC into the vault</li>
              <li>• Your deposits automatically earn yield</li>
              <li>• Yield accumulates in the prize pool</li>
              <li>• Weekly draws distribute prizes to winners</li>
              <li>• Withdraw your deposits anytime</li>
            </ul>
          </div>

          <div className="bg-white rounded-lg p-6 border border-gray-200 shadow-sm">
            <h3 className="text-lg font-semibold text-gray-900 mb-3">Prize Draws</h3>
            <ul className="space-y-2 text-sm text-gray-600">
              <li>• Every Friday at 8 PM UTC</li>
              <li>• Powered by Flow Native VRF</li>
              <li>• Cryptographically secure randomness</li>
              <li>• Higher deposits = better chances</li>
              <li>• Winners get the entire prize pool</li>
            </ul>
          </div>

          <div className="bg-white rounded-lg p-6 border border-gray-200 shadow-sm">
            <h3 className="text-lg font-semibold text-gray-900 mb-3">Security</h3>
            <ul className="space-y-2 text-sm text-gray-600">
              <li>• No-loss guarantee</li>
              <li>• Only yield goes to prizes</li>
              <li>• Smart contracts audited</li>
              <li>• Built on Flow EVM</li>
              <li>• Withdraw anytime</li>
            </ul>
          </div>
        </div>

        {/* Flow & FCL Info */}
        <div className={`mt-12 ${hasFullFCLAccess ? 'bg-gradient-to-r from-blue-50 to-green-50 border-blue-200' : 'bg-gradient-to-r from-blue-50 to-purple-50 border-blue-200'} rounded-lg p-8 border`}>
          <div className="text-center">
            <h3 className="text-2xl font-bold text-gray-900 mb-4">
              {hasFullFCLAccess ? 'Connected to Flow Ecosystem' : 'Powered by Flow Blockchain'}
            </h3>
            <div className="grid md:grid-cols-2 gap-6 text-left">
              <div>
                <h4 className="font-semibold text-gray-800 mb-2">Flow Native VRF</h4>
                <p className="text-gray-600 text-sm">
                  Built-in verifiable random function ensures fair and transparent lottery draws 
                  without relying on external oracles.
                </p>
              </div>
              <div>
                <h4 className="font-semibold text-gray-800 mb-2">Flow Client Library (FCL)</h4>
                <p className="text-gray-600 text-sm">
                  {hasFullFCLAccess 
                    ? 'You\'re connected with Flow\'s native authentication system, providing secure access to the entire Flow ecosystem.'
                    : 'Seamless wallet integration with Flow\'s native authentication system, providing secure access to Flow ecosystem features.'
                  }
                </p>
              </div>
            </div>
            
            {hasFullFCLAccess ? (
              <div className="mt-6 bg-green-100 border border-green-300 rounded-lg p-4">
                <div className="flex items-center justify-center space-x-2">
                  <Shield className="w-5 h-5 text-green-600" />
                  <span className="font-medium text-green-800">
                    FCL Connected • Enhanced Flow Experience Active
                  </span>
                </div>
                <p className="text-sm text-green-700 mt-2">
                  You have full access to Flow's native features and seamless EVM compatibility.
                </p>
                {fclAddress && (
                  <p className="text-xs text-green-600 mt-1">
                    Flow Address: {fclAddress}
                  </p>
                )}
              </div>
            ) : !isConnected && fclConnector && (
              <div className="mt-6">
                <div className="text-sm text-gray-600 mb-4">
                  Experience the full power of Flow with native FCL integration
                </div>
                <div className="bg-blue-100 border border-blue-300 rounded-lg p-3">
                  <p className="text-sm text-blue-800">
                    🚀 Connect with Flow FCL to unlock enhanced features and seamless Flow ecosystem integration
                  </p>
                </div>
              </div>
            )}
          </div>
        </div>
      </main>

      {/* Footer */}
      <footer className="bg-white border-t border-gray-200 py-8 mt-16">
        <div className="container mx-auto px-4 text-center text-gray-600">
          <p className="mb-2">
            Built on Flow EVM Testnet • Powered by Flow Native VRF • Integrated with FCL
          </p>
          <p className="text-sm">
            No-Loss Lottery - Your deposits are always safe to withdraw
          </p>
          {hasFullFCLAccess && (
            <p className="text-sm text-blue-600 mt-1">
              ✨ Enhanced Flow experience active
            </p>
          )}
        </div>
      </footer>
    </div>
  )
}

function App() {
  return (
    <Providers>
      <AppContent />
    </Providers>
  );
}

export default App;