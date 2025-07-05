import { useEffect, useState } from 'react'
import { useAccount } from 'wagmi'
import * as fcl from '@onflow/fcl'

export function useFCLStatus() {
  const { connector } = useAccount()
  const [fclUser, setFclUser] = useState<any>({ loggedIn: null })

  // FCL user subscription
  useEffect(() => {
    const unsubscribe = fcl.currentUser.subscribe(setFclUser)
    return () => unsubscribe()
  }, [])

  // Check if connected via FCL Wagmi connector
  const isFCLConnected = connector?.name === 'FCL' || connector?.id === 'fcl'
  const isFCLAuthenticated = fclUser.loggedIn === true

  return {
    isFCLConnected,
    isFCLAuthenticated,
    fclUser,
    // Helper to check if user has full FCL integration
    hasFullFCLAccess: isFCLConnected && isFCLAuthenticated,
    // Helper to get FCL address if available
    fclAddress: fclUser.addr || null,
  }
}

// Optional: Export individual hooks if you prefer granular imports
export function useIsFCLConnected() {
  const { connector } = useAccount()
  return connector?.name === 'FCL' || connector?.id === 'fcl'
}

export function useFCLUser() {
  const [fclUser, setFclUser] = useState<any>({ loggedIn: null })

  useEffect(() => {
    const unsubscribe = fcl.currentUser.subscribe(setFclUser)
    return () => unsubscribe()
  }, [])

  return fclUser
}

// Helper hook to check if user should see FCL upgrade prompts
export function useShouldPromoteFCL() {
  const { isConnected } = useAccount()
  const { isFCLConnected } = useFCLStatus()

  // Show FCL promotion if user is not connected or connected with non-FCL wallet
  return !isConnected || !isFCLConnected
}