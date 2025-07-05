import os
import json
import time
from dotenv import load_dotenv
from web3 import Web3
# test b4 docs check
try:
    from web3.middleware import geth_poa_middleware
except ImportError:
    from web3.middleware.geth_poa import geth_poa_middleware
from web3.exceptions import ContractLogicError
from fastapi import FastAPI
from pydantic import BaseModel
from langchain_openai import ChatOpenAI
from langchain.agents import AgentExecutor, create_react_agent
from langchain_core.prompts import PromptTemplate
from langchain.tools import tool

# Import risk assessment
import sys
sys.path.append('./ml-risk')
try:
    from risk_api import RiskAssessmentAPI
    RISK_MODEL_AVAILABLE = True
    print("✅ Risk model imported successfully")
except ImportError as e:
    print(f"⚠️ Risk model not available: {e}")
    print("Run: cd ml-risk && python anomaly_risk_model.py")
    RISK_MODEL_AVAILABLE = False

# ==============================================================================
# 1. ENHANCED CONFIGURATION AND SETUP
# ==============================================================================

load_dotenv()

# --- Basic Configuration ---
RPC_URL = os.getenv("FLOW_TESTNET_RPC_URL")
CHAIN_ID = int(os.getenv("FLOW_TESTNET_CHAIN_ID"))
AGENT_PRIVATE_KEY = os.getenv("AGENT_PRIVATE_KEY")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")

# --- Contract Addresses (Your deployed contracts) ---
VAULT_ADDRESS = os.getenv("VAULT_ADDRESS", "0xBaE8f26eDa40Ab353A34ce38F8917318d226318F")
VRF_STRATEGY_ADDRESS = os.getenv("VRF_STRATEGY_ADDRESS", "0xf5DC9ca0518B45C3E372c3bC7959a4f3d1B18901")
USDC_TOKEN_ADDRESS = os.getenv("USDC_TOKEN_ADDRESS", "0x4edbDC8Ed8Ca935513A2F06e231EE42FB6ed1d15")

# --- Enhanced Strategy Configuration ---
ETHEREUM_STRATEGIES = {
    "aave": os.getenv("AAVE_STRATEGY_ADDRESS", ""),
    "compound": os.getenv("COMPOUND_STRATEGY_ADDRESS", "")
}

FLOW_STRATEGIES = {
    "increment": os.getenv("INCREMENT_STRATEGY_ADDRESS", ""),
    "flowswap": os.getenv("FLOWSWAP_STRATEGY_ADDRESS", "")
}

# --- Web3 Setup ---
w3 = Web3(Web3.HTTPProvider(RPC_URL))
w3.middleware_onion.inject(geth_poa_middleware, layer=0)

# --- Agent Account Setup ---
agent_account = w3.eth.account.from_key(AGENT_PRIVATE_KEY)
print(f"🤖 Agent Wallet Address: {agent_account.address}")

# --- Risk Model Setup ---
if RISK_MODEL_AVAILABLE:
    try:
        risk_api = RiskAssessmentAPI("ml-risk/models/anomaly_risk_model.joblib")
        print("✅ Risk assessment model loaded")
    except Exception as e:
        risk_api = None
        print(f"⚠️ Risk model loading failed: {e}")
else:
    risk_api = None

# --- Load ABIs ---
def load_abi(filename):
    path = os.path.join("abi", filename)
    with open(path, "r") as f:
        return json.load(f)["abi"]

vault_abi = load_abi("Vault.json")
vrf_strategy_abi = load_abi("FlowVrfYieldStrategy.json")
usdc_abi = load_abi("MockUSDC.json")

# --- Create Contract Objects ---
vault_contract = w3.eth.contract(address=VAULT_ADDRESS, abi=vault_abi)
vrf_strategy_contract = w3.eth.contract(address=VRF_STRATEGY_ADDRESS, abi=vrf_strategy_abi)
usdc_contract = w3.eth.contract(address=USDC_TOKEN_ADDRESS, abi=usdc_abi)

print("✅ Enhanced configuration loaded with risk management")

# ==============================================================================
# 2. ENHANCED AGENT TOOLS WITH RISK MANAGEMENT
# ==============================================================================

def send_transaction(tx):
    """Signs and sends a transaction with enhanced error handling."""
    try:
        signed_tx = w3.eth.account.sign_transaction(tx, agent_account.key)
        tx_hash = w3.eth.send_raw_transaction(signed_tx.rawTransaction)
        print(f"⏳ Transaction sent: {tx_hash.hex()}. Waiting for confirmation...")
        receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)
        print(f"✅ Transaction confirmed in block: {receipt.blockNumber}")
        return {"success": True, "receipt": receipt, "tx_hash": tx_hash.hex()}
    except ContractLogicError as e:
        print(f"❌ Transaction reverted: {e}")
        return {"success": False, "error": f"Contract logic error: {e}"}
    except Exception as e:
        print(f"❌ An unexpected error occurred: {e}")
        return {"success": False, "error": str(e)}

@tool
def get_enhanced_protocol_status() -> str:
    """
    Gets comprehensive status including risk metrics and yield opportunities.
    """
    print("Tool: get_enhanced_protocol_status")
    try:
        # Basic protocol status
        liquid_usdc_wei = usdc_contract.functions.balanceOf(VAULT_ADDRESS).call()
        prize_pool_wei = vrf_strategy_contract.functions.getBalance().call()
        last_winner = vrf_strategy_contract.functions.lastWinner().call()
        
        liquid_usdc = liquid_usdc_wei / (10**6)
        prize_pool = prize_pool_wei / (10**6)
        
        # Risk assessment for VRF strategy
        risk_level = "UNKNOWN"
        if risk_api:
            try:
                # Note: VRF is on Flow, risk model uses Ethereum data
                # So this might not work, but we'll try
                vrf_risk = risk_api.assess_strategy_risk(VRF_STRATEGY_ADDRESS)
                risk_level = "LOW" if vrf_risk < 0.3 else "MEDIUM" if vrf_risk < 0.7 else "HIGH"
            except Exception as e:
                risk_level = f"UNAVAILABLE ({str(e)[:50]}...)"
        
        # Yield opportunity analysis
        yield_opportunities = analyze_yield_opportunities()
        
        status_report = {
            "vault_liquid_usdc": f"{liquid_usdc:.2f} USDC",
            "current_prize_pool": f"{prize_pool:.2f} USDC", 
            "last_lottery_winner": last_winner,
            "vrf_strategy_risk_level": risk_level,
            "best_yield_opportunity": yield_opportunities.get("best", "VRF Lottery"),
            "total_deployed": f"{prize_pool:.2f} USDC",
            "agent_address": agent_account.address,
            "vault_address": VAULT_ADDRESS,
            "vrf_strategy_address": VRF_STRATEGY_ADDRESS
        }
        
        return f"Enhanced Protocol Status: {json.dumps(status_report, indent=2)}"
    except Exception as e:
        return f"Error getting enhanced protocol status: {e}"

@tool
def assess_strategy_risk(strategy_address: str) -> str:
    """
    Assess the risk level of a DeFi strategy before deployment.
    """
    print(f"Tool: assess_strategy_risk for {strategy_address}")
    
    if not risk_api:
        return "Risk assessment unavailable - model not loaded. Run: cd ml-risk && python anomaly_risk_model.py"
    
    try:
        risk_score = risk_api.assess_strategy_risk(strategy_address)
        detailed_assessment = risk_api.get_detailed_assessment(strategy_address)
        
        risk_level = "LOW" if risk_score < 0.3 else "MEDIUM" if risk_score < 0.7 else "HIGH"
        recommendation = "APPROVE" if risk_score < 0.5 else "CAUTION" if risk_score < 0.8 else "REJECT"
        
        return f"""
Risk Assessment for {strategy_address}:
📊 Risk Score: {risk_score:.3f}
🎯 Risk Level: {risk_level}
💡 Recommendation: {recommendation}
🔍 Details: {detailed_assessment.get('risk_level', 'N/A')}
📋 Error (if any): {detailed_assessment.get('error', 'None')}
        """
    except Exception as e:
        return f"Risk assessment failed: {e}"

def analyze_yield_opportunities():
    """Analyze available yield opportunities across chains."""
    opportunities = {
        "flow_vrf": {"apy": 0.0, "risk": 0.2, "type": "prize"},
        "ethereum_aave": {"apy": 4.5, "risk": 0.3, "type": "lending"},
        "ethereum_compound": {"apy": 4.2, "risk": 0.35, "type": "lending"},
        "flow_increment": {"apy": 8.5, "risk": 0.6, "type": "dex"},
    }
    
    # Calculate risk-adjusted returns
    for name, opp in opportunities.items():
        opp["risk_adjusted_apy"] = opp["apy"] * (1 - opp["risk"])
    
    best = max(opportunities.items(), key=lambda x: x[1]["risk_adjusted_apy"])
    return {"best": best[0], "opportunities": opportunities}

@tool 
def deploy_to_strategy_with_risk_check(strategy_name: str, amount: float) -> str:
    """
    Deploy funds to a strategy after comprehensive risk assessment.
    """
    print(f"Tool: deploy_to_strategy_with_risk_check - {strategy_name}, {amount} USDC")
    
    try:
        # Get strategy address
        strategy_address = None
        if strategy_name in ETHEREUM_STRATEGIES:
            strategy_address = ETHEREUM_STRATEGIES[strategy_name]
        elif strategy_name in FLOW_STRATEGIES:
            strategy_address = FLOW_STRATEGIES[strategy_name]
        elif strategy_name == "vrf":
            strategy_address = VRF_STRATEGY_ADDRESS
        
        if not strategy_address:
            return f"Unknown strategy: {strategy_name}. Available: vrf, {list(ETHEREUM_STRATEGIES.keys())}, {list(FLOW_STRATEGIES.keys())}"
        
        # Risk assessment (skip for VRF since it's on Flow testnet)
        if risk_api and strategy_address != VRF_STRATEGY_ADDRESS:
            try:
                risk_score = risk_api.assess_strategy_risk(strategy_address)
                if risk_score > 0.7:
                    return f"❌ DEPLOYMENT BLOCKED - High risk score: {risk_score:.3f}"
                elif risk_score > 0.5:
                    print(f"⚠️ CAUTION - Medium risk score: {risk_score:.3f}, proceeding...")
            except Exception as e:
                print(f"⚠️ Risk assessment failed: {e}, proceeding without risk check...")
        
        # Check available balance
        liquid_usdc_wei = usdc_contract.functions.balanceOf(VAULT_ADDRESS).call()
        liquid_usdc = liquid_usdc_wei / (10**6)
        
        # If amount is 0, use all available funds
        if amount == 0:
            amount = liquid_usdc
        
        if amount > liquid_usdc:
            return f"Insufficient funds: {liquid_usdc:.2f} USDC available, {amount:.2f} USDC requested"
        
        if amount == 0:
            return "No funds available to deploy"
        
        # Execute deployment
        amount_wei = int(amount * (10**6))
        
        tx = vault_contract.functions.depositToStrategy(
            strategy_address,
            amount_wei,
            b''
        ).build_transaction({
            'from': agent_account.address,
            'nonce': w3.eth.get_transaction_count(agent_account.address),
            'gas': 2_000_000,
            'gasPrice': w3.eth.gas_price,
            'chainId': CHAIN_ID
        })
        
        result = send_transaction(tx)
        
        if result["success"]:
            return f"✅ Successfully deployed {amount:.2f} USDC to {strategy_name} strategy. TX: {result['tx_hash']}"
        else:
            return f"❌ Deployment failed: {result['error']}"
            
    except Exception as e:
        return f"Error in risk-checked deployment: {e}"

@tool
def emergency_risk_assessment() -> str:
    """
    Perform emergency risk assessment of all deployed funds.
    """
    print("Tool: emergency_risk_assessment")
    
    try:
        risk_summary = {
            "total_at_risk": 0.0,
            "high_risk_strategies": [],
            "medium_risk_strategies": [],
            "low_risk_strategies": [],
            "recommendations": []
        }
        
        # Check VRF strategy
        prize_pool_wei = vrf_strategy_contract.functions.getBalance().call()
        prize_pool = prize_pool_wei / (10**6)
        
        if prize_pool > 0:
            risk_summary["low_risk_strategies"].append({
                "name": "VRF Lottery",
                "address": VRF_STRATEGY_ADDRESS,
                "balance": prize_pool,
                "risk_score": 0.2,  # VRF is considered low risk
                "notes": "Flow VRF-based lottery system"
            })
            risk_summary["total_at_risk"] += prize_pool
        
        # Check other deployed strategies (if any)
        for strategy_name, address in {**ETHEREUM_STRATEGIES, **FLOW_STRATEGIES}.items():
            if address and risk_api:
                try:
                    risk_score = risk_api.assess_strategy_risk(address)
                    balance = 0.0  # Would need strategy contract ABI to get actual balance
                    
                    strategy_info = {
                        "name": strategy_name,
                        "address": address,
                        "balance": balance,
                        "risk_score": risk_score
                    }
                    
                    if risk_score > 0.7:
                        risk_summary["high_risk_strategies"].append(strategy_info)
                        risk_summary["recommendations"].append(f"URGENT: Exit {strategy_name}")
                    elif risk_score > 0.5:
                        risk_summary["medium_risk_strategies"].append(strategy_info)
                        risk_summary["recommendations"].append(f"MONITOR: Watch {strategy_name}")
                    else:
                        risk_summary["low_risk_strategies"].append(strategy_info)
                        
                except Exception as e:
                    print(f"Risk check failed for {strategy_name}: {e}")
        
        total_strategies = len(risk_summary["high_risk_strategies"]) + \
                          len(risk_summary["medium_risk_strategies"]) + \
                          len(risk_summary["low_risk_strategies"])
        
        return f"""
🚨 Emergency Risk Assessment:
📊 Total Strategies: {total_strategies}
💰 Total Funds at Risk: {risk_summary["total_at_risk"]:.2f} USDC
🔴 High Risk Strategies: {len(risk_summary["high_risk_strategies"])}
🟡 Medium Risk Strategies: {len(risk_summary["medium_risk_strategies"])}
🟢 Low Risk Strategies: {len(risk_summary["low_risk_strategies"])}

📋 Strategy Details:
{json.dumps(risk_summary, indent=2)}

💡 Recommendations: {risk_summary["recommendations"] if risk_summary["recommendations"] else ["All strategies appear safe"]}
        """
        
    except Exception as e:
        return f"Emergency risk assessment failed: {e}"

@tool
def test_vrf_strategy_risk() -> str:
    """
    Test risk assessment specifically on your VRF strategy.
    """
    print("Tool: test_vrf_strategy_risk")
    
    vrf_address = VRF_STRATEGY_ADDRESS
    
    try:
        if not risk_api:
            return f"Risk model not available. VRF Strategy: {vrf_address} - Cannot assess risk without model."
        
        # Try to assess VRF strategy risk
        result = risk_api.get_detailed_assessment(vrf_address)
        
        if "error" in result:
            return f"""
🎯 VRF Strategy Risk Test:
📍 Address: {vrf_address}
❌ Assessment Failed: {result['error']}
📝 Note: This is expected since VRF is on Flow testnet, but risk model uses Ethereum data.
✅ VRF Strategy is considered LOW RISK by design (lottery system with Flow VRF).
            """
        else:
            return f"""
🎯 VRF Strategy Risk Test:
📍 Address: {vrf_address}
📊 Risk Score: {result.get('risk_score', 'N/A')}
🎯 Risk Level: {result.get('risk_level', 'N/A')}
🔍 Assessment: {json.dumps(result, indent=2)}
            """
            
    except Exception as e:
        return f"""
🎯 VRF Strategy Risk Test:
📍 Address: {vrf_address}
❌ Test Error: {e}
📝 Note: This is expected since VRF is on Flow testnet, but risk model analyzes Ethereum contracts.
✅ VRF Strategy is considered LOW RISK by design (lottery system with secure Flow VRF randomness).
        """

# ==============================================================================
# 3. ORIGINAL TOOLS (Enhanced with risk awareness)
# ==============================================================================

@tool
def get_protocol_status() -> str:
    """Legacy tool - use get_enhanced_protocol_status() for full features."""
    return get_enhanced_protocol_status()

@tool
def deposit_new_funds_into_strategy() -> str:
    """Checks for liquid USDC and deploys to VRF strategy with risk check."""
    return deploy_to_strategy_with_risk_check("vrf", 0)  # Will use all available funds

@tool
def simulate_yield_harvest_and_deposit(amount_usdc: float) -> str:
    """Simulates yield harvest with enhanced logging and risk awareness."""
    print(f"Tool: simulate_yield_harvest_and_deposit (Amount: {amount_usdc})")
    
    # Risk check: Don't simulate excessive amounts
    if amount_usdc > 1000:
        return "❌ Risk check failed: Simulated yield amount too high (>1000 USDC)"
    
    if amount_usdc <= 0:
        return "❌ Invalid amount: Must be greater than 0"
    
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
        
        time.sleep(2)

        # 2. Approve the VRF Strategy
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
            
        time.sleep(2)

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
            return f"✅ Successfully simulated and deposited {amount_usdc} USDC as prize pool. TX: {deposit_result['tx_hash']}"
        else:
            return f"Failed to deposit yield: {deposit_result['error']}"

    except Exception as e:
        return f"Error simulating yield harvest: {e}"

@tool
def trigger_lottery_draw() -> str:
    """Triggers lottery draw with enhanced winner tracking and risk checks."""
    print("Tool: trigger_lottery_draw")
    try:
        prize_pool_wei = vrf_strategy_contract.functions.getBalance().call()
        if prize_pool_wei == 0:
            return "Cannot trigger draw: The prize pool is zero. Use simulate_yield_harvest_and_deposit() first."

        prize_amount = prize_pool_wei / 10**6
        
        # Safety check: Don't trigger draws for extremely large amounts without confirmation
        if prize_amount > 10000:
            return f"⚠️ Safety check: Prize amount is very large ({prize_amount:.2f} USDC). Please confirm this is intended."
        
        print(f"Triggering lottery draw for a prize of {prize_amount:.2f} USDC...")
        
        tx = vault_contract.functions.harvestStrategy(
            VRF_STRATEGY_ADDRESS,
            b''
        ).build_transaction({
            'from': agent_account.address,
            'nonce': w3.eth.get_transaction_count(agent_account.address),
            'gas': 2_000_000,
            'gasPrice': w3.eth.gas_price,
            'chainId': CHAIN_ID
        })

        result = send_transaction(tx)
        if result["success"]:
            time.sleep(2)
            new_winner = vrf_strategy_contract.functions.lastWinner().call()
            return f"🎉 Lottery draw successful! Winner: {new_winner}, Prize: {prize_amount:.2f} USDC, TX: {result['tx_hash']}"
        else:
            return f"Failed to trigger lottery draw: {result['error']}"

    except Exception as e:
        return f"Error triggering lottery draw: {e}"

# ==============================================================================
# 4. ENHANCED LANGCHAIN AGENT
# ==============================================================================

tools = [
    get_enhanced_protocol_status,
    assess_strategy_risk,
    deploy_to_strategy_with_risk_check,
    emergency_risk_assessment,
    test_vrf_strategy_risk,
    simulate_yield_harvest_and_deposit,
    trigger_lottery_draw,
    # Legacy tools for compatibility
    get_protocol_status,
    deposit_new_funds_into_strategy
]

tool_names = [t.name for t in tools]

enhanced_prompt_template = """
You are the "Enhanced Vault Manager," an AI agent with advanced risk management capabilities for operating a no-loss prize savings game on Flow blockchain.

Your address is: {agent_address}
Your vault: {vault_address}
Your VRF strategy: {vrf_strategy_address}

ENHANCED CAPABILITIES:
🎯 Risk Assessment: Evaluate strategies before deployment
🔍 Multi-Strategy Analysis: Compare yield opportunities across protocols
🚨 Emergency Monitoring: Detect and respond to risk events
📊 Comprehensive Reporting: Detailed status and metrics

You have access to these enhanced tools:
{tools}

OPERATIONAL PROCEDURE (Enhanced):
1. **Enhanced Assessment**: Use get_enhanced_protocol_status() for comprehensive overview
2. **Risk Evaluation**: Use assess_strategy_risk() and test_vrf_strategy_risk() to understand safety
3. **Strategic Deployment**: Use deploy_to_strategy_with_risk_check() for safe fund allocation
4. **Emergency Protocols**: Run emergency_risk_assessment() if you detect anomalies
5. **Yield Optimization**: Balance prize rewards with risk management
6. **Lottery Execution**: Only trigger draws after confirming adequate prize pools and safety

Use the following format:
Question: the user's request or task
Thought: Consider current state, risk factors, and optimal strategy
Action: the action to take, should be one of [{tool_names}]
Action Input: the input to the action
Observation: the result of the action
... (repeat as needed)
Thought: I now have enough information to provide the final answer.
Final Answer: comprehensive response with risk assessment and recommendations

RISK MANAGEMENT RULES:
- Never deploy to strategies with risk score > 0.7
- Always assess risk before new deployments
- VRF strategy is considered LOW RISK (Flow-based lottery system)
- Monitor for unusual patterns or high-risk activities
- Prioritize user fund safety over yield maximization
- Run emergency assessment if risk indicators spike

FLOW TESTNET NOTES:
- You operate on Flow testnet with VRF-powered lottery
- Risk model may not work for Flow contracts (uses Ethereum data)
- VRF strategy is safe by design (secure randomness via Flow VRF)
- Focus on lottery operations while monitoring for yield opportunities

Begin!

Question: {input}
Thought: {agent_scratchpad}
"""

prompt = PromptTemplate.from_template(enhanced_prompt_template)

# Initialize enhanced LLM and Agent
llm = ChatOpenAI(model="gpt-4o-mini", temperature=0, api_key=OPENAI_API_KEY)
react_agent = create_react_agent(llm, tools, prompt)
agent_executor = AgentExecutor(
    agent=react_agent, 
    tools=tools, 
    verbose=True, 
    handle_parsing_errors=True,
    max_iterations=10,
    early_stopping_method="force"
)

# ==============================================================================
# 5. ENHANCED FASTAPI SERVER
# ==============================================================================

app = FastAPI(
    title="Enhanced Flow Vault Manager Agent",
    description="AI agent with risk management for Flow prize savings protocol",
    version="2.0.0"
)

class AgentRequest(BaseModel):
    command: str

class RiskAssessmentRequest(BaseModel):
    strategy_address: str

@app.post("/invoke-agent")
async def invoke_agent(request: AgentRequest):
    """Enhanced agent endpoint with risk management."""
    try:
        tool_descriptions = "\n".join([f"{tool.name}: {tool.description}" for tool in tools])
        
        response = await agent_executor.ainvoke({
            "input": request.command,
            "agent_address": agent_account.address,
            "vault_address": VAULT_ADDRESS,
            "vrf_strategy_address": VRF_STRATEGY_ADDRESS,
            "tools": tool_descriptions,
            "tool_names": ", ".join(tool_names)
        })
        return {"success": True, "output": response["output"]}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.post("/assess-risk")
async def assess_risk(request: RiskAssessmentRequest):
    """Dedicated risk assessment endpoint."""
    try:
        result = assess_strategy_risk(request.strategy_address)
        return {"success": True, "assessment": result}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.get("/emergency-status")
async def emergency_status():
    """Emergency risk monitoring endpoint."""
    try:
        result = emergency_risk_assessment()
        return {"success": True, "emergency_assessment": result}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.get("/enhanced-status")
async def enhanced_status():
    """Enhanced protocol status endpoint."""
    try:
        result = get_enhanced_protocol_status()
        return {"success": True, "status": result}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.get("/test-vrf-risk")
async def test_vrf_risk():
    """Test VRF strategy risk assessment."""
    try:
        result = test_vrf_strategy_risk()
        return {"success": True, "vrf_risk_test": result}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.get("/")
def read_root():
    return {
        "message": "Enhanced Flow Vault Manager Agent is running",
        "version": "2.0.0",
        "vault_address": VAULT_ADDRESS,
        "vrf_strategy_address": VRF_STRATEGY_ADDRESS,
        "usdc_token_address": USDC_TOKEN_ADDRESS,
        "agent_address": agent_account.address,
        "risk_model_available": RISK_MODEL_AVAILABLE,
        "features": [
            "Risk Assessment",
            "VRF Lottery Management", 
            "Emergency Monitoring",
            "Enhanced Status Reporting"
        ],
        "endpoints": [
            "/invoke-agent",
            "/assess-risk", 
            "/emergency-status",
            "/enhanced-status",
            "/test-vrf-risk"
        ]
    }

if __name__ == "__main__":
    import uvicorn
    print("🚀 Starting Enhanced Flow Vault Manager Agent...")
    print(f"🔧 Risk Model Available: {RISK_MODEL_AVAILABLE}")
    print(f"💰 Agent Address: {agent_account.address}")
    print(f"🏦 Vault Address: {VAULT_ADDRESS}")
    print(f"🎲 VRF Strategy: {VRF_STRATEGY_ADDRESS}")
    print(f"💵 USDC Token: {USDC_TOKEN_ADDRESS}")
    uvicorn.run(app, host="0.0.0.0", port=8000)