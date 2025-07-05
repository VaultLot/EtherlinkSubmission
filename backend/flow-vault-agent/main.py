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
# 1. CONFIGURATION AND SETUP
# ==============================================================================

# Load environment variables from .env file
load_dotenv()

# --- Basic Configuration ---
RPC_URL = os.getenv("FLOW_TESTNET_RPC_URL")
CHAIN_ID = int(os.getenv("FLOW_TESTNET_CHAIN_ID"))
AGENT_PRIVATE_KEY = os.getenv("AGENT_PRIVATE_KEY")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")

# --- Contract Addresses ---
VAULT_ADDRESS = os.getenv("VAULT_ADDRESS")
VRF_STRATEGY_ADDRESS = os.getenv("VRF_STRATEGY_ADDRESS")
USDC_TOKEN_ADDRESS = os.getenv("USDC_TOKEN_ADDRESS")

# --- Web3 Setup ---
w3 = Web3(Web3.HTTPProvider(RPC_URL))
# Inject PoA middleware for chains like Flow EVM
w3.middleware_onion.inject(geth_poa_middleware, layer=0)

# --- Agent Account Setup ---
agent_account = w3.eth.account.from_key(AGENT_PRIVATE_KEY)
print(f"🤖 Agent Wallet Address: {agent_account.address}")


# --- Function to load ABI ---
def load_abi(filename):
    """Loads a contract ABI from the abi directory."""
    path = os.path.join("abi", filename)
    with open(path, "r") as f:
        return json.load(f)["abi"]

# --- Load ABIs ---
vault_abi = load_abi("Vault.json")
vrf_strategy_abi = load_abi("FlowVrfYieldStrategy.json")
usdc_abi = load_abi("MockUSDC.json")

# --- Create Contract Objects ---
vault_contract = w3.eth.contract(address=VAULT_ADDRESS, abi=vault_abi)
vrf_strategy_contract = w3.eth.contract(address=VRF_STRATEGY_ADDRESS, abi=vrf_strategy_abi)
usdc_contract = w3.eth.contract(address=USDC_TOKEN_ADDRESS, abi=usdc_abi)

print("✅ Configuration loaded and contracts initialized.")


# ==============================================================================
# 2. AGENT TOOLS
# ==============================================================================

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
    This action moves funds from the vault's holding area into the active lottery pool.
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
    Simulates harvesting yield by minting new USDC and depositing it
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


# ==============================================================================
# 3. LANGCHAIN AGENT AND FASTAPI SERVER
# ==============================================================================

# --- Agent Setup ---

# 1. Define the tools the agent can use
tools = [
    get_protocol_status,
    deposit_new_funds_into_strategy,
    simulate_yield_harvest_and_deposit,
    trigger_lottery_draw
]
tool_names = [t.name for t in tools]

# 2. Create the prompt template
prompt_template = """
You are the "Vault Manager," a highly efficient and reliable AI agent responsible for operating a no-loss prize savings game on the Flow blockchain.

Your address is: {agent_address}.

Your primary goal is to manage the protocol's funds to ensure a weekly prize can be awarded to a lucky user. You operate with precision and follow a strict operational procedure.

You have access to the following tools:

{tools}

Use the following format for your thought process:

Question: the user's request or the task you need to perform
Thought: You should always think about what to do. First, always check the protocol status to understand the current state. Then, decide the next logical step based on the user's request and the protocol's state.
Action: the action to take, should be one of [{tool_names}]
Action Input: the input to the action
Observation: the result of the action
... (this Thought/Action/Action Input/Observation can repeat N times)
Thought: I now know the final answer.
Final Answer: the final answer to the original input question.

**Operational Procedure:**

1.  **Assessment:** Always start by using the `get_protocol_status` tool to understand the current state of the vault and the prize pool.
2.  **Capital Deployment:** If you see liquid USDC in the vault, your duty is to deploy it using `deposit_new_funds_into_strategy`.
3.  **Yield Simulation (for demo):** To prepare for a lottery draw, you must first fund the prize pool. Use the `simulate_yield_harvest_and_deposit` tool. A reasonable weekly prize might be between 50 and 500 USDC.
4.  **Lottery Execution:** Once you confirm there is a prize pool, and only then, you can execute the weekly draw using `trigger_lottery_draw`.

Begin!

Question: {input}
Thought: {agent_scratchpad}
"""

prompt = PromptTemplate.from_template(prompt_template)

# 3. Initialize the LLM and Agent
llm = ChatOpenAI(model="gpt-4o-mini", temperature=0, api_key=OPENAI_API_KEY)
react_agent = create_react_agent(llm, tools, prompt)
agent_executor = AgentExecutor(agent=react_agent, tools=tools, verbose=True, handle_parsing_errors=True)

# --- FastAPI Server ---
app = FastAPI(
    title="Flow Vault Manager Agent",
    description="An API for interacting with an autonomous agent that manages a prize savings protocol on Flow.",
)

class AgentRequest(BaseModel):
    command: str

@app.post("/invoke-agent")
async def invoke_agent(request: AgentRequest):
    """
    Receives a natural language command and lets the agent execute it.
    """
    try:
        # Format the tools for the prompt
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
    return {"message": "Flow Vault Manager Agent is running."}
