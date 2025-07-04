import os
import json
import time
from dotenv import load_dotenv
from web3 import Web3
from web3.middleware import geth_poa_middleware
from web3.exceptions import ContractLogicError
from fastapi import FastAPI
from pydantic import BaseModel
from langchain_openai import ChatOpenAI
from langchain.agents import AgentExecutor, create_react_agent
from langchain_core.prompts import PromptTemplate
from langchain.tools import tool

# ==============================================================================
# 1. NEAR CONFIGURATION AND SETUP
# ==============================================================================

load_dotenv()

# --- NEAR Configuration ---
RPC_URL = os.getenv("NEAR_TESTNET_RPC_URL")
CHAIN_ID = int(os.getenv("NEAR_TESTNET_CHAIN_ID"))
AGENT_PRIVATE_KEY = os.getenv("AGENT_PRIVATE_KEY")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")

# --- Contract Addresses ---
VAULT_ADDRESS = os.getenv("VAULT_ADDRESS")
VRF_STRATEGY_ADDRESS = os.getenv("VRF_STRATEGY_ADDRESS")
USDC_TOKEN_ADDRESS = os.getenv("USDC_TOKEN_ADDRESS")

# --- Web3 Setup ---
w3 = Web3(Web3.HTTPProvider(RPC_URL))
w3.middleware_onion.inject(geth_poa_middleware, layer=0)

# --- Agent Account ---
agent_account = w3.eth.account.from_key(AGENT_PRIVATE_KEY)
print(f"🤖 NEAR Agent Wallet Address: {agent_account.address}")

# --- ABI Loading ---
def load_abi(filename):
    path = os.path.join("abi", filename)
    with open(path, "r") as f:
        return json.load(f)["abi"]

vault_abi = load_abi("Vault.json")
# Use the new NearVrfStrategy ABI
vrf_strategy_abi = load_abi("NearVrfStrategy.json") 
usdc_abi = load_abi("MockUSDC.json")

# --- Contract Objects ---
vault_contract = w3.eth.contract(address=VAULT_ADDRESS, abi=vault_abi)
vrf_strategy_contract = w3.eth.contract(address=VRF_STRATEGY_ADDRESS, abi=vrf_strategy_abi)
usdc_contract = w3.eth.contract(address=USDC_TOKEN_ADDRESS, abi=usdc_abi)

print("✅ NEAR Configuration loaded.")

# ==============================================================================
# 2. AGENT TOOLS (Identical logic, just on NEAR)
# ==============================================================================

def send_transaction(tx):
    try:
        signed_tx = w3.eth.account.sign_transaction(tx, agent_account.key)
        tx_hash = w3.eth.send_raw_transaction(signed_tx.rawTransaction)
        print(f"⏳ NEAR Tx Sent: {tx_hash.hex()}. Waiting...")
        receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)
        print(f"✅ NEAR Tx Confirmed in block: {receipt.blockNumber}")
        return {"success": True, "receipt": receipt}
    except Exception as e:
        return {"success": False, "error": str(e)}

@tool
def get_protocol_status() -> str:
    """Gets the current status of the NEAR prize savings protocol."""
    print("Tool: get_protocol_status (NEAR)")
    liquid_usdc_wei = usdc_contract.functions.balanceOf(VAULT_ADDRESS).call()
    prize_pool_wei = vrf_strategy_contract.functions.getBalance().call()
    last_winner = vrf_strategy_contract.functions.lastWinner().call()
    liquid_usdc = liquid_usdc_wei / (10**6)
    prize_pool = prize_pool_wei / (10**6)
    return f"Protocol Status on NEAR: Vault has {liquid_usdc:.2f} liquid USDC. Prize pool is {prize_pool:.2f} USDC. Last winner: {last_winner}."

@tool
def deposit_new_funds_into_strategy() -> str:
    """Moves liquid USDC from the NEAR vault into the active lottery strategy."""
    print("Tool: deposit_new_funds_into_strategy (NEAR)")
    liquid_usdc_wei = usdc_contract.functions.balanceOf(VAULT_ADDRESS).call()
    if liquid_usdc_wei == 0:
        return "No new funds to deposit."
    tx = vault_contract.functions.depositToStrategy(VRF_STRATEGY_ADDRESS, liquid_usdc_wei, b'').build_transaction({
        'from': agent_account.address, 'nonce': w3.eth.get_transaction_count(agent_account.address), 'gas': 2000000, 'gasPrice': w3.eth.gas_price, 'chainId': CHAIN_ID
    })
    result = send_transaction(tx)
    return f"Successfully deposited {liquid_usdc_wei / 10**6} USDC." if result["success"] else f"Failed: {result['error']}"

@tool
def simulate_yield_harvest_and_deposit(amount_usdc: float) -> str:
    """Simulates harvesting yield by minting USDC and depositing it as the prize pool on NEAR."""
    print(f"Tool: simulate_yield_harvest_and_deposit (NEAR, Amount: {amount_usdc})")
    amount_wei = int(amount_usdc * (10**6))
    
    mint_tx = usdc_contract.functions.mint(agent_account.address, amount_wei).build_transaction({
        'from': agent_account.address, 'nonce': w3.eth.get_transaction_count(agent_account.address), 'gas': 500000, 'gasPrice': w3.eth.gas_price, 'chainId': CHAIN_ID
    })
    if not send_transaction(mint_tx)["success"]: return "Failed to mint mock yield."
    
    approve_tx = usdc_contract.functions.approve(VRF_STRATEGY_ADDRESS, amount_wei).build_transaction({
        'from': agent_account.address, 'nonce': w3.eth.get_transaction_count(agent_account.address), 'gas': 500000, 'gasPrice': w3.eth.gas_price, 'chainId': CHAIN_ID
    })
    if not send_transaction(approve_tx)["success"]: return "Failed to approve yield deposit."

    deposit_tx = vrf_strategy_contract.functions.depositYield(amount_wei).build_transaction({
        'from': agent_account.address, 'nonce': w3.eth.get_transaction_count(agent_account.address), 'gas': 1000000, 'gasPrice': w3.eth.gas_price, 'chainId': CHAIN_ID
    })
    return f"Successfully deposited {amount_usdc} USDC as prize pool." if send_transaction(deposit_tx)["success"] else "Failed to deposit yield."

@tool
def trigger_lottery_draw() -> str:
    """Triggers the VRF-powered lottery draw on the NEAR protocol."""
    print("Tool: trigger_lottery_draw (NEAR)")
    prize_pool_wei = vrf_strategy_contract.functions.getBalance().call()
    if prize_pool_wei == 0:
        return "Cannot trigger draw: Prize pool is zero."
    tx = vault_contract.functions.harvestStrategy(VRF_STRATEGY_ADDRESS, b'').build_transaction({
        'from': agent_account.address, 'nonce': w3.eth.get_transaction_count(agent_account.address), 'gas': 2000000, 'gasPrice': w3.eth.gas_price, 'chainId': CHAIN_ID
    })
    result = send_transaction(tx)
    if result["success"]:
        new_winner = vrf_strategy_contract.functions.lastWinner().call()
        return f"NEAR lottery draw successful! The new winner is {new_winner}."
    return f"Failed to trigger NEAR lottery draw: {result['error']}"

# ==============================================================================
# 3. LANGCHAIN AGENT AND FASTAPI SERVER
# ==============================================================================

tools = [get_protocol_status, deposit_new_funds_into_strategy, simulate_yield_harvest_and_deposit, trigger_lottery_draw]
tool_names = [t.name for t in tools]

prompt_template = """
You are the "Vault Manager," an AI agent operating a no-loss prize savings game on the NEAR blockchain.
Your address is: {agent_address}. Your goal is to manage the protocol's funds for the weekly prize draw.
You have access to the following tools:
{tools}
Use the following format:
Question: the user's request
Thought: First, check the protocol status. Then, decide the next step.
Action: one of [{tool_names}]
Action Input: the input to the action
Observation: the result of the action
... (this can repeat)
Thought: I now know the final answer.
Final Answer: the final answer to the original input question.

Begin!
Question: {input}
Thought: {agent_scratchpad}
"""
prompt = PromptTemplate.from_template(prompt_template)

llm = ChatOpenAI(model="gpt-4o-mini", temperature=0, api_key=OPENAI_API_KEY)
react_agent = create_react_agent(llm, tools, prompt)
agent_executor = AgentExecutor(agent=react_agent, tools=tools, verbose=True, handle_parsing_errors=True)

app = FastAPI(title="NEAR Vault Manager Agent")

class AgentRequest(BaseModel):
    command: str

@app.post("/invoke-agent")
async def invoke_agent(request: AgentRequest):
    try:
        tool_descriptions = "\n".join([f"{tool.name}: {tool.description}" for tool in tools])
        response = await agent_executor.ainvoke({
            "input": request.command,
            "agent_address": agent_account.address,
            "tools": tool_descriptions,
            "tool_names": ", ".join(tool_names)
        })
        return {"success": True, "output": response["output"]}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.get("/")
def read_root():
    return {"message": "NEAR Vault Manager Agent is running."}

# To run: uvicorn main:app --reload
