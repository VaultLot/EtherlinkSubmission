issues with aurora faucet, having to deploy on eth sepolia for now until faucet back

🌍 Deploying contracts to Ethereum Sepolia: ethereumSepolia
➤ Deployer: 0x1fF116257e646b6C0220a049e893e81DE87fc475
➤ Balance: 2.332784966360525559 ETH

🚀 Deploying MockUSDC for testing...
✅ MockUSDC deployed at: 0x90cC65cCaEF6F856E54a22647f1656835EB1588C

🚀 Deploying VaultFactory...
✅ VaultFactory deployed at: 0x863728Ac20C0453D7b5BB23aAFb1265D587A027E

🏭 Using VaultFactory to create a new Vault for Sepolia...
✅ New Vault created successfully at: 0x8f97b2f418BF05DD59759FFf93FCdA1C74849805

🚀 Deploying SepoliaVrfStrategy...
✅ SepoliaVrfStrategy deployed at: 0x525ce5DFf70411C5caA7cB18D5A584f7cCEDe621

🔗 Adding the new Sepolia VRF strategy to the Vault...
✅ Strategy added and configured successfully!

🎉 --- SEPOLIA DEPLOYMENT SUMMARY --- 🎉
------------------------------------
   Mock USDC Token:        0x90cC65cCaEF6F856E54a22647f1656835EB1588C
   Vault Factory:          0x863728Ac20C0453D7b5BB23aAFb1265D587A027E
   Lottery Vault:          0x8f97b2f418BF05DD59759FFf93FCdA1C74849805
   Sepolia VRF Strategy:   0x525ce5DFf70411C5caA7cB18D5A584f7cCEDe621
------------------------------------

🔮 Randomness Integration Details:
   The SepoliaVrfStrategy uses block variables for pseudo-randomness.
   This is for testing purposes only and is not secure for production.

🎯 Next Steps on Sepolia:
   1. Use the MockUSDC contract to mint test tokens.
   2. Approve the Vault to spend your USDC.
   3. Deposit USDC into the Vault.
   4. Use your agent to manage the protocol on Sepolia!