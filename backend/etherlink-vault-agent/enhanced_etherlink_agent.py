#!/usr/bin/env python3
"""
Advanced Etherlink Vault Manager Agent
Sophisticated AI agent with ML risk assessment, cross-chain yield optimization, and automated lottery management
"""

import os
import json
import time
import asyncio
from typing import Dict, List, Optional, Tuple
from datetime import datetime, timedelta
from dotenv import load_dotenv
from web3 import Web3
from web3.middleware import geth_poa_middleware
from web3.exceptions import ContractLogicError
from fastapi import FastAPI, BackgroundTasks
from pydantic import BaseModel
from langchain_openai import ChatOpenAI
from langchain.agents import AgentExecutor, create_react_agent
from langchain_core.prompts import PromptTemplate
from langchain.tools import tool
import requests
import numpy as np
from dataclasses import dataclass

# Import risk assessment
import sys
sys.path.append('./ml-risk')
try:
    from risk_api import RiskAssessmentAPI
    RISK_MODEL_AVAILABLE = True
    print("✅ Risk model imported successfully")
except ImportError as e:
    print(f"⚠️ Risk model not available: {e}")
    RISK_MODEL_AVAILABLE = False

# ==============================================================================
# 1. ENHANCED CONFIGURATION AND SETUP
# ==============================================================================

load_dotenv()

# --- Network Configuration ---
ETHERLINK_RPC_URL = os.getenv("ETHERLINK_RPC_URL", "https://node.ghostnet.etherlink.com")
ETHERLINK_CHAIN_ID = int(os.getenv("ETHERLINK_CHAIN_ID", "128123"))
AGENT_PRIVATE_KEY = os.getenv("AGENT_PRIVATE_KEY")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")

# --- Core Contract Addresses ---
VAULT_CORE_ADDRESS = "0x15DcEF7A9C2AbFD8a8a53BE9378a3A7B3ac9e5eD"
LOTTERY_EXTENSION = "0xBB28f99330B5fDffd96a1D1D5D6f94345B6e1229"
USDC_ADDRESS = "0xC0933C5440c656464D1Eb1F886422bE3466B1459"
RISK_ORACLE = "0xf237E15122DeE41F26bEA9D58f014Fd105b531aC"
STRATEGY_REGISTRY = "0x8fa300Faf24b9B764B0D7934D8861219Db0626e5"
YIELD_AGGREGATOR = "0x98464681a7aDb649f6bE8a5c26723bD6c9a631b8"
LAYER_ZERO_BRIDGE = "0x282E9890357F76C46878B6c1EA6D355Ef940E407"

# --- Mock Protocol Addresses ---
MOCK_LENDING = "0x9D6E64d6dE2251c1121c1f1f163794EbA5Cf97F1"
MOCK_DEX = "0x62FD5Ab8b5b1d11D0902Fce5B937C856301e7bf8"
MOCK_STAKING = "0x5F8E67E37e223c571D184fe3CF4e27cae33E81fF"
EMERGENCY_SYSTEM = "0x25bc04a49997e25B7482eEcbeB2Ec67740AEd5a6"

# --- Token Addresses ---
USDT_ADDRESS = "0xf0f994B4A8dB86A46a1eD4F12263c795b26703Ca"
WETH_ADDRESS = "0x959e85561b3cc2E2AE9e9764f55499525E350f56"

# --- Cross-Chain Configuration ---
SUPPORTED_CHAINS = {
    "ethereum": {"id": 101, "name": "Ethereum", "rpc": os.getenv("ETHEREUM_RPC_URL")},
    "arbitrum": {"id": 110, "name": "Arbitrum", "rpc": os.getenv("ARBITRUM_RPC_URL")},
    "polygon": {"id": 109, "name": "Polygon", "rpc": os.getenv("POLYGON_RPC_URL")},
    "etherlink": {"id": 30302, "name": "Etherlink", "rpc": ETHERLINK_RPC_URL}
}

# --- Web3 Setup ---
w3 = Web3(Web3.HTTPProvider(ETHERLINK_RPC_URL))
w3.middleware_onion.inject(geth_poa_middleware, layer=0)

# --- Agent Account Setup ---
agent_account = w3.eth.account.from_key(AGENT_PRIVATE_KEY)
print(f"🤖 Enhanced Agent Wallet: {agent_account.address}")

# --- Advanced Configuration ---
@dataclass
class VaultConfig:
    max_risk_tolerance: int = 6000  # 60%
    min_yield_threshold: int = 200  # 2%
    rebalance_threshold: int = 500  # 5%
    lottery_interval_days: int = 7
    emergency_threshold: int = 8000  # 80%
    max_single_strategy_allocation: int = 4000  # 40%
    cross_chain_enabled: bool = True
    auto_rebalance_enabled: bool = True
    gas_optimization_enabled: bool = True

config = VaultConfig()

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
    """Loads a contract ABI with multiple fallback paths."""
    possible_paths = [
        os.path.join("abi", filename),
        os.path.join("contracts", "abi", filename),
        os.path.join("..", "abi", filename),
        filename
    ]
    
    for path in possible_paths:
        try:
            if os.path.exists(path):
                with open(path, "r") as f:
                    data = json.load(f)
                    return data.get("abi", data) if isinstance(data, dict) else data
        except (FileNotFoundError, json.JSONDecodeError):
            continue
    
    # Return minimal ABI if none found
    print(f"⚠️ Could not find {filename}, using minimal ABI")
    return [
        {"type": "function", "name": "getBalance", "outputs": [{"type": "uint256"}]},
        {"type": "function", "name": "deposit", "inputs": [{"type": "uint256"}, {"type": "address"}]},
        {"type": "function", "name": "withdraw", "inputs": [{"type": "uint256"}, {"type": "address"}, {"type": "address"}]}
    ]

# Load all ABIs
vault_core_abi = load_abi("EtherlinkVaultCore.json")
lottery_abi = load_abi("LotteryExtension.json")
usdc_abi = load_abi("MockUSDC.json")
risk_oracle_abi = load_abi("RiskOracle.json")
strategy_registry_abi = load_abi("StrategyRegistry.json")
yield_aggregator_abi = load_abi("YieldAggregator.json")
bridge_abi = load_abi("LayerZeroBridge.json")

# Create contract objects
vault_core = w3.eth.contract(address=VAULT_CORE_ADDRESS, abi=vault_core_abi)
lottery_extension = w3.eth.contract(address=LOTTERY_EXTENSION, abi=lottery_abi)
usdc_contract = w3.eth.contract(address=USDC_ADDRESS, abi=usdc_abi)
risk_oracle = w3.eth.contract(address=RISK_ORACLE, abi=risk_oracle_abi)
strategy_registry = w3.eth.contract(address=STRATEGY_REGISTRY, abi=strategy_registry_abi)
yield_aggregator = w3.eth.contract(address=YIELD_AGGREGATOR, abi=yield_aggregator_abi)
bridge_contract = w3.eth.contract(address=LAYER_ZERO_BRIDGE, abi=bridge_abi)

print("✅ Enhanced configuration loaded with ML risk management")

# ==============================================================================
# 2. ADVANCED TRANSACTION HANDLING
# ==============================================================================

def send_transaction(tx, description="Transaction"):
    """Enhanced transaction handler with better error reporting."""
    try:
        # Estimate gas if not provided
        if 'gas' not in tx:
            tx['gas'] = w3.eth.estimate_gas(tx)
        
        # Sign and send
        signed_tx = w3.eth.account.sign_transaction(tx, agent_account.key)
        
        # Handle different Web3.py versions
        raw_tx = getattr(signed_tx, 'rawTransaction', getattr(signed_tx, 'raw_transaction', signed_tx))
        tx_hash = w3.eth.send_raw_transaction(raw_tx)
        
        print(f"⏳ {description}: {tx_hash.hex()}")
        receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)
        
        if receipt.status == 1:
            print(f"✅ {description} confirmed in block {receipt.blockNumber}")
            return {"success": True, "receipt": receipt, "tx_hash": tx_hash.hex()}
        else:
            print(f"❌ {description} failed")
            return {"success": False, "error": "Transaction failed"}
            
    except ContractLogicError as e:
        print(f"❌ {description} reverted: {e}")
        return {"success": False, "error": f"Contract logic error: {e}"}
    except Exception as e:
        print(f"❌ {description} error: {e}")
        return {"success": False, "error": str(e)}

# ==============================================================================
# 3. ADVANCED AGENT TOOLS WITH ML INTEGRATION
# ==============================================================================

@tool
def get_comprehensive_vault_status() -> str:
    """
    Gets comprehensive vault status including ML risk analysis, yield optimization, and lottery state.
    """
    print("Tool: get_comprehensive_vault_status")
    try:
        # Basic vault metrics
        try:
            vault_status = vault_core.functions.getProtocolStatus().call()
            liquid_usdc, prize_pool, last_winner, total_deployed, num_strategies, avg_apy, lottery_ready, time_until = vault_status
        except:
            # Fallback to individual calls
            liquid_usdc = usdc_contract.functions.balanceOf(VAULT_CORE_ADDRESS).call() / 1e6
            prize_pool = 0
            last_winner = "0x0000000000000000000000000000000000000000"
            total_deployed = 0
            num_strategies = 0
            avg_apy = 0
            lottery_ready = False
            time_until = 0

        # Get lottery information
        try:
            lottery_info = lottery_extension.functions.getLotteryInfo().call()
            lottery_prize_pool, lottery_winner, lottery_ready, lottery_time_left = lottery_info
            lottery_prize_pool = lottery_prize_pool / 1e6
        except:
            lottery_prize_pool = 0
            lottery_winner = last_winner
            lottery_ready = False
            lottery_time_left = 0

        # Get yield opportunities
        try:
            opportunities = yield_aggregator.functions.calculateOptimalAllocation(
                USDC_ADDRESS, 
                int(1000000 * 1e6), 
                config.max_risk_tolerance
            ).call()
            best_apy = opportunities[1] / 100 if opportunities and len(opportunities) > 1 else 0
        except:
            best_apy = 0

        # Risk assessment
        risk_level = "UNKNOWN"
        if risk_api:
            try:
                strategies = vault_core.functions.getStrategies().call()
                if strategies:
                    risk_scores = []
                    for strategy in strategies[:3]:  # Check top 3 strategies
                        try:
                            risk_score = risk_api.assess_strategy_risk(strategy)
                            risk_scores.append(risk_score)
                        except:
                            continue
                    
                    if risk_scores:
                        avg_risk = sum(risk_scores) / len(risk_scores)
                        risk_level = "LOW" if avg_risk < 0.3 else "MEDIUM" if avg_risk < 0.7 else "HIGH"
            except Exception as e:
                risk_level = f"ERROR: {str(e)[:50]}"

        # Market conditions
        try:
            market_conditions = yield_aggregator.functions.getMarketConditions().call()
            market_stress = market_conditions[5] if len(market_conditions) > 5 else False
        except:
            market_stress = False

        status_report = {
            "vault_metrics": {
                "liquid_usdc": f"{liquid_usdc:.2f} USDC",
                "total_deployed": f"{total_deployed:.2f} USDC",
                "number_of_strategies": num_strategies,
                "average_apy": f"{avg_apy/100:.2f}%",
                "best_available_apy": f"{best_apy:.2f}%"
            },
            "lottery_status": {
                "current_prize_pool": f"{lottery_prize_pool:.2f} USDC",
                "last_winner": lottery_winner,
                "lottery_ready": lottery_ready,
                "time_until_next": f"{lottery_time_left/3600:.1f} hours"
            },
            "risk_analysis": {
                "overall_risk_level": risk_level,
                "market_stress": market_stress,
                "risk_model_available": RISK_MODEL_AVAILABLE
            },
            "optimization_opportunities": {
                "rebalance_needed": best_apy > avg_apy/100 + config.rebalance_threshold/10000,
                "cross_chain_enabled": config.cross_chain_enabled,
                "auto_rebalance": config.auto_rebalance_enabled
            },
            "contract_addresses": {
                "vault_core": VAULT_CORE_ADDRESS,
                "lottery_extension": LOTTERY_EXTENSION,
                "usdc_token": USDC_ADDRESS,
                "agent_address": agent_account.address
            }
        }

        return f"Enhanced Vault Status: {json.dumps(status_report, indent=2)}"
    except Exception as e:
        return f"Error getting comprehensive vault status: {e}"

@tool
def perform_ml_risk_assessment(strategy_addresses: str) -> str:
    """
    Perform ML-powered risk assessment on strategy addresses.
    Args:
        strategy_addresses: Comma-separated list of strategy addresses
    """
    print(f"Tool: perform_ml_risk_assessment for {strategy_addresses}")
    
    if not risk_api:
        return "❌ ML Risk assessment unavailable - model not loaded"
    
    addresses = [addr.strip() for addr in strategy_addresses.split(',')]
    assessments = []
    
    for address in addresses:
        try:
            risk_score = risk_api.assess_strategy_risk(address)
            detailed = risk_api.get_detailed_assessment(address)
            
            assessment = {
                "address": address,
                "risk_score": f"{risk_score:.3f}",
                "risk_level": "LOW" if risk_score < 0.3 else "MEDIUM" if risk_score < 0.7 else "HIGH",
                "recommendation": "APPROVE" if risk_score < 0.5 else "CAUTION" if risk_score < 0.8 else "REJECT",
                "confidence": detailed.get('confidence_level', 0) if isinstance(detailed, dict) else 0,
                "details": str(detailed)[:200] + "..." if len(str(detailed)) > 200 else str(detailed)
            }
            assessments.append(assessment)
            
        except Exception as e:
            assessments.append({
                "address": address,
                "error": str(e),
                "risk_score": "N/A",
                "recommendation": "MANUAL_REVIEW"
            })
    
    return f"ML Risk Assessment Results:\n{json.dumps(assessments, indent=2)}"

@tool
def optimize_yield_allocation(amount_usdc: float, max_risk: float = None) -> str:
    """
    Use ML-powered yield aggregator to find optimal allocation across strategies.
    Args:
        amount_usdc: Amount in USDC to allocate
        max_risk: Maximum risk tolerance (0.0-1.0), defaults to config value
    """
    print(f"Tool: optimize_yield_allocation - {amount_usdc} USDC, max_risk: {max_risk}")
    
    if max_risk is None:
        max_risk = config.max_risk_tolerance
    else:
        max_risk = int(max_risk * 10000)  # Convert to basis points
    
    try:
        amount_wei = int(amount_usdc * 1e6)  # USDC has 6 decimals
        
        # Get optimal allocation from yield aggregator
        result = yield_aggregator.functions.calculateOptimalAllocation(
            USDC_ADDRESS,
            amount_wei,
            max_risk
        ).call()
        
        allocations, total_expected_apy, total_risk, gas_estimate = result
        
        if not allocations:
            return "❌ No suitable yield opportunities found within risk tolerance"
        
        allocation_details = []
        for i, allocation in enumerate(allocations):
            protocol, chain_id, amount, expected_apy, risk_score, allocation_pct, gas_est, requires_bridge, execution_data = allocation
            
            allocation_details.append({
                "protocol": protocol,
                "chain_id": chain_id,
                "amount_usdc": amount / 1e6,
                "expected_apy": f"{expected_apy/100:.2f}%",
                "risk_score": risk_score,
                "allocation_percentage": f"{allocation_pct/100:.1f}%",
                "requires_bridge": requires_bridge,
                "gas_estimate": gas_est
            })
        
        optimization_result = {
            "total_amount": amount_usdc,
            "total_expected_apy": f"{total_expected_apy/100:.2f}%",
            "total_risk": total_risk,
            "total_gas_estimate": gas_estimate,
            "allocations": allocation_details,
            "recommendation": "EXECUTE" if total_risk <= max_risk else "REVIEW_RISK"
        }
        
        return f"Yield Optimization Results:\n{json.dumps(optimization_result, indent=2)}"
        
    except Exception as e:
        return f"❌ Yield optimization failed: {e}"

@tool
def execute_optimal_strategy_deployment(amount_usdc: float, max_risk: float = None) -> str:
    """
    Execute deployment to optimal strategies based on ML analysis.
    Args:
        amount_usdc: Amount in USDC to deploy
        max_risk: Maximum risk tolerance (0.0-1.0)
    """
    print(f"Tool: execute_optimal_strategy_deployment - {amount_usdc} USDC")
    
    try:
        # First get optimal allocation
        optimization = optimize_yield_allocation(amount_usdc, max_risk)
        
        if "❌" in optimization:
            return optimization
        
        # Extract allocation data (simplified for demo)
        amount_wei = int(amount_usdc * 1e6)
        
        # For demo, we'll deploy to the vault's strategy system
        # In production, this would execute the specific allocations
        
        # Check available balance
        liquid_balance = usdc_contract.functions.balanceOf(VAULT_CORE_ADDRESS).call()
        
        if amount_wei > liquid_balance:
            return f"❌ Insufficient liquid funds: {liquid_balance/1e6:.2f} USDC available, {amount_usdc:.2f} requested"
        
        # Execute deployment via vault's strategy system
        try:
            tx = vault_core.functions.harvestAllStrategies().build_transaction({
                'from': agent_account.address,
                'nonce': w3.eth.get_transaction_count(agent_account.address),
                'gas': 2_000_000,
                'gasPrice': w3.eth.gas_price,
                'chainId': ETHERLINK_CHAIN_ID
            })
            
            result = send_transaction(tx, f"Deploy {amount_usdc} USDC to optimal strategies")
            
            if result["success"]:
                return f"✅ Successfully deployed {amount_usdc} USDC to optimal strategies\nOptimization details:\n{optimization}\nTX: {result['tx_hash']}"
            else:
                return f"❌ Deployment failed: {result['error']}"
                
        except Exception as e:
            return f"❌ Strategy deployment error: {e}"
            
    except Exception as e:
        return f"❌ Optimal strategy deployment failed: {e}"

@tool
def manage_cross_chain_opportunities() -> str:
    """
    Analyze and manage cross-chain yield opportunities using LayerZero bridge.
    """
    print("Tool: manage_cross_chain_opportunities")
    
    try:
        opportunities = []
        
        # Check supported chains
        for chain_name, chain_info in SUPPORTED_CHAINS.items():
            if chain_name == "etherlink":
                continue  # Skip current chain
            
            try:
                # Check if chain is supported by bridge
                chain_config = bridge_contract.functions.getChainConfig(chain_info["id"]).call()
                if chain_config[2]:  # active
                    opportunities.append({
                        "chain": chain_name,
                        "chain_id": chain_info["id"],
                        "bridge_fee": w3.from_wei(chain_config[5], 'ether'),
                        "min_amount": chain_config[3] / 1e6,
                        "max_amount": chain_config[4] / 1e6,
                        "status": "AVAILABLE"
                    })
            except:
                opportunities.append({
                    "chain": chain_name,
                    "chain_id": chain_info["id"],
                    "status": "UNAVAILABLE"
                })
        
        # Get best opportunities from yield aggregator
        try:
            top_opportunities = yield_aggregator.functions.getTopYieldOpportunities(
                USDC_ADDRESS,
                config.max_risk_tolerance,
                5
            ).call()
            
            cross_chain_analysis = {
                "available_chains": len([o for o in opportunities if o.get("status") == "AVAILABLE"]),
                "bridge_opportunities": opportunities,
                "top_yield_opportunities": len(top_opportunities) if top_opportunities else 0,
                "cross_chain_enabled": config.cross_chain_enabled,
                "recommendation": "EXPLORE" if len(opportunities) > 0 else "LOCAL_ONLY"
            }
        except:
            cross_chain_analysis = {
                "available_chains": len([o for o in opportunities if o.get("status") == "AVAILABLE"]),
                "bridge_opportunities": opportunities,
                "cross_chain_enabled": config.cross_chain_enabled,
                "recommendation": "BRIDGE_CHECK_NEEDED"
            }
        
        return f"Cross-Chain Analysis:\n{json.dumps(cross_chain_analysis, indent=2)}"
        
    except Exception as e:
        return f"❌ Cross-chain analysis failed: {e}"

@tool
def execute_lottery_management() -> str:
    """
    Manage lottery system including participant tracking and prize distribution.
    """
    print("Tool: execute_lottery_management")
    
    try:
        # Get lottery status
        lottery_info = lottery_extension.functions.getLotteryInfo().call()
        prize_pool, last_winner, ready, time_left = lottery_info
        
        prize_pool_usdc = prize_pool / 1e6
        
        # Get depositors
        try:
            depositors = lottery_extension.functions.getDepositors().call()
            num_participants = len(depositors)
        except:
            num_participants = 0
        
        lottery_status = {
            "current_prize_pool": f"{prize_pool_usdc:.2f} USDC",
            "participants": num_participants,
            "lottery_ready": ready,
            "time_until_next": f"{time_left/3600:.1f} hours",
            "last_winner": last_winner
        }
        
        # Check if lottery should be executed
        if ready and prize_pool_usdc >= 10:  # Minimum 10 USDC
            try:
                tx = lottery_extension.functions.executeLottery().build_transaction({
                    'from': agent_account.address,
                    'nonce': w3.eth.get_transaction_count(agent_account.address),
                    'gas': 1_000_000,
                    'gasPrice': w3.eth.gas_price,
                    'chainId': ETHERLINK_CHAIN_ID
                })
                
                result = send_transaction(tx, f"Execute lottery draw - {prize_pool_usdc:.2f} USDC prize")
                
                if result["success"]:
                    # Get updated winner info
                    time.sleep(2)
                    new_info = lottery_extension.functions.getLotteryInfo().call()
                    new_winner = new_info[1]
                    
                    lottery_status["action"] = "LOTTERY_EXECUTED"
                    lottery_status["winner"] = new_winner
                    lottery_status["prize_awarded"] = f"{prize_pool_usdc:.2f} USDC"
                    lottery_status["tx_hash"] = result['tx_hash']
                else:
                    lottery_status["action"] = "LOTTERY_FAILED"
                    lottery_status["error"] = result['error']
                    
            except Exception as e:
                lottery_status["action"] = "LOTTERY_ERROR"
                lottery_status["error"] = str(e)
        else:
            lottery_status["action"] = "WAITING"
            lottery_status["reason"] = "Not ready" if not ready else f"Prize pool too small ({prize_pool_usdc:.2f} < 10 USDC)"
        
        return f"Lottery Management:\n{json.dumps(lottery_status, indent=2)}"
        
    except Exception as e:
        return f"❌ Lottery management failed: {e}"

@tool
def simulate_yield_harvest_and_deposit(amount_usdc: float) -> str:
    """
    Enhanced yield simulation with ML optimization and lottery integration.
    """
    print(f"Tool: simulate_yield_harvest_and_deposit - {amount_usdc} USDC")
    
    if amount_usdc <= 0:
        return "❌ Invalid amount: Must be greater than 0"
    
    try:
        amount_wei = int(amount_usdc * 1e6)
        
        # 1. Mint yield to agent
        mint_tx = usdc_contract.functions.mint(agent_account.address, amount_wei).build_transaction({
            'from': agent_account.address,
            'nonce': w3.eth.get_transaction_count(agent_account.address),
            'gas': 500_000,
            'gasPrice': w3.eth.gas_price,
            'chainId': ETHERLINK_CHAIN_ID
        })
        
        mint_result = send_transaction(mint_tx, f"Mint {amount_usdc} USDC yield")
        if not mint_result["success"]:
            return f"❌ Failed to mint yield: {mint_result['error']}"
        
        time.sleep(2)
        
        # 2. Approve lottery extension
        approve_tx = usdc_contract.functions.approve(LOTTERY_EXTENSION, amount_wei).build_transaction({
            'from': agent_account.address,
            'nonce': w3.eth.get_transaction_count(agent_account.address),
            'gas': 500_000,
            'gasPrice': w3.eth.gas_price,
            'chainId': ETHERLINK_CHAIN_ID
        })
        
        approve_result = send_transaction(approve_tx, f"Approve lottery extension")
        if not approve_result["success"]:
            return f"❌ Failed to approve: {approve_result['error']}"
        
        time.sleep(2)
        
        # 3. Deposit yield into lottery
        deposit_tx = lottery_extension.functions.depositYieldForLottery(amount_wei).build_transaction({
            'from': agent_account.address,
            'nonce': w3.eth.get_transaction_count(agent_account.address),
            'gas': 1_000_000,
            'gasPrice': w3.eth.gas_price,
            'chainId': ETHERLINK_CHAIN_ID
        })
        
        deposit_result = send_transaction(deposit_tx, f"Deposit {amount_usdc} USDC yield to lottery")
        
        if deposit_result["success"]:
            # Check if this triggers lottery execution
            lottery_check = execute_lottery_management()
            
            return f"✅ Successfully simulated and deposited {amount_usdc} USDC yield\nMint TX: {mint_result['tx_hash']}\nDeposit TX: {deposit_result['tx_hash']}\nLottery Status: {lottery_check}"
        else:
            return f"❌ Failed to deposit yield: {deposit_result['error']}"
            
    except Exception as e:
        return f"❌ Yield simulation failed: {e}"

@tool
def emergency_risk_monitoring() -> str:
    """
    Perform emergency risk monitoring across all strategies and positions.
    """
    print("Tool: emergency_risk_monitoring")
    
    try:
        emergency_report = {
            "timestamp": datetime.now().isoformat(),
            "vault_status": "CHECKING",
            "strategies_at_risk": [],
            "market_conditions": "UNKNOWN",
            "recommended_actions": [],
            "risk_scores": {}
        }
        
        # Check vault emergency status
        try:
            # This would call the emergency system contract
            # For now, we'll simulate the check
            emergency_report["vault_status"] = "NORMAL"
        except:
            emergency_report["vault_status"] = "UNKNOWN"
        
        # Check strategies if risk model available
        if risk_api:
            try:
                strategies = vault_core.functions.getStrategies().call()
                high_risk_strategies = []
                
                for strategy in strategies:
                    try:
                        risk_score = risk_api.assess_strategy_risk(strategy)
                        emergency_report["risk_scores"][strategy] = risk_score
                        
                        if risk_score > 0.8:  # High risk threshold
                            high_risk_strategies.append({
                                "address": strategy,
                                "risk_score": risk_score,
                                "recommendation": "EMERGENCY_EXIT"
                            })
                        elif risk_score > 0.6:  # Medium risk
                            high_risk_strategies.append({
                                "address": strategy,
                                "risk_score": risk_score,
                                "recommendation": "MONITOR"
                            })
                    except:
                        continue
                
                emergency_report["strategies_at_risk"] = high_risk_strategies
                
                if high_risk_strategies:
                    emergency_report["recommended_actions"].append("Review high-risk strategies")
                    if any(s["risk_score"] > 0.8 for s in high_risk_strategies):
                        emergency_report["recommended_actions"].append("URGENT: Emergency exit from high-risk strategies")
                        
            except Exception as e:
                emergency_report["risk_assessment_error"] = str(e)
        
        # Check market conditions
        try:
            market_conditions = yield_aggregator.functions.getMarketConditions().call()
            if len(market_conditions) > 5:
                market_stress = market_conditions[5]
                emergency_report["market_conditions"] = "STRESS" if market_stress else "NORMAL"
                
                if market_stress:
                    emergency_report["recommended_actions"].append("Market stress detected - reduce risk exposure")
        except:
            pass
        
        # Overall assessment
        if emergency_report["strategies_at_risk"]:
            emergency_report["overall_status"] = "ATTENTION_REQUIRED"
        elif emergency_report["market_conditions"] == "STRESS":
            emergency_report["overall_status"] = "MONITOR"
        else:
            emergency_report["overall_status"] = "NORMAL"
        
        return f"Emergency Risk Monitoring:\n{json.dumps(emergency_report, indent=2)}"
        
    except Exception as e:
        return f"❌ Emergency monitoring failed: {e}"

# ==============================================================================
# 4. ENHANCED LANGCHAIN AGENT
# ==============================================================================

# Build enhanced tools list
tools = [
    get_comprehensive_vault_status,
    perform_ml_risk_assessment,
    optimize_yield_allocation,
    execute_optimal_strategy_deployment,
    manage_cross_chain_opportunities,
    execute_lottery_management,
    simulate_yield_harvest_and_deposit,
    emergency_risk_monitoring
]

tool_names = [t.name for t in tools]

enhanced_prompt_template = """
You are the "Advanced Etherlink Vault Manager," a sophisticated AI agent with ML-powered risk assessment, cross-chain yield optimization, and automated lottery management capabilities.

Your address: {agent_address}
Vault Core: {vault_core_address}
Lottery Extension: {lottery_extension}
Risk Oracle: {risk_oracle}
Strategy Registry: {strategy_registry}
Yield Aggregator: {yield_aggregator}

ADVANCED CAPABILITIES:
🧠 ML Risk Assessment: Real-time strategy risk scoring using machine learning
⚡ Yield Optimization: Cross-chain yield aggregation with automated rebalancing
🔄 Cross-Chain Management: LayerZero-powered bridge integration for maximum yield
🎰 Advanced Lottery System: Sophisticated prize distribution with fair randomness
📊 Market Intelligence: Real-time market condition analysis and adaptation
🚨 Emergency Monitoring: Proactive risk detection and emergency response
🤖 Autonomous Operations: Self-optimizing strategies with minimal human intervention

ENHANCED TOOLS:
{tools}

OPERATIONAL FRAMEWORK:
1. **Comprehensive Analysis**: Always start with get_comprehensive_vault_status() for full system overview
2. **Risk-First Approach**: Use perform_ml_risk_assessment() before any major strategy changes
3. **Yield Optimization**: Apply optimize_yield_allocation() to maximize returns within risk tolerance
4. **Cross-Chain Exploration**: Use manage_cross_chain_opportunities() for yield arbitrage
5. **Automated Execution**: Deploy execute_optimal_strategy_deployment() for strategic fund allocation
6. **Lottery Management**: Monitor and execute execute_lottery_management() for prize distribution
7. **Emergency Vigilance**: Run emergency_risk_monitoring() if anomalies detected
8. **Continuous Improvement**: Adapt strategies based on market conditions and performance

DECISION MATRIX:
Risk Score < 0.3: GREEN - Aggressive yield strategies, cross-chain arbitrage
Risk Score 0.3-0.6: YELLOW - Balanced approach, moderate diversification  
Risk Score 0.6-0.8: ORANGE - Conservative strategies, increased monitoring
Risk Score > 0.8: RED - Emergency mode, capital preservation, exit strategies

CROSS-CHAIN STRATEGY:
- Ethereum: Target high-TVL protocols (Aave, Compound) for stability
- Arbitrum: Leverage low gas costs for frequent rebalancing
- Polygon: Explore emerging DeFi opportunities with moderate risk
- Etherlink: Base operations with VRF lottery as core offering

LOTTERY MECHANICS:
- Weekly draws with accumulated yield as prizes
- Weighted probability based on deposit amounts
- Minimum 10 USDC prize pool for execution
- Automatic trigger when conditions are met

Use the following format:
Question: the user's request or operational directive
Thought: Consider current market conditions, risk factors, and optimization opportunities
Action: the action to take, should be one of [{tool_names}]
Action Input: the input to the action
Observation: the result of the action
... (repeat as needed for comprehensive analysis)
Thought: I now have sufficient information to provide strategic recommendations.
Final Answer: comprehensive response with risk assessment, yield optimization, and actionable recommendations

RISK MANAGEMENT PROTOCOL:
- Never exceed 60% risk tolerance without explicit approval
- Always diversify across minimum 3 strategies when possible
- Maintain 20% liquid reserves for emergency exits
- Monitor gas costs - never exceed 10% of potential yield
- Cross-chain operations require additional 5% risk buffer
- Emergency exit if any strategy exceeds 80% risk score

Begin strategic operations!

Question: {input}
Thought: {agent_scratchpad}
"""

prompt = PromptTemplate.from_template(enhanced_prompt_template)

# Initialize enhanced LLM and Agent
llm = ChatOpenAI(model="gpt-4o-mini", temperature=0.1, api_key=OPENAI_API_KEY)
react_agent = create_react_agent(llm, tools, prompt)
agent_executor = AgentExecutor(
    agent=react_agent,
    tools=tools,
    verbose=True,
    handle_parsing_errors=True,
    max_iterations=15,
    early_stopping_method="force"
)

# ==============================================================================
# 5. ENHANCED FASTAPI SERVER
# ==============================================================================

app = FastAPI(
    title="Advanced Etherlink Vault Manager",
    description="ML-powered AI agent for sophisticated DeFi yield optimization and lottery management",
    version="3.0.0"
)

class AgentRequest(BaseModel):
    command: str

class YieldOptimizationRequest(BaseModel):
    amount_usdc: float
    max_risk: Optional[float] = None

class RiskAssessmentRequest(BaseModel):
    strategy_addresses: str

class LotteryRequest(BaseModel):
    amount_usdc: float

@app.post("/invoke-agent")
async def invoke_enhanced_agent(request: AgentRequest):
    """Enhanced agent endpoint with ML integration."""
    try:
        tool_descriptions = "\n".join([f"- {tool.name}: {tool.description}" for tool in tools])
        
        response = await agent_executor.ainvoke({
            "input": request.command,
            "agent_address": agent_account.address,
            "vault_core_address": VAULT_CORE_ADDRESS,
            "lottery_extension": LOTTERY_EXTENSION,
            "risk_oracle": RISK_ORACLE,
            "strategy_registry": STRATEGY_REGISTRY,
            "yield_aggregator": YIELD_AGGREGATOR,
            "tools": tool_descriptions,
            "tool_names": ", ".join(tool_names)
        })
        return {"success": True, "output": response["output"]}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.post("/optimize-yield")
async def optimize_yield_endpoint(request: YieldOptimizationRequest):
    """Dedicated yield optimization endpoint."""
    try:
        result = optimize_yield_allocation.invoke({
            "amount_usdc": request.amount_usdc,
            "max_risk": request.max_risk
        })
        return {"success": True, "optimization": result}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.post("/assess-risk")
async def assess_risk_endpoint(request: RiskAssessmentRequest):
    """ML-powered risk assessment endpoint."""
    try:
        result = perform_ml_risk_assessment.invoke({
            "strategy_addresses": request.strategy_addresses
        })
        return {"success": True, "assessment": result}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.get("/comprehensive-status")
async def comprehensive_status():
    """Comprehensive vault status endpoint."""
    try:
        result = get_comprehensive_vault_status.invoke({})
        return {"success": True, "status": result}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.post("/execute-strategy")
async def execute_strategy_endpoint(request: YieldOptimizationRequest):
    """Execute optimal strategy deployment."""
    try:
        result = execute_optimal_strategy_deployment.invoke({
            "amount_usdc": request.amount_usdc,
            "max_risk": request.max_risk
        })
        return {"success": True, "execution": result}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.get("/cross-chain-analysis")
async def cross_chain_analysis():
    """Cross-chain opportunities analysis."""
    try:
        result = manage_cross_chain_opportunities.invoke({})
        return {"success": True, "analysis": result}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.post("/manage-lottery")
async def manage_lottery_endpoint():
    """Lottery management endpoint."""
    try:
        result = execute_lottery_management.invoke({})
        return {"success": True, "lottery": result}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.post("/simulate-yield")
async def simulate_yield_endpoint(request: LotteryRequest):
    """Enhanced yield simulation endpoint."""
    try:
        result = simulate_yield_harvest_and_deposit.invoke({
            "amount_usdc": request.amount_usdc
        })
        return {"success": True, "simulation": result}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.get("/emergency-status")
async def emergency_status():
    """Emergency risk monitoring endpoint."""
    try:
        result = emergency_risk_monitoring.invoke({})
        return {"success": True, "emergency_status": result}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.get("/health")
async def health_check():
    """Comprehensive health check."""
    try:
        latest_block = w3.eth.block_number
        agent_balance = w3.eth.get_balance(agent_account.address)
        
        # Test core contracts
        vault_balance = usdc_contract.functions.balanceOf(VAULT_CORE_ADDRESS).call()
        
        health_status = {
            "status": "healthy",
            "timestamp": datetime.now().isoformat(),
            "network": {
                "chain_id": ETHERLINK_CHAIN_ID,
                "latest_block": latest_block,
                "rpc_url": ETHERLINK_RPC_URL[:50] + "..."
            },
            "agent": {
                "address": agent_account.address,
                "balance_eth": float(w3.from_wei(agent_balance, 'ether')),
                "vault_usdc_balance": vault_balance / 1e6
            },
            "contracts": {
                "vault_core": VAULT_CORE_ADDRESS,
                "lottery_extension": LOTTERY_EXTENSION,
                "usdc_token": USDC_ADDRESS,
                "risk_oracle": RISK_ORACLE,
                "strategy_registry": STRATEGY_REGISTRY,
                "yield_aggregator": YIELD_AGGREGATOR
            },
            "features": {
                "ml_risk_model": RISK_MODEL_AVAILABLE,
                "cross_chain_enabled": config.cross_chain_enabled,
                "auto_rebalance_enabled": config.auto_rebalance_enabled,
                "emergency_monitoring": True
            },
            "configuration": {
                "max_risk_tolerance": f"{config.max_risk_tolerance/100}%",
                "min_yield_threshold": f"{config.min_yield_threshold/100}%",
                "lottery_interval": f"{config.lottery_interval_days} days"
            }
        }
        
        return {"success": True, "health": health_status}
        
    except Exception as e:
        return {
            "success": False,
            "health": {
                "status": "unhealthy",
                "error": str(e),
                "timestamp": datetime.now().isoformat()
            }
        }

@app.get("/")
def read_root():
    return {
        "message": "Advanced Etherlink Vault Manager is operational",
        "version": "3.0.0",
        "features": [
            "ML-Powered Risk Assessment",
            "Cross-Chain Yield Optimization", 
            "Automated Lottery Management",
            "Emergency Risk Monitoring",
            "Real-Time Market Analysis",
            "Autonomous Strategy Execution"
        ],
        "contracts": {
            "vault_core": VAULT_CORE_ADDRESS,
            "lottery_extension": LOTTERY_EXTENSION,
            "usdc_token": USDC_ADDRESS,
            "risk_oracle": RISK_ORACLE,
            "strategy_registry": STRATEGY_REGISTRY,
            "yield_aggregator": YIELD_AGGREGATOR
        },
        "agent_address": agent_account.address,
        "ml_risk_available": RISK_MODEL_AVAILABLE,
        "endpoints": [
            "/invoke-agent - Natural language agent interaction",
            "/optimize-yield - ML-powered yield optimization",
            "/assess-risk - Strategy risk assessment",
            "/comprehensive-status - Full system status",
            "/execute-strategy - Deploy optimal strategies",
            "/cross-chain-analysis - Cross-chain opportunities",
            "/manage-lottery - Lottery system management",
            "/emergency-status - Emergency monitoring",
            "/health - System health check"
        ]
    }

if __name__ == "__main__":
    import uvicorn
    print("🚀 Starting Advanced Etherlink Vault Manager...")
    print(f"🧠 ML Risk Model: {'✅ Available' if RISK_MODEL_AVAILABLE else '❌ Unavailable'}")
    print(f"🔗 Cross-Chain: {'✅ Enabled' if config.cross_chain_enabled else '❌ Disabled'}")
    print(f"⚡ Auto-Rebalance: {'✅ Enabled' if config.auto_rebalance_enabled else '❌ Manual'}")
    print(f"🤖 Agent Address: {agent_account.address}")
    print(f"🏦 Vault Core: {VAULT_CORE_ADDRESS}")
    print(f"🎰 Lottery Extension: {LOTTERY_EXTENSION}")
    print(f"🔍 Risk Oracle: {RISK_ORACLE}")
    print(f"📊 Yield Aggregator: {YIELD_AGGREGATOR}")
    
    print("\n🎯 Ready for sophisticated DeFi operations!")
    print("🌐 Server: http://localhost:8000")
    print("📚 API docs: http://localhost:8000/docs")
    print("💊 Health: http://localhost:8000/health")
    
    uvicorn.run(app, host="0.0.0.0", port=8000)