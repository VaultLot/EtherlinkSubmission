import { writeContract as wagmiWriteContract } from '@wagmi/core'
import { config } from '@/lib/wagmi'
import { Address } from 'viem'

interface EVMWriteContractParams {
  address: Address
  abi: any
  functionName: string
  args?: readonly any[]
  account: Address
}

export async function writeEVMContract(params: EVMWriteContractParams) {
  try {
    console.log('=== FORCING EVM TRANSACTION ===')
    console.log('Account (EVM address):', params.account)
    console.log('Contract:', params.address)
    console.log('Function:', params.functionName)
    console.log('Args:', params.args)

    // Force the transaction to use the specific EVM account
    const result = await wagmiWriteContract(config, {
      address: params.address,
      abi: params.abi,
      functionName: params.functionName,
      args: params.args || [],
      account: params.account,
      // Add EVM-specific parameters
      chain: config.chains[0], // Force Flow Testnet EVM
    })

    console.log('EVM Transaction submitted:', result)
    return result
  } catch (error) {
    console.error('EVM Transaction failed:', error)
    throw error
  }
}