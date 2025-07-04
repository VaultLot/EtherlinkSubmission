import time
from langchain.tools import tool
from config import (
    w3,
    agent_account,
    vault_contract,
    vrf_strategy_contract,
    usdc_contract,
    VAULT_ADDRESS,
    VRF_STRATEGY_ADDRESS,
    USDC_TOKEN_ADDRESS,
    CHAIN_ID
)
from web3.exceptions import ContractLogicError

# --- Helper function for sending transactions ---
def send_transaction(tx):
    """Signs and sends a transaction, then waits for the receipt."""
    try:
        signed_tx = w3.eth.account.sign_transaction(tx, agent_account.key)
        tx_hash = w3.eth.send_raw_transaction(signed_tx.rawTransaction)
        print(f"⏳ Transaction sent: {tx_hash.hex()}. Waiting for confirmation...")
        receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)
        print(f"✅ Transaction confirmed in block: {receipt.blockNumber}")
        return {"success": True, "receipt": receipt}
    except ContractLogicError as e:
        print(f"❌ Transaction reverted: {e}")
        return {"success": False, "error": f"Contract logic error: {e}"}
    except Exception as e:
        print(f"❌ An unexpected error occurred: {e}")
        return {"success": False, "error": str(e)}

# ==============================================================================
# AGENT TOOLS
# ==============================================================================

@tool
def get_protocol_status() -> str:
    """
    Gets the current status of the entire prize savings protocol.
    Checks the vault's liquid USDC balance, the total prize pool in the VRF strategy,
    and the address of the last winner. This should be the first tool used to understand the state.
    """
    print("Tool: get_protocol_status")
    try:
        liquid_usdc_wei = usdc_contract.functions.balanceOf(VAULT_ADDRESS).call()
        prize_pool_wei = vrf_strategy_contract.functions.getBalance().call()
        last_winner = vrf_strategy_contract.functions.lastWinner().call()
        
        # USDC has 6 decimals
        liquid_usdc = liquid_usdc_wei / (10**6)
        prize_pool = prize_pool_wei / (10**6)

        status_report = {
            "vault_liquid_usdc": f"{liquid_usdc:.2f} USDC",
            "current_prize_pool": f"{prize_pool:.2f} USDC",
            "last_lottery_winner": last_winner
        }
        return f"Protocol Status: {status_report}"
    except Exception as e:
        return f"Error getting protocol status: {e}"

@tool
def deposit_new_funds_into_strategy() -> str:
    """
    Checks for any liquid USDC in the main vault and deposits it into the VRF strategy contract.
    This action moves funds from the vault's holding area into the active lottery pool, making them
    part of the principal that generates yield.
    """
    print("Tool: deposit_new_funds_into_strategy")
    try:
        liquid_usdc_wei = usdc_contract.functions.balanceOf(VAULT_ADDRESS).call()
        if liquid_usdc_wei == 0:
            return "No new funds in the vault to deposit. All capital is already deployed."

        print(f"Found {liquid_usdc_wei / 10**6} USDC to deposit...")
        
        tx = vault_contract.functions.depositToStrategy(
            VRF_STRATEGY_ADDRESS,
            liquid_usdc_wei,
            b''  # Empty bytes for data parameter
        ).build_transaction({
            'from': agent_account.address,
            'nonce': w3.eth.get_transaction_count(agent_account.address),
            'gas': 2_000_000,
            'gasPrice': w3.eth.gas_price,
            'chainId': CHAIN_ID
        })

        result = send_transaction(tx)
        if result["success"]:
            return f"Successfully deposited {liquid_usdc_wei / 10**6} USDC into the VRF strategy."
        else:
            return f"Failed to deposit funds: {result['error']}"

    except Exception as e:
        return f"Error depositing funds: {e}"

@tool
def simulate_yield_harvest_and_deposit(amount_usdc: float) -> str:
    """
    Simulates harvesting yield from an external protocol by minting new USDC and depositing it
    as the prize pool into the VRF strategy contract. Use this to fund the lottery before a draw.
    Input: amount_usdc (float) - The amount of USDC to simulate as yield, e.g., 150.50.
    """
    print(f"Tool: simulate_yield_harvest_and_deposit (Amount: {amount_usdc})")
    try:
        amount_wei = int(amount_usdc * (10**6))

        # 1. Mint "yield" to the agent's wallet
        print(f"Minting {amount_usdc} USDC to agent...")
        mint_tx = usdc_contract.functions.mint(
            agent_account.address,
            amount_wei
        ).build_transaction({
            'from': agent_account.address,
            'nonce': w3.eth.get_transaction_count(agent_account.address),
            'gas': 500_000,
            'gasPrice': w3.eth.gas_price,
            'chainId': CHAIN_ID
        })
        mint_result = send_transaction(mint_tx)
        if not mint_result["success"]:
            return f"Failed to mint mock yield: {mint_result['error']}"
        
        time.sleep(2) # Give node time to sync state

        # 2. Approve the VRF Strategy to spend the agent's new USDC
        print(f"Approving VRF strategy to spend {amount_usdc} USDC...")
        approve_tx = usdc_contract.functions.approve(
            VRF_STRATEGY_ADDRESS,
            amount_wei
        ).build_transaction({
            'from': agent_account.address,
            'nonce': w3.eth.get_transaction_count(agent_account.address),
            'gas': 500_000,
            'gasPrice': w3.eth.gas_price,
            'chainId': CHAIN_ID
        })
        approve_result = send_transaction(approve_tx)
        if not approve_result["success"]:
            return f"Failed to approve yield deposit: {approve_result['error']}"
            
        time.sleep(2) # Give node time to sync state

        # 3. Deposit the "yield" into the VRF strategy
        print(f"Depositing {amount_usdc} USDC as prize pool...")
        deposit_tx = vrf_strategy_contract.functions.depositYield(
            amount_wei
        ).build_transaction({
            'from': agent_account.address,
            'nonce': w3.eth.get_transaction_count(agent_account.address),
            'gas': 1_000_000,
            'gasPrice': w3.eth.gas_price,
            'chainId': CHAIN_ID
        })
        deposit_result = send_transaction(deposit_tx)
        if deposit_result["success"]:
            return f"Successfully simulated and deposited {amount_usdc} USDC as the prize pool."
        else:
            return f"Failed to deposit yield: {deposit_result['error']}"

    except Exception as e:
        return f"Error simulating yield harvest: {e}"

@tool
def trigger_lottery_draw() -> str:
    """
    Triggers the lottery draw. This function calls harvest on the main vault, which in turn
    calls the VRF strategy to pick a random winner and distribute the entire prize pool.
    Only use this after confirming there is a prize pool to be won.
    """
    print("Tool: trigger_lottery_draw")
    try:
        prize_pool_wei = vrf_strategy_contract.functions.getBalance().call()
        if prize_pool_wei == 0:
            return "Cannot trigger draw: The prize pool is zero. Harvest some yield first."

        print(f"Triggering lottery draw for a prize of {prize_pool_wei / 10**6} USDC...")
        
        tx = vault_contract.functions.harvestStrategy(
            VRF_STRATEGY_ADDRESS,
            b'' # Empty bytes for data
        ).build_transaction({
            'from': agent_account.address,
            'nonce': w3.eth.get_transaction_count(agent_account.address),
            'gas': 2_000_000,
            'gasPrice': w3.eth.gas_price,
            'chainId': CHAIN_ID
        })

        result = send_transaction(tx)
        if result["success"]:
            # Fetch the new winner to report back
            time.sleep(2)
            new_winner = vrf_strategy_contract.functions.lastWinner().call()
            return f"Lottery draw successful! The new winner is {new_winner}."
        else:
            return f"Failed to trigger lottery draw: {result['error']}"

    except Exception as e:
        return f"Error triggering lottery draw: {e}"

