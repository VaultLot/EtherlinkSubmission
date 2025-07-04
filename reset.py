# reset_game.py
import os
import json
from web3 import Web3
from dotenv import load_dotenv

# --- Configuration ---
load_dotenv()

RPC_URL = os.getenv("FLOW_TESTNET_RPC_URL")
PRIVATE_KEY = os.getenv("PRIVATE_KEY")
CONTRACT_ADDRESS = os.getenv("NEXT_PUBLIC_CONTRACT_ADDRESS")

if not all([RPC_URL, PRIVATE_KEY, CONTRACT_ADDRESS]):
    print("Error: Make sure FLOW_TESTNET_RPC_URL, PRIVATE_KEY, and NEXT_PUBLIC_CONTRACT_ADDRESS are set in your .env file.")
    exit()

# --- Load Contract ABI ---
try:
    # MODIFIED: Updated path to your ABI file
    with open('abi/DicePoker.json', 'r') as f:
        contract_abi = json.load(f)['abi']
except FileNotFoundError:
    print("Error: 'abi/DicePoker.json' not found. Make sure the path is correct.")
    exit()
except (KeyError, json.JSONDecodeError):
    print("Error: The ABI JSON file is not formatted correctly or is missing the 'abi' key.")
    exit()


# --- Script Execution ---
def main():
    """Connects to the blockchain, calls resetIfExpired, and waits for confirmation."""
    print("--- Starting Game Reset Script ---")

    # 1. Connect to the Flow EVM Testnet
    w3 = Web3(Web3.HTTPProvider(RPC_URL))
    if not w3.is_connected():
        print("❌ Failed to connect to the blockchain.")
        return
    print(f"✅ Connected to blockchain (Chain ID: {w3.eth.chain_id})")

    # 2. Set up your account
    try:
        account = w3.eth.account.from_key(PRIVATE_KEY)
        print(f"✅ Loaded account: {account.address}")
    except Exception as e:
        print(f"❌ Error loading account from private key: {e}")
        return

    # 3. Create contract instance
    contract = w3.eth.contract(address=CONTRACT_ADDRESS, abi=contract_abi)
    print(f"✅ Initialized contract at: {CONTRACT_ADDRESS}")

    try:
        # 4. Build the transaction to call 'resetIfExpired'
        print("\n🔧 Building transaction for 'resetIfExpired'...")
        tx_data = contract.functions.resetIfExpired().build_transaction({
            'from': account.address,
            'nonce': w3.eth.get_transaction_count(account.address),
            'gas': 200000,
            'gasPrice': w3.eth.gas_price
        })

        # 5. Sign the transaction
        print("✍️ Signing transaction...")
        signed_tx = w3.eth.account.sign_transaction(tx_data, private_key=PRIVATE_KEY)

        # 6. Send the transaction
        print("🚀 Sending transaction to the network...")
        tx_hash = w3.eth.send_raw_transaction(signed_tx.raw_transaction)
        print(f"🔗 Transaction sent! Hash: {tx_hash.hex()}")

        # 7. Wait for the transaction to be mined
        print("⏳ Waiting for transaction confirmation...")
        receipt = w3.eth.wait_for_transaction_receipt(tx_hash)

        if receipt['status'] == 1:
            print("\n🎉 SUCCESS: Game reset transaction confirmed!")
            print(f"   - Block Number: {receipt['blockNumber']}")
            print(f"   - Gas Used: {receipt['gasUsed']}")
        else:
            print("\n❌ FAILED: Transaction was reverted by the contract.")
            print("   - This might happen if the game is not in a state that allows for a reset (e.g., the timeout has not passed).")

    except Exception as e:
        print(f"\nAn error occurred: {e}")
        print("   - Please check if your contract has funds for gas and if the game state allows for a reset.")

if __name__ == "__main__":
    main()