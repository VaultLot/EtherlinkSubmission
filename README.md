No-Loss Prize Savings Game

gamified savings protocol

People want to save money and earn returns, but traditional savings offer tiny, boring yields. Lotteries are exciting, but you almost always lose your money. This app solves both proeblems.

X people in, 1 gets their money + the yield, losers get their money back.



FRONTEND: Use of onflow/FCL module if needed in app




Make agent interact with uniswap contracts... etc


AI-Powered Yield Optimization for Flow Blockchain


🌊 Deploying contracts to Flow Testnet: flow_testnet
➤ Deployer: 0xa341b0F69359482862Ed4422c6057cd59560D9E4
➤ Balance: 199873.99865709302 FLOW

🚀 Deploying MockUSDC for testing...
✅ MockUSDC deployed at: 0x4edbDC8Ed8Ca935513A2F06e231EE42FB6ed1d15

🚀 Deploying VaultFactory...
✅ VaultFactory deployed at: 0xa87fe90A07DE4E10398F2203A9F3Bd8b98Cf902D

🏭 Using VaultFactory to create a new Vault...
✅ New Vault created successfully at: 0xBaE8f26eDa40Ab353A34ce38F8917318d226318F

🚀 Deploying FlowVrfYieldStrategy...
✅ FlowVrfYieldStrategy deployed at: 0xf5DC9ca0518B45C3E372c3bC7959a4f3d1B18901

🔗 Adding the new VRF strategy to the Vault...
✅ Strategy added and configured successfully!

🎉 --- DEPLOYMENT SUMMARY --- 🎉
------------------------------------
   Mock USDC Token:     0x4edbDC8Ed8Ca935513A2F06e231EE42FB6ed1d15
   Vault Factory:       0xa87fe90A07DE4E10398F2203A9F3Bd8b98Cf902D
   Lottery Vault:       0xBaE8f26eDa40Ab353A34ce38F8917318d226318F
   Flow VRF Strategy:   0xf5DC9ca0518B45C3E372c3bC7959a4f3d1B18901
------------------------------------

🔮 VRF Integration Details:
   The Flow VRF Strategy uses the Cadence Arch contract at:
   0x0000000000000000000000010000000000000001
   This provides secure, on-chain randomness.

🎯 Next Steps:
   1. Use the MockUSDC contract to mint test tokens to your wallet.
      e.g., call 'mint("0xa341b0F69359482862Ed4422c6057cd59560D9E4", "1000000000")' // 1000 USDC
   2. Approve the Vault to spend your USDC.
   3. Deposit your USDC into the Vault contract.
   4. As the agent, call 'depositToStrategy' on the Vault to move funds to the lottery.
   5. Call 'harvest' on the Vault to trigger the lottery and award a winner!