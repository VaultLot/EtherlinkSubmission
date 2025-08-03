import React from 'react';
import { Header } from '@/components/header'
import { Dashboard } from '@/components/dashboard'
import { DepositWithdraw } from '@/components/deposit-withdraw'
import { MyStats } from '@/components/my-stats'
import { LotteryHistory } from '@/components/lottery-history'
import { WalletDebugInfo } from '@/components/wallet-debug-info'
import { ErrorBoundary } from '@/components/error-boundary'
import { useAccount } from 'wagmi'
import { Shield, Wallet } from 'lucide-react'
import Providers from '@/components/providers'

function AppContent() {
  const { isConnected } = useAccount()

  // Show debug info in development
  const showDebugInfo = process.env.NODE_ENV === 'development'

  return (
    <div className="min-h-screen bg-gray-50">
      <Header />

      <main className="container mx-auto px-4 py-8">
        {/* Hero Section */}
        <div className="text-center mb-12">
          <div className="max-w-3xl mx-auto">
            <h1 className="text-4xl font-bold text-gray-900 mb-4">
              Etherlink Prize Savings
            </h1>
            <p className="text-xl text-gray-600 mb-6">
              No-Loss Lottery powered by Smart Contracts
            </p>
            <p className="text-gray-500">
              Deposit USDC, earn yield, and win weekly prizes. Your deposits are always safe to withdraw.
            </p>
            
            {/* Connection Status Indicator */}
            {isConnected && (
              <div className="mt-4 inline-flex items-center px-4 py-2 bg-green-50 border border-green-200 rounded-full">
                <div className="w-2 h-2 bg-green-500 rounded-full mr-2"></div>
                <Shield className="w-4 h-4 text-green-600 mr-2" />
                <span className="text-sm text-green-700">
                  Connected to Etherlink Testnet
                </span>
              </div>
            )}
          </div>
        </div>

        {/* Main Dashboard */}
        <ErrorBoundary>
          <Dashboard />
        </ErrorBoundary>

        {/* Debug Info (Development Only) */}
        {showDebugInfo && isConnected && (
          <div className="mb-8">
            <WalletDebugInfo />
          </div>
        )}

        {/* Main Content Grid */}
        <div className="grid lg:grid-cols-3 gap-8">
          {/* Left Column - Deposit/Withdraw */}
          <div className="lg:col-span-1">
            <ErrorBoundary>
              <DepositWithdraw />
            </ErrorBoundary>
          </div>

          {/* Middle Column - My Stats */}
          <div className="lg:col-span-1">
            <ErrorBoundary>
              <MyStats />
            </ErrorBoundary>
          </div>

          {/* Right Column - Lottery History */}
          <div className="lg:col-span-1">
            <ErrorBoundary>
              <LotteryHistory />
            </ErrorBoundary>
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
              <li>• Powered by secure smart contracts</li>
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
              <li>• Built on Etherlink testnet</li>
              <li>• Withdraw anytime</li>
            </ul>
          </div>
        </div>

        {/* Etherlink Info */}
        <div className="mt-12 bg-gradient-to-r from-blue-50 to-purple-50 border-blue-200 rounded-lg p-8 border">
          <div className="text-center">
            <h3 className="text-2xl font-bold text-gray-900 mb-4">
              Powered by Etherlink Blockchain
            </h3>
            <div className="grid md:grid-cols-2 gap-6 text-left">
              <div>
                <h4 className="font-semibold text-gray-800 mb-2">EVM Compatible</h4>
                <p className="text-gray-600 text-sm">
                  Built on Etherlink, providing full Ethereum compatibility with the security 
                  and efficiency of Tezos infrastructure.
                </p>
              </div>
              <div>
                <h4 className="font-semibold text-gray-800 mb-2">Smart Contract Security</h4>
                <p className="text-gray-600 text-sm">
                  Your funds are protected by battle-tested smart contracts and the proven 
                  security of the Tezos ecosystem.
                </p>
              </div>
            </div>
            
            <div className="mt-6 bg-blue-100 border border-blue-300 rounded-lg p-4">
              <div className="flex items-center justify-center space-x-2">
                <Shield className="w-5 h-5 text-blue-600" />
                <span className="font-medium text-blue-800">
                  Secure • Fast • Low Fees
                </span>
              </div>
              <p className="text-sm text-blue-700 mt-2">
                Experience the power of Etherlink with minimal gas fees and fast transactions.
              </p>
            </div>
          </div>
        </div>
      </main>

      {/* Footer */}
      <footer className="bg-white border-t border-gray-200 py-8 mt-16">
        <div className="container mx-auto px-4 text-center text-gray-600">
          <p className="mb-2">
            Built on Etherlink Testnet • Powered by Smart Contracts
          </p>
          <p className="text-sm">
            No-Loss Lottery - Your deposits are always safe to withdraw
          </p>
          {process.env.NODE_ENV === 'development' && (
            <p className="text-xs text-gray-400 mt-2">
              Development Mode • Debug Info Available
            </p>
          )}
        </div>
      </footer>
    </div>
  )
}

function App() {
  return (
    <ErrorBoundary>
      <Providers>
        <AppContent />
      </Providers>
    </ErrorBoundary>
  );
}

export default App;