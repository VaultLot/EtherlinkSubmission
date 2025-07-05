import * as fcl from "@onflow/fcl"

// Cadence script to check if a COA exists and get its EVM address
const CHECK_COA_SCRIPT = `
import EVM from 0x8c5303eaa26202d6

access(all) fun main(address: Address): Address? {
    let account = getAccount(address)
    let vaultRef = account
        .capabilities.borrow<&EVM.CadenceOwnedAccount{EVM.Addressable}>(/public/evm)

    if let vault = vaultRef {
        return vault.address()
    }
    return nil
}
`

// Cadence transaction to create a COA if it doesn't exist
const CREATE_COA_TRANSACTION = `
import EVM from 0x8c5303eaa26202d6

transaction {
    prepare(signer: &Account) {
        let vaultRef = signer
            .capabilities.borrow<&EVM.CadenceOwnedAccount{EVM.Addressable}>(/public/evm)

        if vaultRef == nil {
            let vault <- EVM.createCadenceOwnedAccount()
            signer.storage.save(<-vault, to: /storage/evm)
            
            let capability = signer.capabilities.storage
                .issue<&EVM.CadenceOwnedAccount{EVM.Addressable}>(/storage/evm)
            signer.capabilities.publish(capability, at: /public/evm)
        }
    }
}
`

export async function ensureCOAExists(userAddress: string): Promise<string | null> {
  try {
    // First, check if COA already exists
    const existingCOA = await fcl.query({
      cadence: CHECK_COA_SCRIPT,
      args: (arg: any, t: any) => [arg(userAddress, t.Address)],
    })

    if (existingCOA) {
      console.log('COA already exists:', existingCOA)
      return existingCOA
    }

    // COA doesn't exist, create it
    console.log('Creating new COA for user:', userAddress)

    const transactionId = await fcl.mutate({
      cadence: CREATE_COA_TRANSACTION,
      proposer: fcl.currentUser,
      authorizations: [fcl.currentUser],
      payer: fcl.currentUser,
      limit: 1000,
    })

    console.log('COA creation transaction:', transactionId)

    // Wait for transaction to be sealed
    const transaction = await fcl.tx(transactionId).onceSealed()
    console.log('COA creation transaction sealed:', transaction)

    // Query again to get the new COA address
    const newCOA = await fcl.query({
      cadence: CHECK_COA_SCRIPT,
      args: (arg: any, t: any) => [arg(userAddress, t.Address)],
    })

    console.log('New COA created:', newCOA)
    return newCOA
  } catch (error) {
    console.error('Error ensuring COA exists:', error)
    return null
  }
}

export async function getCOAAddress(userAddress: string): Promise<string | null> {
  try {
    const coaAddress = await fcl.query({
      cadence: CHECK_COA_SCRIPT,
      args: (arg: any, t: any) => [arg(userAddress, t.Address)],
    })

    return coaAddress
  } catch (error) {
    console.error('Error getting COA address:', error)
    return null
  }
}