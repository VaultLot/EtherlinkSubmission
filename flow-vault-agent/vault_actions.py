import time
from coinbase_agentkit import ActionProvider, action
from coinbase_agentkit.wallet import LocalWalletProvider
from pydantic import BaseModel, Field
from web3.exceptions import ContractLogicError

# Import our setup from config.py
from config import (
    w3,
    agent_account,
    vault_contract,
    vrf_strategy_contract,
    usdc_contract,
    VAULT_ADDRESS,
    VRF_STRATEGY_ADDRESS,
    CHAIN_ID
)

# --- Helper function for sending transactions ---
# This remains the same, as it's a reliable way to handle tx logic.
def send_transaction(tx):
    try:
        signed_tx = w3.eth.account.sign_transaction(tx, agent_account.key)
        tx_hash = w3.eth.send_raw_transaction(signed_tx.rawTransaction)
        print(f"⏳ Tx Sent: {tx_hash.hex()}. Waiting...")
        receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)
        print(f"✅ Tx Confirmed in block: {receipt.blockNumber}")
        return {"success": True, "receipt": receipt}
    except Exception as e:
        print(f"❌ Tx Error: {e}")
        return {"success": False, "error": str(e)}

# --- Define Input Schemas for our Actions using Pydantic ---
class SimulateYieldInput(BaseModel):
    amount_usdc: float = Field(..., description="The amount of USDC to simulate as yield, e.g., 150.50.")

# --- Create a Custom Action Provider ---
class VaultActionProvider(ActionProvider):
    """An ActionProvider for managing the Prize Savings Vault."""

    def __init__(self):
        # The name of our tool group
        super().__init__(name="prize_vault_manager")

    @action(
        name="get_protocol_status",
        description="Gets the current status of the prize savings protocol. Checks balances and the last winner. ALWAYS use this first.",
        input_schema=None, # No input needed
    )
    async def get_protocol_status(self, wallet_provider: LocalWalletProvider) -> str:
        print("Action: get_protocol_status")
        liquid_usdc_wei = usdc_contract.functions.balanceOf(VAULT_ADDRESS).call()
        prize_pool_wei = vrf_strategy_contract.functions.getBalance().call()
        last_winner = vrf_strategy_contract.functions.lastWinner().call()
        liquid_usdc = liquid_usdc_wei / (10**6)
        prize_pool = prize_pool_wei / (10**6)
        return f"Protocol Status: Vault has {liquid_usdc:.2f} liquid USDC. The prize pool is {prize_pool:.2f} USDC. The last winner was {last_winner}."

    @action(
        name="deposit_new_funds_into_strategy",
        description="Moves any liquid USDC from the main vault into the active lottery strategy.",
        input_schema=None,
    )
    async def deposit_new_funds(self, wallet_provider: LocalWalletProvider) -> str:
        print("Action: deposit_new_funds_into_strategy")
        liquid_usdc_wei = usdc_contract.functions.balanceOf(VAULT_ADDRESS).call()
        if liquid_usdc_wei == 0:
            return "No new funds to deposit."
        
        tx = vault_contract.functions.depositToStrategy(VRF_STRATEGY_ADDRESS, liquid_usdc_wei, b'').build_transaction({
            'from': agent_account.address, 'nonce': w3.eth.get_transaction_count(agent_account.address), 'gas': 2000000, 'gasPrice': w3.eth.gas_price, 'chainId': CHAIN_ID
        })
        result = send_transaction(tx)
        return f"Successfully deposited {liquid_usdc_wei / 10**6} USDC." if result["success"] else f"Failed: {result['error']}"

    @action(
        name="simulate_yield_harvest_and_deposit",
        description="Simulates harvesting yield by minting new USDC and depositing it as the prize pool.",
        input_schema=SimulateYieldInput,
    )
    async def simulate_yield(self, args: SimulateYieldInput, wallet_provider: LocalWalletProvider) -> str:
        print(f"Action: simulate_yield_harvest_and_deposit (Amount: {args.amount_usdc})")
        amount_wei = int(args.amount_usdc * (10**6))
        
        # This action now performs 3 transactions, which is a great candidate for batching with Cadence in the future.
        # 1. Mint
        mint_tx = usdc_contract.functions.mint(agent_account.address, amount_wei).build_transaction({
            'from': agent_account.address, 'nonce': w3.eth.get_transaction_count(agent_account.address), 'gas': 500000, 'gasPrice': w3.eth.gas_price, 'chainId': CHAIN_ID
        })
        if not send_transaction(mint_tx)["success"]: return "Failed to mint mock yield."
        
        # 2. Approve
        approve_tx = usdc_contract.functions.approve(VRF_STRATEGY_ADDRESS, amount_wei).build_transaction({
            'from': agent_account.address, 'nonce': w3.eth.get_transaction_count(agent_account.address), 'gas': 500000, 'gasPrice': w3.eth.gas_price, 'chainId': CHAIN_ID
        })
        if not send_transaction(approve_tx)["success"]: return "Failed to approve yield deposit."

        # 3. Deposit Yield
        deposit_tx = vrf_strategy_contract.functions.depositYield(amount_wei).build_transaction({
            'from': agent_account.address, 'nonce': w3.eth.get_transaction_count(agent_account.address), 'gas': 1000000, 'gasPrice': w3.eth.gas_price, 'chainId': CHAIN_ID
        })
        return f"Successfully deposited {args.amount_usdc} USDC as prize pool." if send_transaction(deposit_tx)["success"] else "Failed to deposit yield."

    @action(
        name="trigger_lottery_draw",
        description="Triggers the VRF-powered lottery draw. Only use this after confirming there is a prize pool to be won.",
        input_schema=None,
    )
    async def trigger_draw(self, wallet_provider: LocalWalletProvider) -> str:
        print("Action: trigger_lottery_draw")
        prize_pool_wei = vrf_strategy_contract.functions.getBalance().call()
        if prize_pool_wei == 0:
            return "Cannot trigger draw: Prize pool is zero."

        tx = vault_contract.functions.harvestStrategy(VRF_STRATEGY_ADDRESS, b'').build_transaction({
            'from': agent_account.address, 'nonce': w3.eth.get_transaction_count(agent_account.address), 'gas': 2000000, 'gasPrice': w3.eth.gas_price, 'chainId': CHAIN_ID
        })
        result = send_transaction(tx)
        if result["success"]:
            new_winner = vrf_strategy_contract.functions.lastWinner().call()
            return f"Lottery draw successful! The new winner is {new_winner}."
        return f"Failed to trigger draw: {result['error']}"
