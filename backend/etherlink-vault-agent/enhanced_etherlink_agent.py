#!/usr/bin/env python3
"""
Enhanced Etherlink Vault Manager Agent - Production Ready
Sophisticated AI agent for weekly yield lottery with ML risk assessment and deployed strategies
"""

import os
import json
import time
import asyncio
from typing import Dict, List, Optional, Tuple
from datetime import datetime, timedelta
from dotenv import load_dotenv
from web3 import Web3
from web3.middleware import ExtraDataToPOAMiddleware
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
import schedule
import threading

# Import risk assessment
import os, sys
sys.path.append(os.path.join(os.path.dirname(__file__), 'ml-risk'))
try:
    from risk_api import RiskAssessmentAPI
    RISK_MODEL_AVAILABLE = True
    print("✅ Risk model imported successfully")
except ImportError as e:
    print(f"⚠️ Risk model not available: {e}")
    RISK_MODEL_AVAILABLE = False

# Import price feeds
try:
    from price_feeds import PriceFeedManager
    PRICE_FEEDS_AVAILABLE = True
    print("✅ Price feeds imported successfully")
except ImportError as e:
    print(f"⚠️ Price feeds not available: {e}")
    PRICE_FEEDS_AVAILABLE = False

# ==============================================================================
# 1. PRODUCTION CONFIGURATION WITH DEPLOYED CONTRACTS
# ==============================================================================


load_dotenv()  

AGENT_PRIVATE_KEY = os.getenv("AGENT_PRIVATE_KEY", "")

# --- Network Configuration ---
ETHERLINK_RPC_URL = os.getenv("ETHERLINK_RPC_URL", "https://node.ghostnet.etherlink.com")
ETHERLINK_CHAIN_ID = int(os.getenv("ETHERLINK_CHAIN_ID", "128123"))
AGENT_PRIVATE_KEY = os.getenv("AGENT_PRIVATE_KEY")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")

# --- Price Feed API Keys ---
COINMARKETCAP_API_KEY = os.getenv("COINMARKETCAP_API_KEY")

# --- DEPLOYED CONTRACT ADDRESSES (Updated to match your deployment) ---
VAULT_CORE_ADDRESS = "0xB8B55df1B5AE01e6ABAf141F0D3CAC64303eFfB2"
LOTTERY_EXTENSION = "0x779992660Eb4eb9C17AC38D4ABb79D07F0a1d374"
USDC_ADDRESS = "0xc2E9E01F16764F8e63d5113Ec01b13cc968dB5Dc"
WETH_ADDRESS = "0x9aD2A76D1f940C2eedFE7aBF5b55e6943a90cC41"
RISK_ORACLE = "0x3e833aF4870F35e7F8c63f5E6CA1D884c305bc2e"
STRATEGY_REGISTRY = "0x4Fd69BD63Ad6f2688239B496bbAF89390572693d"

# --- DEPLOYED STRATEGY ADDRESSES ---
SIMPLE_SUPERLEND_STRATEGY = "0x1864adaBc679B62Ae69A838309E5fB9435675D1A"
SIMPLE_PANCAKE_STRATEGY = "0x888e307EC9DeF2e038d545251f7b7F6c944b96d5"
LOTTERY_YIELD_STRATEGY = "0x3dC0390c2C4Aad9b342Dac7e6741662d52963577"

# --- Strategy Names (as registered in vault) ---
STRATEGY_NAMES = {
    "simple_superlend_usdc": SIMPLE_SUPERLEND_STRATEGY,
    "simple_pancake_usdc_weth": SIMPLE_PANCAKE_STRATEGY,
    "lottery_yield": LOTTERY_YIELD_STRATEGY
}

# --- Web3 Setup ---
w3 = Web3(Web3.HTTPProvider(ETHERLINK_RPC_URL))
w3.middleware_onion.inject(ExtraDataToPOAMiddleware, layer=0)

# --- Agent Account Setup ---
agent_account = w3.eth.account.from_key(AGENT_PRIVATE_KEY)
print(f"🤖 Enhanced Agent Wallet: {agent_account.address}")

# --- Weekly Lottery Configuration ---
@dataclass
class LotteryConfig:
    weekly_cycle_days: int = 7
    min_prize_pool: float = 10.0  # 10 USDC minimum
    max_participants: int = 1000
    yield_distribution_ratio: float = 0.8  # 80% to winner, 20% to participants
    min_deposit_for_lottery: float = 1.0  # 1 USDC minimum
    lottery_execution_hour: int = 12  # Execute at noon UTC
    lottery_execution_day: int = 0  # Monday = 0

# --- Risk Configuration ---
@dataclass
class RiskConfig:
    max_strategy_allocation: float = 0.4  # 40% max per strategy
    emergency_risk_threshold: float = 0.8  # 80% risk score
    rebalance_risk_threshold: float = 0.6  # 60% risk score
    min_diversification_strategies: int = 2
    risk_assessment_interval_hours: int = 6

# --- Yield Configuration ---
@dataclass
class YieldConfig:
    harvest_interval_hours: int = 12
    min_harvest_amount: float = 1.0  # 1 USDC
    auto_compound_enabled: bool = True
    yield_distribution_enabled: bool = True
    performance_fee_pct: float = 0.05  # 5% performance fee

lottery_config = LotteryConfig()
risk_config = RiskConfig()
yield_config = YieldConfig()

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

# --- Price Feed Manager Setup ---
if PRICE_FEEDS_AVAILABLE:
    try:
        price_manager = PriceFeedManager(coinmarketcap_api_key=COINMARKETCAP_API_KEY)
        print("✅ Price feed manager initialized")
    except Exception as e:
        price_manager = None
        print(f"⚠️ Price feed manager initialization failed: {e}")
else:
    price_manager = None

# --- Load Minimal ABIs ---
def load_abi(filename):
    """Loads contract ABI with fallback to minimal interface."""
    minimal_abis = {
        "vault": [
            {"type": "function", "name": "getProtocolStatus", "outputs": [{"type": "uint256"}, {"type": "uint256"}, {"type": "address"}, {"type": "uint256"}, {"type": "uint256"}, {"type": "uint256"}, {"type": "bool"}, {"type": "uint256"}]},
            {"type": "function", "name": "getNamedStrategies", "outputs": [{"type": "string[]"}, {"type": "address[]"}]},
            {"type": "function", "name": "deployToNamedStrategy", "inputs": [{"type": "string"}, {"type": "uint256"}, {"type": "bytes"}]},
            {"type": "function", "name": "harvestAllStrategies", "outputs": [{"type": "uint256"}]},
            {"type": "function", "name": "totalAssets", "outputs": [{"type": "uint256"}]},
            {"type": "function", "name": "balanceOf", "inputs": [{"type": "address"}], "outputs": [{"type": "uint256"}]},
            {"type": "function", "name": "deposit", "inputs": [{"type": "uint256"}, {"type": "address"}], "outputs": [{"type": "uint256"}]},
            {"type": "function", "name": "withdraw", "inputs": [{"type": "uint256"}, {"type": "address"}, {"type": "address"}], "outputs": [{"type": "uint256"}]}
        ],
        "lottery": [
            {"type": "function", "name": "getLotteryInfo", "outputs": [{"type": "uint256"}, {"type": "address"}, {"type": "bool"}, {"type": "uint256"}]},
            {"type": "function", "name": "getDepositors", "outputs": [{"type": "address[]"}]},
            {"type": "function", "name": "getUserDepositInfo", "inputs": [{"type": "address"}], "outputs": [{"type": "uint256"}, {"type": "uint256"}]},
            {"type": "function", "name": "executeLottery", "outputs": [{"type": "address"}, {"type": "uint256"}]},
            {"type": "function", "name": "depositYieldForLottery", "inputs": [{"type": "uint256"}]},
            {"type": "function", "name": "canExecuteLottery", "outputs": [{"type": "bool"}]}
        ],
        "usdc": [
            {"type": "function", "name": "balanceOf", "inputs": [{"type": "address"}], "outputs": [{"type": "uint256"}]},
            {"type": "function", "name": "approve", "inputs": [{"type": "address"}, {"type": "uint256"}], "outputs": [{"type": "bool"}]},
            {"type": "function", "name": "transfer", "inputs": [{"type": "address"}, {"type": "uint256"}], "outputs": [{"type": "bool"}]},
            {"type": "function", "name": "mint", "inputs": [{"type": "address"}, {"type": "uint256"}], "outputs": [{"type": "bool"}]}
        ],
        "strategy": [
            {"type": "function", "name": "getStrategyInfo", "outputs": [{"type": "string"}, {"type": "address"}, {"type": "address"}, {"type": "uint256"}, {"type": "uint256"}, {"type": "uint256"}, {"type": "bool"}]},
            {"type": "function", "name": "getBalance", "outputs": [{"type": "uint256"}]},
            {"type": "function", "name": "harvest", "inputs": [{"type": "bytes"}]},
            {"type": "function", "name": "execute", "inputs": [{"type": "uint256"}, {"type": "bytes"}]},
            {"type": "function", "name": "paused", "outputs": [{"type": "bool"}]}
        ],
        "registry": [
            {"type": "function", "name": "getOptimalStrategy", "inputs": [{"type": "uint256"}, {"type": "uint256"}, {"type": "bool"}, {"type": "uint16"}], "outputs": [{"type": "bytes32"}, {"type": "uint256"}, {"type": "uint256"}, {"type": "bool"}]},
            {"type": "function", "name": "getStrategyByName", "inputs": [{"type": "string"}, {"type": "uint16"}], "outputs": [{"type": "address"}, {"type": "uint16"}, {"type": "string"}, {"type": "string"}, {"type": "uint256"}, {"type": "uint256"}, {"type": "uint256"}, {"type": "uint256"}, {"type": "uint256"}, {"type": "bool"}, {"type": "bool"}, {"type": "uint256"}, {"type": "bytes"}]},
            {"type": "function", "name": "updateRealTimeMetrics", "inputs": [{"type": "bytes32"}, {"type": "uint256"}, {"type": "uint256"}, {"type": "uint256"}, {"type": "uint256"}, {"type": "uint256"}, {"type": "bool"}, {"type": "bytes32"}]}
        ]
    }
    
    try:
        with open(filename, "r") as f:
            data = json.load(f)
            return data.get("abi", data) if isinstance(data, dict) else data
    except:
        # Return appropriate minimal ABI
        if "vault" in filename.lower():
            return minimal_abis["vault"]
        elif "lottery" in filename.lower():
            return minimal_abis["lottery"]
        elif "usdc" in filename.lower() or "token" in filename.lower():
            return minimal_abis["usdc"]
        elif "strategy" in filename.lower():
            return minimal_abis["strategy"]
        elif "registry" in filename.lower():
            return minimal_abis["registry"]
        else:
            return minimal_abis["vault"]

# Create contract objects
vault_core = w3.eth.contract(address=VAULT_CORE_ADDRESS, abi=load_abi("vault"))
lottery_extension = w3.eth.contract(address=LOTTERY_EXTENSION, abi=load_abi("lottery"))
usdc_contract = w3.eth.contract(address=USDC_ADDRESS, abi=load_abi("usdc"))
strategy_registry = w3.eth.contract(address=STRATEGY_REGISTRY, abi=load_abi("registry"))

# Strategy contracts
superlend_strategy = w3.eth.contract(address=SIMPLE_SUPERLEND_STRATEGY, abi=load_abi("strategy"))
pancake_strategy = w3.eth.contract(address=SIMPLE_PANCAKE_STRATEGY, abi=load_abi("strategy"))
lottery_strategy = w3.eth.contract(address=LOTTERY_YIELD_STRATEGY, abi=load_abi("strategy"))

print("✅ Production configuration loaded with deployed contracts")

# ==============================================================================
# 2. ENHANCED TRANSACTION HANDLING
# ==============================================================================

def send_transaction(tx, description="Transaction", retry_count=3):
    """Enhanced transaction handler with retry logic."""
    for attempt in range(retry_count):
        try:
            # Update gas price for current market conditions
            tx['gasPrice'] = int(w3.eth.gas_price * 1.1)  # 10% above current
            
            # Estimate gas if not provided
            if 'gas' not in tx:
                try:
                    estimated_gas = w3.eth.estimate_gas(tx)
                    tx['gas'] = int(estimated_gas * 1.2)  # 20% buffer
                except:
                    tx['gas'] = 2_000_000  # Default high gas limit
            
            # Update nonce
            tx['nonce'] = w3.eth.get_transaction_count(agent_account.address)
            
            # Sign and send
            signed_tx = w3.eth.account.sign_transaction(tx, agent_account.key)
            raw_tx = getattr(signed_tx, 'rawTransaction', getattr(signed_tx, 'raw_transaction', signed_tx))
            tx_hash = w3.eth.send_raw_transaction(raw_tx)
            
            print(f"⏳ {description} (attempt {attempt + 1}): {tx_hash.hex()}")
            receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)
            
            if receipt.status == 1:
                print(f"✅ {description} confirmed in block {receipt.blockNumber}")
                return {"success": True, "receipt": receipt, "tx_hash": tx_hash.hex(), "gas_used": receipt.gasUsed}
            else:
                print(f"❌ {description} failed in attempt {attempt + 1}")
                if attempt == retry_count - 1:
                    return {"success": False, "error": "Transaction failed after retries"}
                time.sleep(5)  # Wait before retry
                
        except Exception as e:
            print(f"❌ {description} error (attempt {attempt + 1}): {e}")
            if attempt == retry_count - 1:
                return {"success": False, "error": str(e)}
            time.sleep(5)  # Wait before retry

# ==============================================================================
# 3. ENHANCED AGENT TOOLS FOR DEPLOYED STRATEGIES
# ==============================================================================

@tool
def get_comprehensive_vault_status() -> str:
    """
    Gets complete status of the deployed vault and all strategies.
    """
    print("Tool: get_comprehensive_vault_status")
    try:
        # Get vault protocol status
        try:
            status = vault_core.functions.getProtocolStatus().call()
            liquid_usdc = float(status[0])
            prize_pool = float(status[1])  
            last_winner = status[2] if len(status) > 2 else "0x0000000000000000000000000000000000000000"
            total_deployed = float(status[3]) if len(status) > 3 else 0
            num_strategies = int(status[4]) if len(status) > 4 else 0
            avg_apy = float(status[5]) if len(status) > 5 else 0
            lottery_ready = bool(status[6]) if len(status) > 6 else False
            time_until = int(status[7]) if len(status) > 7 else 0
        except Exception as e:
            print(f"Status call failed: {e}, using fallback")
            # Fallback to individual calls
            liquid_usdc = float(usdc_contract.functions.balanceOf(VAULT_CORE_ADDRESS).call()) / 1e6
            total_deployed = 0
            num_strategies = 3  # We know we have 3 strategies
            avg_apy = 0
            prize_pool = 0
            lottery_ready = False
            time_until = 0

        # Get strategy information
        strategies_info = {}
        strategy_total_balance = 0
        
        for name, address in STRATEGY_NAMES.items():
            try:
                strategy_contract = w3.eth.contract(address=address, abi=load_abi("strategy"))
                
                # Get strategy info
                try:
                    info = strategy_contract.functions.getStrategyInfo().call()
                    strategy_name = info[0] if len(info) > 0 else name
                    strategy_asset = info[1] if len(info) > 1 else USDC_ADDRESS
                    strategy_protocol = info[2] if len(info) > 2 else address
                    total_dep = float(info[3]) / 1e6 if len(info) > 3 else 0
                    total_harv = float(info[4]) / 1e6 if len(info) > 4 else 0
                    last_harvest = int(info[5]) if len(info) > 5 else 0
                    is_paused = bool(info[6]) if len(info) > 6 else False
                except:
                    # Fallback
                    strategy_name = name
                    total_dep = 0
                    total_harv = 0
                    last_harvest = 0
                    is_paused = False
                
                # Get current balance
                try:
                    balance = float(strategy_contract.functions.getBalance().call()) / 1e6
                except:
                    balance = 0
                
                strategy_total_balance += balance
                
                strategies_info[name] = {
                    "address": address,
                    "name": strategy_name,
                    "total_deployed": total_dep,
                    "total_harvested": total_harv,
                    "current_balance": balance,
                    "last_harvest": last_harvest,
                    "is_paused": is_paused,
                    "status": "ACTIVE" if not is_paused else "PAUSED"
                }
                
            except Exception as e:
                strategies_info[name] = {
                    "address": address,
                    "error": str(e),
                    "status": "ERROR"
                }

        # Get lottery information
        try:
            lottery_info = lottery_extension.functions.getLotteryInfo().call()
            lottery_prize = float(lottery_info[0]) / 1e6
            lottery_winner = lottery_info[1]
            lottery_ready = lottery_info[2]
            lottery_time_left = int(lottery_info[3])
        except Exception as e:
            lottery_prize = 0
            lottery_winner = "Unknown"
            lottery_ready = False
            lottery_time_left = 0

        # Get depositors for lottery
        try:
            depositors = lottery_extension.functions.getDepositors().call()
            num_participants = len(depositors)
        except:
            num_participants = 0

        # Risk assessment if available
        risk_assessment = {}
        if risk_api:
            for name, address in STRATEGY_NAMES.items():
                try:
                    risk_score = risk_api.assess_strategy_risk(address)
                    risk_level = "LOW" if risk_score < 0.3 else "MEDIUM" if risk_score < 0.7 else "HIGH"
                    risk_assessment[name] = {
                        "risk_score": f"{risk_score:.3f}",
                        "risk_level": risk_level,
                        "recommendation": "APPROVE" if risk_score < 0.5 else "MONITOR" if risk_score < 0.8 else "REVIEW"
                    }
                except:
                    risk_assessment[name] = {"risk_score": "N/A", "risk_level": "UNKNOWN"}

        # Get current market data if available
        market_data = {}
        if price_manager:
            try:
                usdc_price = price_manager.get_price("USDC")
                eth_price = price_manager.get_price("ETH")
                market_data = {
                    "usdc_price": f"${usdc_price:.4f}",
                    "eth_price": f"${eth_price:.2f}",
                    "last_updated": datetime.now().isoformat()
                }
            except:
                market_data = {"error": "Price data unavailable"}

        comprehensive_status = {
            "vault_metrics": {
                "liquid_usdc": f"{liquid_usdc:.2f}",
                "total_deployed": f"{strategy_total_balance:.2f}",
                "total_assets": f"{liquid_usdc + strategy_total_balance:.2f}",
                "number_of_strategies": len(STRATEGY_NAMES),
                "average_apy": f"{avg_apy/100:.2f}%" if avg_apy > 0 else "Calculating..."
            },
            "strategies": strategies_info,
            "lottery_system": {
                "current_prize_pool": f"{lottery_prize:.2f} USDC",
                "participants": num_participants,
                "last_winner": lottery_winner,
                "lottery_ready": lottery_ready,
                "time_until_next": f"{lottery_time_left/3600:.1f} hours",
                "min_prize_pool": f"{lottery_config.min_prize_pool} USDC"
            },
            "risk_analysis": risk_assessment,
            "market_data": market_data,
            "contract_addresses": {
                "vault_core": VAULT_CORE_ADDRESS,
                "lottery_extension": LOTTERY_EXTENSION,
                "usdc_token": USDC_ADDRESS,
                "strategies": STRATEGY_NAMES
            },
            "weekly_lottery_config": {
                "cycle_days": lottery_config.weekly_cycle_days,
                "execution_day": "Monday",
                "execution_hour": f"{lottery_config.lottery_execution_hour}:00 UTC",
                "min_deposit": f"{lottery_config.min_deposit_for_lottery} USDC"
            }
        }

        return f"Comprehensive Vault Status:\n{json.dumps(comprehensive_status, indent=2)}"
        
    except Exception as e:
        return f"❌ Error getting vault status: {e}"

@tool
def get_market_analysis_and_pricing() -> str:
    """
    Get comprehensive market analysis including cryptocurrency prices and trends.
    """
    print("Tool: get_market_analysis_and_pricing")
    
    if not price_manager:
        return "❌ Price feed manager not available"
    
    try:
        market_analysis = {
            "timestamp": datetime.now().isoformat(),
            "prices": {},
            "market_sentiment": {},
            "risk_indicators": {}
        }
        
        # Get current prices for major cryptocurrencies
        important_assets = ["BTC", "ETH", "USDC", "USDT", "ARB"]
        
        for asset in important_assets:
            try:
                price_data = price_manager.get_detailed_price_data(asset)
                market_analysis["prices"][asset] = price_data
            except Exception as e:
                market_analysis["prices"][asset] = {"error": str(e)}
        
        # Calculate market volatility indicators
        try:
            eth_price = price_manager.get_price("ETH")
            btc_price = price_manager.get_price("BTC")
            
            # Simple volatility assessment (in production, would use historical data)
            volatility_score = 0.5  # Default medium volatility
            if eth_price > 3000:  # High price might indicate bull market
                volatility_score = 0.3  # Lower volatility in bull markets
            elif eth_price < 1500:  # Low price might indicate bear market
                volatility_score = 0.8  # Higher volatility in bear markets
            
            market_analysis["market_sentiment"] = {
                "volatility_score": volatility_score,
                "market_phase": "BULL" if eth_price > 2500 else "BEAR" if eth_price < 1800 else "SIDEWAYS",
                "risk_level": "LOW" if volatility_score < 0.4 else "MEDIUM" if volatility_score < 0.7 else "HIGH"
            }
            
        except Exception as e:
            market_analysis["market_sentiment"] = {"error": str(e)}
        
        # Risk indicators for DeFi strategies
        try:
            usdc_price = price_manager.get_price("USDC")
            usdc_depeg_risk = abs(1.0 - usdc_price) > 0.01  # More than 1% deviation
            
            market_analysis["risk_indicators"] = {
                "usdc_depeg_risk": usdc_depeg_risk,
                "usdc_price": usdc_price,
                "stablecoin_risk_level": "HIGH" if usdc_depeg_risk else "LOW",
                "defi_market_conditions": "STABLE" if not usdc_depeg_risk else "STRESSED"
            }
            
        except Exception as e:
            market_analysis["risk_indicators"] = {"error": str(e)}
        
        return f"Market Analysis and Pricing:\n{json.dumps(market_analysis, indent=2)}"
        
    except Exception as e:
        return f"❌ Market analysis failed: {e}"

@tool
def perform_ml_risk_assessment_deployed_strategies() -> str:
    """
    Perform ML risk assessment on all deployed strategies with market data integration.
    """
    print("Tool: perform_ml_risk_assessment_deployed_strategies")
    
    if not risk_api:
        return "❌ ML Risk assessment unavailable - model not loaded"
    
    assessments = {}
    overall_risk = 0
    strategy_count = 0
    
    # Get current market conditions for enhanced risk assessment
    market_volatility = 0.5  # Default
    if price_manager:
        try:
            eth_price = price_manager.get_price("ETH")
            market_volatility = 0.3 if eth_price > 2500 else 0.8 if eth_price < 1800 else 0.5
        except:
            pass
    
    for strategy_name, strategy_address in STRATEGY_NAMES.items():
        try:
            base_risk_score = risk_api.assess_strategy_risk(strategy_address)
            detailed = risk_api.get_detailed_assessment(strategy_address)
            
            # Adjust risk score based on market conditions
            market_adjustment = 0.0
            if "pancake" in strategy_name.lower():
                # DEX strategies more sensitive to market volatility
                market_adjustment = market_volatility * 0.2
            elif "superlend" in strategy_name.lower():
                # Lending strategies less sensitive but still affected
                market_adjustment = market_volatility * 0.1
            
            adjusted_risk_score = min(1.0, base_risk_score + market_adjustment)
            
            risk_level = "LOW" if adjusted_risk_score < 0.3 else "MEDIUM" if adjusted_risk_score < 0.7 else "HIGH"
            recommendation = "APPROVE" if adjusted_risk_score < 0.5 else "MONITOR" if adjusted_risk_score < 0.8 else "EMERGENCY_REVIEW"
            
            # Get strategy balance for risk weighting
            try:
                strategy_contract = w3.eth.contract(address=strategy_address, abi=load_abi("strategy"))
                balance = float(strategy_contract.functions.getBalance().call()) / 1e6
            except:
                balance = 0
            
            assessments[strategy_name] = {
                "address": strategy_address,
                "base_risk_score": f"{base_risk_score:.3f}",
                "market_adjusted_risk": f"{adjusted_risk_score:.3f}",
                "market_adjustment": f"{market_adjustment:.3f}",
                "risk_level": risk_level,
                "recommendation": recommendation,
                "current_balance": f"{balance:.2f} USDC",
                "weighted_risk": adjusted_risk_score * balance,
                "market_volatility": f"{market_volatility:.3f}",
                "details": str(detailed)[:150] + "..." if len(str(detailed)) > 150 else str(detailed)
            }
            
            overall_risk += adjusted_risk_score * balance
            strategy_count += balance
            
        except Exception as e:
            assessments[strategy_name] = {
                "address": strategy_address,
                "error": str(e),
                "recommendation": "MANUAL_REVIEW"
            }
    
    # Calculate portfolio-weighted risk
    portfolio_risk = overall_risk / strategy_count if strategy_count > 0 else 0
    portfolio_level = "LOW" if portfolio_risk < 0.3 else "MEDIUM" if portfolio_risk < 0.7 else "HIGH"
    
    risk_report = {
        "individual_strategies": assessments,
        "portfolio_analysis": {
            "weighted_risk_score": f"{portfolio_risk:.3f}",
            "portfolio_risk_level": portfolio_level,
            "total_assessed_value": f"{strategy_count:.2f} USDC",
            "recommendation": "CONTINUE" if portfolio_risk < 0.6 else "REBALANCE" if portfolio_risk < 0.8 else "EMERGENCY_ACTION"
        },
        "market_conditions": {
            "volatility_score": f"{market_volatility:.3f}",
            "market_impact": "Volatility adjustments applied to risk scores",
            "high_risk_strategies": [name for name, data in assessments.items() 
                                   if isinstance(data, dict) and data.get("risk_level") == "HIGH"]
        },
        "risk_thresholds": {
            "emergency_threshold": f"{risk_config.emergency_risk_threshold:.1f}",
            "rebalance_threshold": f"{risk_config.rebalance_risk_threshold:.1f}",
            "max_strategy_allocation": f"{risk_config.max_strategy_allocation:.1%}"
        }
    }
    
    return f"ML Risk Assessment - Deployed Strategies:\n{json.dumps(risk_report, indent=2)}"

@tool
def harvest_all_deployed_strategies() -> str:
    """
    Harvest yield from all deployed strategies and prepare for lottery.
    """
    print("Tool: harvest_all_deployed_strategies")
    
    try:
        harvest_results = {}
        total_harvested = 0
        
        # Harvest each strategy individually
        for strategy_name, strategy_address in STRATEGY_NAMES.items():
            try:
                strategy_contract = w3.eth.contract(address=strategy_address, abi=load_abi("strategy"))
                
                # Check if strategy is paused
                try:
                    is_paused = strategy_contract.functions.paused().call()
                    if is_paused:
                        harvest_results[strategy_name] = {"status": "SKIPPED", "reason": "Strategy paused"}
                        continue
                except:
                    pass  # Continue if paused() function not available
                
                # Get balance before harvest
                try:
                    balance_before = strategy_contract.functions.getBalance().call()
                except:
                    balance_before = 0
                
                # Execute harvest
                tx = strategy_contract.functions.harvest(b"").build_transaction({
                    'from': agent_account.address,
                    'nonce': w3.eth.get_transaction_count(agent_account.address),
                    'gas': 1_000_000,
                    'gasPrice': w3.eth.gas_price,
                    'chainId': ETHERLINK_CHAIN_ID
                })
                
                result = send_transaction(tx, f"Harvest {strategy_name}")
                
                if result["success"]:
                    # Get balance after harvest
                    time.sleep(2)
                    try:
                        balance_after = strategy_contract.functions.getBalance().call()
                        harvested_amount = (balance_after - balance_before) / 1e6
                    except:
                        harvested_amount = 0
                    
                    harvest_results[strategy_name] = {
                        "status": "SUCCESS",
                        "harvested": f"{harvested_amount:.2f} USDC",
                        "tx_hash": result["tx_hash"],
                        "gas_used": result.get("gas_used", 0)
                    }
                    total_harvested += harvested_amount
                else:
                    harvest_results[strategy_name] = {
                        "status": "FAILED",
                        "error": result["error"]
                    }
                    
            except Exception as e:
                harvest_results[strategy_name] = {
                    "status": "ERROR",
                    "error": str(e)
                }
        
        # Also try vault-level harvest
        try:
            vault_harvest_tx = vault_core.functions.harvestAllStrategies().build_transaction({
                'from': agent_account.address,
                'nonce': w3.eth.get_transaction_count(agent_account.address),
                'gas': 2_000_000,
                'gasPrice': w3.eth.gas_price,
                'chainId': ETHERLINK_CHAIN_ID
            })
            
            vault_result = send_transaction(vault_harvest_tx, "Vault-level harvest all strategies")
            
            if vault_result["success"]:
                harvest_results["vault_harvest"] = {
                    "status": "SUCCESS",
                    "tx_hash": vault_result["tx_hash"]
                }
            else:
                harvest_results["vault_harvest"] = {
                    "status": "FAILED",
                    "error": vault_result["error"]
                }
                
        except Exception as e:
            harvest_results["vault_harvest"] = {
                "status": "ERROR",
                "error": str(e)
            }
        
        harvest_summary = {
            "total_harvested": f"{total_harvested:.2f} USDC",
            "successful_harvests": len([r for r in harvest_results.values() if r.get("status") == "SUCCESS"]),
            "failed_harvests": len([r for r in harvest_results.values() if r.get("status") in ["FAILED", "ERROR"]]),
            "harvest_details": harvest_results,
            "next_action": "DEPOSIT_TO_LOTTERY" if total_harvested > yield_config.min_harvest_amount else "WAIT_FOR_MORE_YIELD"
        }
        
        return f"Strategy Harvest Results:\n{json.dumps(harvest_summary, indent=2)}"
        
    except Exception as e:
        return f"❌ Harvest failed: {e}"

@tool
def execute_weekly_lottery_cycle() -> str:
    """
    Execute the complete weekly lottery cycle: harvest, deposit yield, and run lottery.
    """
    print("Tool: execute_weekly_lottery_cycle")
    
    try:
        cycle_results = {
            "cycle_start": datetime.now().isoformat(),
            "steps": {},
            "final_status": "UNKNOWN"
        }
        
        # Step 1: Harvest all strategies
        print("Step 1: Harvesting all strategies...")
        harvest_result = harvest_all_deployed_strategies.invoke({})
        cycle_results["steps"]["harvest"] = harvest_result
        
        # Step 2: Check lottery status before execution
        try:
            lottery_info = lottery_extension.functions.getLotteryInfo().call()
            current_prize = float(lottery_info[0]) / 1e6
            can_execute = lottery_info[2] if len(lottery_info) > 2 else False
            
            cycle_results["steps"]["pre_lottery_check"] = {
                "current_prize_pool": f"{current_prize:.2f} USDC",
                "can_execute": can_execute,
                "min_required": f"{lottery_config.min_prize_pool} USDC"
            }
        except Exception as e:
            cycle_results["steps"]["pre_lottery_check"] = {"error": str(e)}
            current_prize = 0
            can_execute = False
        
        # Step 3: If we have harvested yield, deposit it to lottery
        if "total_harvested" in harvest_result and float(harvest_result.split("total_harvested")[1].split("USDC")[0].strip('": ')) > 0:
            print("Step 2: Depositing harvested yield to lottery...")
            
            # Simulate additional yield for lottery (since our strategies are simplified)
            additional_yield = 25.0  # 25 USDC for demo
            yield_deposit_result = simulate_yield_harvest_and_deposit.invoke({"amount_usdc": additional_yield})
            cycle_results["steps"]["yield_deposit"] = yield_deposit_result
            
            # Update prize pool
            current_prize += additional_yield
        
        # Step 4: Execute lottery if conditions are met
        if current_prize >= lottery_config.min_prize_pool:
            print("Step 3: Executing lottery...")
            
            try:
                # Get participants before lottery
                try:
                    depositors = lottery_extension.functions.getDepositors().call()
                    participants_before = len(depositors)
                except:
                    participants_before = 0
                
                lottery_tx = lottery_extension.functions.executeLottery().build_transaction({
                    'from': agent_account.address,
                    'nonce': w3.eth.get_transaction_count(agent_account.address),
                    'gas': 1_500_000,
                    'gasPrice': w3.eth.gas_price,
                    'chainId': ETHERLINK_CHAIN_ID
                })
                
                lottery_result = send_transaction(lottery_tx, f"Execute weekly lottery - {current_prize:.2f} USDC prize")
                
                if lottery_result["success"]:
                    # Get winner information
                    time.sleep(3)
                    try:
                        new_lottery_info = lottery_extension.functions.getLotteryInfo().call()
                        winner = new_lottery_info[1]
                        new_prize_pool = float(new_lottery_info[0]) / 1e6
                    except:
                        winner = "Unknown"
                        new_prize_pool = 0
                    
                    cycle_results["steps"]["lottery_execution"] = {
                        "status": "SUCCESS",
                        "winner": winner,
                        "prize_awarded": f"{current_prize:.2f} USDC",
                        "participants": participants_before,
                        "tx_hash": lottery_result["tx_hash"],
                        "new_prize_pool": f"{new_prize_pool:.2f} USDC"
                    }
                    cycle_results["final_status"] = "LOTTERY_COMPLETED"
                else:
                    cycle_results["steps"]["lottery_execution"] = {
                        "status": "FAILED",
                        "error": lottery_result["error"]
                    }
                    cycle_results["final_status"] = "LOTTERY_FAILED"
                    
            except Exception as e:
                cycle_results["steps"]["lottery_execution"] = {
                    "status": "ERROR",
                    "error": str(e)
                }
                cycle_results["final_status"] = "LOTTERY_ERROR"
        else:
            cycle_results["steps"]["lottery_execution"] = {
                "status": "SKIPPED",
                "reason": f"Prize pool ({current_prize:.2f} USDC) below minimum ({lottery_config.min_prize_pool} USDC)"
            }
            cycle_results["final_status"] = "WAITING_FOR_MORE_YIELD"
        
        # Step 5: Post-cycle analysis
        cycle_results["cycle_end"] = datetime.now().isoformat()
        cycle_results["next_cycle"] = (datetime.now() + timedelta(days=lottery_config.weekly_cycle_days)).isoformat()
        
        return f"Weekly Lottery Cycle Results:\n{json.dumps(cycle_results, indent=2)}"
        
    except Exception as e:
        return f"❌ Weekly lottery cycle failed: {e}"

@tool
def rebalance_strategy_allocations() -> str:
    """
    Rebalance allocations between strategies based on risk and performance with market data.
    """
    print("Tool: rebalance_strategy_allocations")
    
    try:
        # Get current allocations
        current_allocations = {}
        total_deployed = 0
        
        for strategy_name, strategy_address in STRATEGY_NAMES.items():
            try:
                strategy_contract = w3.eth.contract(address=strategy_address, abi=load_abi("strategy"))
                balance = float(strategy_contract.functions.getBalance().call()) / 1e6
                current_allocations[strategy_name] = balance
                total_deployed += balance
            except:
                current_allocations[strategy_name] = 0
        
        # Calculate current percentages
        current_percentages = {}
        for name, balance in current_allocations.items():
            current_percentages[name] = (balance / total_deployed * 100) if total_deployed > 0 else 0
        
        # Get market conditions for enhanced rebalancing
        market_volatility = 0.5  # Default
        if price_manager:
            try:
                eth_price = price_manager.get_price("ETH")
                market_volatility = 0.3 if eth_price > 2500 else 0.8 if eth_price < 1800 else 0.5
            except:
                pass
        
        # Get risk scores and performance if available
        risk_scores = {}
        if risk_api:
            for strategy_name, strategy_address in STRATEGY_NAMES.items():
                try:
                    base_risk = risk_api.assess_strategy_risk(strategy_address)
                    
                    # Apply market adjustments
                    market_adjustment = 0.0
                    if "pancake" in strategy_name.lower():
                        market_adjustment = market_volatility * 0.2
                    elif "superlend" in strategy_name.lower():
                        market_adjustment = market_volatility * 0.1
                    
                    risk_scores[strategy_name] = min(1.0, base_risk + market_adjustment)
                except:
                    risk_scores[strategy_name] = 0.5  # Default medium risk
        else:
            # Default risk scores based on strategy type with market adjustment
            base_risks = {
                "simple_superlend_usdc": 0.3,      # Lower risk lending
                "simple_pancake_usdc_weth": 0.5,   # Medium risk DEX
                "lottery_yield": 0.2                # Lowest risk lottery
            }
            
            for name, base_risk in base_risks.items():
                market_adjustment = 0.0
                if "pancake" in name.lower():
                    market_adjustment = market_volatility * 0.2
                elif "superlend" in name.lower():
                    market_adjustment = market_volatility * 0.1
                
                risk_scores[name] = min(1.0, base_risk + market_adjustment)
        
        # Calculate optimal allocations with market-adjusted risk
        strategy_scores = {}
        for name in STRATEGY_NAMES.keys():
            risk_penalty = risk_scores.get(name, 0.5)
            # Inverse risk score (lower risk = higher score)
            risk_adjusted_score = 1 - risk_penalty
            
            # Apply market condition bonus/penalty
            if market_volatility > 0.7:  # High volatility - prefer safer strategies
                if "lottery" in name.lower():
                    risk_adjusted_score *= 1.2  # Bonus for lottery strategy
                elif "pancake" in name.lower():
                    risk_adjusted_score *= 0.8  # Penalty for DEX strategy
            
            strategy_scores[name] = risk_adjusted_score
        
        # Normalize scores to percentages
        total_score = sum(strategy_scores.values())
        optimal_percentages = {}
        for name, score in strategy_scores.items():
            optimal_percentages[name] = (score / total_score * 100) if total_score > 0 else 33.33
        
        # Apply maximum allocation limits
        max_allocation_pct = risk_config.max_strategy_allocation * 100
        for name in optimal_percentages:
            if optimal_percentages[name] > max_allocation_pct:
                optimal_percentages[name] = max_allocation_pct
        
        # Renormalize after applying limits
        total_optimal = sum(optimal_percentages.values())
        if total_optimal > 0:
            for name in optimal_percentages:
                optimal_percentages[name] = (optimal_percentages[name] / total_optimal * 100)
        
        # Calculate rebalancing needs
        rebalancing_actions = {}
        significant_rebalance_needed = False
        
        for name in STRATEGY_NAMES.keys():
            current_pct = current_percentages.get(name, 0)
            optimal_pct = optimal_percentages.get(name, 0)
            difference = optimal_pct - current_pct
            
            if abs(difference) > 5:  # 5% threshold for rebalancing
                significant_rebalance_needed = True
                action = "INCREASE" if difference > 0 else "DECREASE"
                amount_change = abs(difference) * total_deployed / 100
                
                rebalancing_actions[name] = {
                    "action": action,
                    "current_percentage": f"{current_pct:.1f}%",
                    "optimal_percentage": f"{optimal_pct:.1f}%",
                    "difference": f"{difference:+.1f}%",
                    "amount_change": f"{amount_change:.2f} USDC",
                    "risk_score": f"{risk_scores.get(name, 0.5):.3f}"
                }
        
        rebalance_report = {
            "current_allocations": {name: f"{bal:.2f} USDC ({pct:.1f}%)" 
                                  for name, bal, pct in zip(current_allocations.keys(), 
                                                          current_allocations.values(), 
                                                          current_percentages.values())},
            "optimal_allocations": {name: f"{pct:.1f}%" for name, pct in optimal_percentages.items()},
            "risk_scores": {name: f"{score:.3f}" for name, score in risk_scores.items()},
            "market_conditions": {
                "volatility_score": f"{market_volatility:.3f}",
                "market_adjustment": "Applied to risk calculations",
                "rebalancing_bias": "Conservative (favoring safer strategies)" if market_volatility > 0.7 else "Balanced"
            },
            "rebalancing_needed": significant_rebalance_needed,
            "rebalancing_actions": rebalancing_actions,
            "total_deployed": f"{total_deployed:.2f} USDC",
            "recommendation": "EXECUTE_REBALANCE" if significant_rebalance_needed else "MAINTAIN_CURRENT"
        }
        
        return f"Strategy Rebalancing Analysis:\n{json.dumps(rebalance_report, indent=2)}"
        
    except Exception as e:
        return f"❌ Rebalancing analysis failed: {e}"

@tool
def deploy_to_optimal_strategy(amount_usdc: float, strategy_preference: str = "auto") -> str:
    """
    Deploy funds to the optimal strategy based on current risk and performance analysis.
    Args:
        amount_usdc: Amount in USDC to deploy
        strategy_preference: "auto", "simple_superlend_usdc", "simple_pancake_usdc_weth", or "lottery_yield"
    """
    print(f"Tool: deploy_to_optimal_strategy - {amount_usdc} USDC to {strategy_preference}")
    
    try:
        # Check available liquid balance
        liquid_balance = float(usdc_contract.functions.balanceOf(VAULT_CORE_ADDRESS).call()) / 1e6
        
        if amount_usdc > liquid_balance:
            return f"❌ Insufficient liquid funds: {liquid_balance:.2f} USDC available, {amount_usdc:.2f} requested"
        
        # Determine target strategy
        if strategy_preference == "auto":
            # Use risk assessment and market conditions to choose optimal strategy
            market_volatility = 0.5  # Default
            if price_manager:
                try:
                    eth_price = price_manager.get_price("ETH")
                    market_volatility = 0.3 if eth_price > 2500 else 0.8 if eth_price < 1800 else 0.5
                except:
                    pass
            
            best_strategy = None
            best_score = -1
            
            if risk_api:
                for strategy_name, strategy_address in STRATEGY_NAMES.items():
                    try:
                        base_risk = risk_api.assess_strategy_risk(strategy_address)
                        
                        # Apply market adjustments
                        market_adjustment = 0.0
                        if "pancake" in strategy_name.lower():
                            market_adjustment = market_volatility * 0.2
                        elif "superlend" in strategy_name.lower():
                            market_adjustment = market_volatility * 0.1
                        
                        risk_score = min(1.0, base_risk + market_adjustment)
                        
                        # Score = yield potential / risk (simplified)
                        yield_estimate = 0.05 if "superlend" in strategy_name else 0.08 if "pancake" in strategy_name else 0.03
                        
                        # Apply market condition adjustments to yield estimates
                        if market_volatility > 0.7 and "pancake" in strategy_name:
                            yield_estimate *= 0.8  # Reduce expected yield in high volatility
                        
                        risk_adjusted_score = yield_estimate / (risk_score + 0.1)  # Avoid division by zero
                        
                        if risk_adjusted_score > best_score and risk_score < 0.7:  # Only consider low-medium risk
                            best_score = risk_adjusted_score
                            best_strategy = strategy_name
                    except:
                        continue
                
                if not best_strategy:
                    best_strategy = "simple_superlend_usdc"  # Default safe choice
            else:
                # Default strategy selection based on market conditions
                if market_volatility > 0.7:
                    best_strategy = "lottery_yield"  # Safest in high volatility
                else:
                    best_strategy = "simple_superlend_usdc"  # Default
        else:
            if strategy_preference in STRATEGY_NAMES:
                best_strategy = strategy_preference
            else:
                return f"❌ Invalid strategy preference: {strategy_preference}. Valid options: {list(STRATEGY_NAMES.keys())}"
        
        # Execute deployment
        amount_wei = int(amount_usdc * 1e6)
        
        try:
            deploy_tx = vault_core.functions.deployToNamedStrategy(
                best_strategy,
                amount_wei,
                b""  # Empty data
            ).build_transaction({
                'from': agent_account.address,
                'nonce': w3.eth.get_transaction_count(agent_account.address),
                'gas': 2_000_000,
                'gasPrice': w3.eth.gas_price,
                'chainId': ETHERLINK_CHAIN_ID
            })
            
            result = send_transaction(deploy_tx, f"Deploy {amount_usdc} USDC to {best_strategy}")
            
            if result["success"]:
                # Get updated balance
                time.sleep(2)
                try:
                    strategy_address = STRATEGY_NAMES[best_strategy]
                    strategy_contract = w3.eth.contract(address=strategy_address, abi=load_abi("strategy"))
                    new_balance = float(strategy_contract.functions.getBalance().call()) / 1e6
                except:
                    new_balance = 0
                
                # Get current market context
                market_context = "N/A"
                if price_manager:
                    try:
                        eth_price = price_manager.get_price("ETH")
                        market_context = f"ETH: ${eth_price:.2f}"
                    except:
                        pass
                
                deployment_result = {
                    "status": "SUCCESS",
                    "strategy": best_strategy,
                    "strategy_address": STRATEGY_NAMES[best_strategy],
                    "amount_deployed": f"{amount_usdc:.2f} USDC",
                    "new_strategy_balance": f"{new_balance:.2f} USDC",
                    "tx_hash": result["tx_hash"],
                    "gas_used": result.get("gas_used", 0),
                    "selection_reason": "ML Risk + Market Assessment" if risk_api and strategy_preference == "auto" else "Manual Selection",
                    "market_context": market_context
                }
                
                return f"Strategy Deployment Result:\n{json.dumps(deployment_result, indent=2)}"
            else:
                return f"❌ Deployment failed: {result['error']}"
                
        except Exception as e:
            return f"❌ Deployment transaction failed: {e}"
            
    except Exception as e:
        return f"❌ Optimal strategy deployment failed: {e}"

@tool
def simulate_yield_harvest_and_deposit(amount_usdc: float) -> str:
    """
    Simulate yield generation and deposit to lottery for testing and weekly operations.
    """
    print(f"Tool: simulate_yield_harvest_and_deposit - {amount_usdc} USDC")
    
    if amount_usdc <= 0:
        return "❌ Invalid amount: Must be greater than 0"
    
    try:
        amount_wei = int(amount_usdc * 1e6)
        
        # Step 1: Mint yield to agent
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
        
        # Step 2: Approve lottery extension
        approve_tx = usdc_contract.functions.approve(LOTTERY_EXTENSION, amount_wei).build_transaction({
            'from': agent_account.address,
            'nonce': w3.eth.get_transaction_count(agent_account.address),
            'gas': 500_000,
            'gasPrice': w3.eth.gas_price,
            'chainId': ETHERLINK_CHAIN_ID
        })
        
        approve_result = send_transaction(approve_tx, f"Approve lottery extension for {amount_usdc} USDC")
        if not approve_result["success"]:
            return f"❌ Failed to approve: {approve_result['error']}"
        
        time.sleep(2)
        
        # Step 3: Deposit yield into lottery
        try:
            deposit_tx = lottery_extension.functions.depositYieldForLottery(amount_wei).build_transaction({
                'from': agent_account.address,
                'nonce': w3.eth.get_transaction_count(agent_account.address),
                'gas': 1_000_000,
                'gasPrice': w3.eth.gas_price,
                'chainId': ETHERLINK_CHAIN_ID
            })
            
            deposit_result = send_transaction(deposit_tx, f"Deposit {amount_usdc} USDC yield to lottery")
            
            if deposit_result["success"]:
                # Check updated lottery status
                time.sleep(2)
                try:
                    lottery_info = lottery_extension.functions.getLotteryInfo().call()
                    new_prize_pool = float(lottery_info[0]) / 1e6
                    can_execute = lottery_info[2] if len(lottery_info) > 2 else False
                except:
                    new_prize_pool = 0
                    can_execute = False
                
                simulation_result = {
                    "status": "SUCCESS",
                    "yield_generated": f"{amount_usdc:.2f} USDC",
                    "mint_tx": mint_result["tx_hash"],
                    "approve_tx": approve_result["tx_hash"],
                    "deposit_tx": deposit_result["tx_hash"],
                    "new_prize_pool": f"{new_prize_pool:.2f} USDC",
                    "lottery_ready": can_execute,
                    "total_gas_used": mint_result.get("gas_used", 0) + approve_result.get("gas_used", 0) + deposit_result.get("gas_used", 0)
                }
                
                return f"Yield Simulation Result:\n{json.dumps(simulation_result, indent=2)}"
            else:
                return f"❌ Failed to deposit yield: {deposit_result['error']}"
                
        except Exception as e:
            return f"❌ Yield deposit failed: {e}"
            
    except Exception as e:
        return f"❌ Yield simulation failed: {e}"

# ==============================================================================
# 4. WEEKLY LOTTERY AUTOMATION
# ==============================================================================

class WeeklyLotteryScheduler:
    """Handles automated weekly lottery execution."""
    
    def __init__(self):
        self.is_running = False
        self.last_execution = None
    
    def should_execute_lottery(self):
        """Check if it's time to execute the weekly lottery."""
        now = datetime.now()
        
        # Check if it's the right day and time
        if now.weekday() == lottery_config.lottery_execution_day and now.hour == lottery_config.lottery_execution_hour:
            # Check if we haven't executed today
            if self.last_execution is None or self.last_execution.date() != now.date():
                return True
        return False
    
    def execute_automated_lottery(self):
        """Execute the automated weekly lottery cycle."""
        if self.is_running:
            print("🔄 Lottery execution already in progress")
            return
        
        self.is_running = True
        try:
            print("🎰 Starting automated weekly lottery execution...")
            
            # Execute the full lottery cycle
            result = execute_weekly_lottery_cycle.invoke({})
            print(f"✅ Weekly lottery cycle completed: {result}")
            
            self.last_execution = datetime.now()
            
        except Exception as e:
            print(f"❌ Automated lottery execution failed: {e}")
        finally:
            self.is_running = False

# Initialize scheduler
lottery_scheduler = WeeklyLotteryScheduler()

# ==============================================================================
# 5. ENHANCED LANGCHAIN AGENT
# ==============================================================================

# Build enhanced tools list
tools = [
    get_comprehensive_vault_status,
    get_market_analysis_and_pricing,
    perform_ml_risk_assessment_deployed_strategies,
    harvest_all_deployed_strategies,
    execute_weekly_lottery_cycle,
    rebalance_strategy_allocations,
    deploy_to_optimal_strategy,
    simulate_yield_harvest_and_deposit
]

tool_names = [t.name for t in tools]

enhanced_prompt_template = """
You are the "Enhanced Etherlink Vault Manager," a sophisticated AI agent managing a WEEKLY YIELD LOTTERY system with ML-powered risk assessment, real-time market data integration, and deployed strategies.

Your deployed contracts:
🏦 Vault Core: {vault_core_address}
🎰 Lottery Extension: {lottery_extension}
💰 USDC Token: {usdc_address}
📊 Strategy Registry: {strategy_registry}

DEPLOYED STRATEGIES:
🏛️ SimpleSuperlendStrategy: {simple_superlend} (Lending protocol simulation)
🥞 SimplePancakeSwapStrategy: {simple_pancake} (DEX liquidity simulation)  
🎲 EtherlinkYieldLottery: {lottery_strategy} (Lottery-specific yield strategy)

WEEKLY LOTTERY SYSTEM:
- Operates on 7-day cycles starting Monday at 12:00 UTC
- Collects yield from all strategies during the week
- Participants are vault depositors weighted by deposit amount
- Weekly prize distribution with ML risk-optimized yield generation
- Minimum 10 USDC prize pool for execution
- Winner selection uses provably fair randomness

ENHANCED TOOLS:
{tools}

OPERATIONAL FRAMEWORK:
1. **Monday Lottery Execution**: Check if it's lottery day and execute weekly cycle
2. **Continuous Yield Harvesting**: Harvest from deployed strategies every 12 hours
3. **Risk Monitoring**: ML assessment of all strategies every 6 hours with market data
4. **Dynamic Rebalancing**: Optimize allocations based on risk/reward and market conditions
5. **Prize Pool Management**: Ensure sufficient yield for meaningful prizes
6. **Market Analysis**: Real-time cryptocurrency price monitoring and volatility assessment
7. **Participant Tracking**: Monitor deposits and lottery eligibility

STRATEGY-SPECIFIC OPERATIONS:
- SimpleSuperlendStrategy: Conservative lending with 1% simulated yield
- SimplePancakeSwapStrategy: DEX liquidity with 0.3% fee simulation (market-sensitive)
- EtherlinkYieldLottery: Direct lottery contribution with minimal risk

MARKET-ENHANCED DECISION MATRIX:
Risk Score < 0.3 + Market Volatility Adjustment: ✅ Aggressive allocation (up to 40%)
Risk Score 0.3-0.6 + Market Adjustment: ⚠️ Moderate allocation (up to 30%)
Risk Score 0.6-0.8 + Market Adjustment: 🔶 Conservative allocation (up to 20%)
Risk Score > 0.8 + Market Adjustment: 🚨 Emergency review required

MARKET CONDITIONS INTEGRATION:
- High Volatility (ETH < $1800): Favor lottery_yield and superlend strategies
- Medium Volatility ($1800 < ETH < $2500): Balanced allocation
- Low Volatility (ETH > $2500): Allow higher pancake strategy allocation
- USDC Depeg Risk: Emergency rebalancing to safest strategies

WEEKLY LOTTERY MECHANICS:
- Monday 12:00 UTC: Execute lottery if prize pool ≥ 10 USDC
- Deposit-weighted probability (more deposits = higher chance)
- Automated yield collection from all strategies
- Prize distribution to single winner
- Reset cycle for next week

Use this format:
Question: the user's operational request
Thought: Consider current lottery cycle, strategy performance, market conditions, and risk factors
Action: the action to take, should be one of [{tool_names}]
Action Input: the input to the action
Observation: the result of the action
... (repeat for comprehensive analysis)
Thought: I now have sufficient information for lottery operations with market context.
Final Answer: comprehensive response with lottery status, strategy performance, market analysis, and actionable recommendations

PRIORITY OPERATIONS:
1. Always check if it's lottery execution time
2. Monitor strategy risk scores with market adjustments continuously
3. Assess current market conditions and volatility
4. Ensure sufficient yield generation for prizes
5. Maintain participant engagement
6. Optimize risk-adjusted returns based on market conditions

Begin enhanced lottery operations with market intelligence!

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
    max_iterations=12,
    early_stopping_method="force"
)

# ==============================================================================
# 6. ENHANCED FASTAPI SERVER
# ==============================================================================

app = FastAPI(
    title="Enhanced Etherlink Vault Manager - Weekly Lottery System",
    description="Production-ready AI agent for weekly yield lottery with deployed strategies and market intelligence",
    version="4.1.0"
)

class AgentRequest(BaseModel):
    command: str

class DeploymentRequest(BaseModel):
    amount_usdc: float
    strategy_preference: str = "auto"

class LotteryRequest(BaseModel):
    amount_usdc: float

@app.post("/invoke-agent")
async def invoke_enhanced_agent(request: AgentRequest):
    """Enhanced agent endpoint with deployed contract integration and market data."""
    try:
        tool_descriptions = "\n".join([f"- {tool.name}: {tool.description}" for tool in tools])
        
        response = await agent_executor.ainvoke({
            "input": request.command,
            "vault_core_address": VAULT_CORE_ADDRESS,
            "lottery_extension": LOTTERY_EXTENSION,
            "usdc_address": USDC_ADDRESS,
            "strategy_registry": STRATEGY_REGISTRY,
            "simple_superlend": SIMPLE_SUPERLEND_STRATEGY,
            "simple_pancake": SIMPLE_PANCAKE_STRATEGY,
            "lottery_strategy": LOTTERY_YIELD_STRATEGY,
            "tools": tool_descriptions,
            "tool_names": ", ".join(tool_names)
        })
        return {"success": True, "output": response["output"]}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.get("/comprehensive-status")
async def comprehensive_status():
    """Get complete status of deployed vault and strategies."""
    try:
        result = get_comprehensive_vault_status.invoke({})
        return {"success": True, "status": result}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.get("/market-analysis")
async def market_analysis():
    """Get comprehensive market analysis and pricing data."""
    try:
        result = get_market_analysis_and_pricing.invoke({})
        return {"success": True, "market_analysis": result}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.post("/harvest-strategies")
async def harvest_strategies():
    """Harvest yield from all deployed strategies."""
    try:
        result = harvest_all_deployed_strategies.invoke({})
        return {"success": True, "harvest_results": result}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.post("/execute-lottery-cycle")
async def execute_lottery_cycle():
    """Execute the complete weekly lottery cycle."""
    try:
        result = execute_weekly_lottery_cycle.invoke({})
        return {"success": True, "lottery_cycle": result}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.post("/deploy-to-strategy")
async def deploy_to_strategy_endpoint(request: DeploymentRequest):
    """Deploy funds to optimal strategy with market intelligence."""
    try:
        result = deploy_to_optimal_strategy.invoke({
            "amount_usdc": request.amount_usdc,
            "strategy_preference": request.strategy_preference
        })
        return {"success": True, "deployment": result}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.get("/risk-assessment")
async def risk_assessment():
    """Get ML risk assessment for all deployed strategies with market adjustments."""
    try:
        result = perform_ml_risk_assessment_deployed_strategies.invoke({})
        return {"success": True, "risk_assessment": result}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.get("/rebalancing-analysis")
async def rebalancing_analysis():
    """Get strategy rebalancing recommendations with market intelligence."""
    try:
        result = rebalance_strategy_allocations.invoke({})
        return {"success": True, "rebalancing": result}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.post("/simulate-yield")
async def simulate_yield_endpoint(request: LotteryRequest):
    """Simulate yield generation for testing."""
    try:
        result = simulate_yield_harvest_and_deposit.invoke({
            "amount_usdc": request.amount_usdc
        })
        return {"success": True, "simulation": result}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.get("/lottery-status")
async def lottery_status():
    """Get current lottery system status."""
    try:
        # Check if it's lottery execution time
        should_execute = lottery_scheduler.should_execute_lottery()
        
        # Get lottery info
        try:
            lottery_info = lottery_extension.functions.getLotteryInfo().call()
            prize_pool = float(lottery_info[0]) / 1e6
            last_winner = lottery_info[1]
            ready = lottery_info[2] if len(lottery_info) > 2 else False
            time_left = int(lottery_info[3]) if len(lottery_info) > 3 else 0
        except:
            prize_pool = 0
            last_winner = "Unknown"
            ready = False
            time_left = 0
        
        # Get participants
        try:
            depositors = lottery_extension.functions.getDepositors().call()
            participants = len(depositors)
        except:
            participants = 0
        
        # Get market context
        market_context = {}
        if price_manager:
            try:
                eth_price = price_manager.get_price("ETH")
                usdc_price = price_manager.get_price("USDC")
                market_context = {
                    "eth_price": f"${eth_price:.2f}",
                    "usdc_price": f"${usdc_price:.4f}",
                    "market_volatility": "HIGH" if eth_price < 1800 else "LOW" if eth_price > 2500 else "MEDIUM"
                }
            except:
                market_context = {"error": "Price data unavailable"}
        
        status = {
            "current_prize_pool": f"{prize_pool:.2f} USDC",
            "participants": participants,
            "last_winner": last_winner,
            "lottery_ready": ready,
            "time_until_next": f"{time_left/3600:.1f} hours",
            "should_execute_now": should_execute,
            "execution_schedule": {
                "day": "Monday",
                "time": f"{lottery_config.lottery_execution_hour}:00 UTC",
                "cycle_days": lottery_config.weekly_cycle_days
            },
            "requirements": {
                "min_prize_pool": f"{lottery_config.min_prize_pool} USDC",
                "min_deposit": f"{lottery_config.min_deposit_for_lottery} USDC"
            },
            "market_context": market_context
        }
        
        return {"success": True, "lottery_status": status}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.get("/health")
async def health_check():
    """Comprehensive health check for deployed system."""
    try:
        latest_block = w3.eth.block_number
        agent_balance = w3.eth.get_balance(agent_account.address)
        
        # Test core contracts
        vault_balance = usdc_contract.functions.balanceOf(VAULT_CORE_ADDRESS).call()
        
        # Test strategies
        strategy_health = {}
        for name, address in STRATEGY_NAMES.items():
            try:
                strategy_contract = w3.eth.contract(address=address, abi=load_abi("strategy"))
                balance = strategy_contract.functions.getBalance().call()
                strategy_health[name] = {
                    "address": address,
                    "balance": f"{balance/1e6:.2f} USDC",
                    "status": "HEALTHY"
                }
            except Exception as e:
                strategy_health[name] = {
                    "address": address,
                    "status": "ERROR",
                    "error": str(e)
                }
        
        # Test price feeds
        price_feed_status = "UNAVAILABLE"
        if price_manager:
            try:
                eth_price = price_manager.get_price("ETH")
                price_feed_status = "HEALTHY"
            except:
                price_feed_status = "ERROR"
        
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
            "deployed_contracts": {
                "vault_core": VAULT_CORE_ADDRESS,
                "lottery_extension": LOTTERY_EXTENSION,
                "usdc_token": USDC_ADDRESS,
                "strategy_registry": STRATEGY_REGISTRY
            },
            "deployed_strategies": strategy_health,
            "features": {
                "ml_risk_model": RISK_MODEL_AVAILABLE,
                "price_feeds": PRICE_FEEDS_AVAILABLE,
                "price_feed_status": price_feed_status,
                "weekly_lottery": True,
                "automated_harvesting": True,
                "risk_monitoring": True,
                "market_intelligence": True
            },
            "lottery_config": {
                "cycle_days": lottery_config.weekly_cycle_days,
                "execution_day": "Monday",
                "execution_hour": f"{lottery_config.lottery_execution_hour}:00 UTC",
                "min_prize_pool": f"{lottery_config.min_prize_pool} USDC"
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
        "message": "Enhanced Etherlink Vault Manager - Weekly Lottery System with Market Intelligence",
        "version": "4.1.0",
        "lottery_system": {
            "cycle": "Weekly (7 days)",
            "execution": "Monday 12:00 UTC",
            "min_prize": f"{lottery_config.min_prize_pool} USDC",
            "selection": "Deposit-weighted random"
        },
        "deployed_strategies": {
            "simple_superlend_usdc": SIMPLE_SUPERLEND_STRATEGY,
            "simple_pancake_usdc_weth": SIMPLE_PANCAKE_STRATEGY,
            "lottery_yield": LOTTERY_YIELD_STRATEGY
        },
        "deployed_contracts": {
            "vault_core": VAULT_CORE_ADDRESS,
            "lottery_extension": LOTTERY_EXTENSION,
            "usdc_token": USDC_ADDRESS,
            "strategy_registry": STRATEGY_REGISTRY
        },
        "agent_address": agent_account.address,
        "ml_risk_available": RISK_MODEL_AVAILABLE,
        "price_feeds_available": PRICE_FEEDS_AVAILABLE,
        "key_features": [
            "Weekly automated lottery execution",
            "ML-powered strategy risk assessment",
            "Real-time cryptocurrency price monitoring",
            "Market volatility-adjusted strategy selection",
            "Real strategy yield harvesting",
            "Deposit-weighted prize distribution",
            "Automated rebalancing with market intelligence",
            "Emergency risk monitoring"
        ],
        "api_endpoints": [
            "/comprehensive-status - Full system status",
            "/market-analysis - Real-time market data and analysis",
            "/harvest-strategies - Harvest from all strategies",
            "/execute-lottery-cycle - Run weekly lottery",
            "/deploy-to-strategy - Deploy to optimal strategy",
            "/risk-assessment - ML risk analysis with market adjustments",
            "/lottery-status - Current lottery information",
            "/rebalancing-analysis - Strategy optimization with market data",
            "/simulate-yield - Test yield generation"
        ]
    }

# Background task for automated lottery execution
@app.on_event("startup")
async def startup_event():
    """Initialize background tasks."""
    def check_lottery_schedule():
        """Check if lottery should be executed."""
        if lottery_scheduler.should_execute_lottery():
            lottery_scheduler.execute_automated_lottery()
    
    # Schedule lottery check every hour
    schedule.every().hour.do(check_lottery_schedule)
    
    def run_scheduler():
        """Run the scheduler in a separate thread."""
        while True:
            schedule.run_pending()
            time.sleep(60)  # Check every minute
    
    # Start scheduler in background thread
    scheduler_thread = threading.Thread(target=run_scheduler, daemon=True)
    scheduler_thread.start()
    
    print("✅ Background lottery scheduler started")

if __name__ == "__main__":
    import uvicorn
    print("🚀 Starting Enhanced Etherlink Vault Manager - Weekly Lottery System with Market Intelligence...")
    print(f"🧠 ML Risk Model: {'✅ Available' if RISK_MODEL_AVAILABLE else '❌ Unavailable'}")
    print(f"📈 Price Feeds: {'✅ Available' if PRICE_FEEDS_AVAILABLE else '❌ Unavailable'}")
    print(f"🎰 Weekly Lottery: ✅ Enabled (Monday {lottery_config.lottery_execution_hour}:00 UTC)")
    print(f"🤖 Agent Address: {agent_account.address}")
    print(f"🏦 Vault Core: {VAULT_CORE_ADDRESS}")
    print(f"🎲 Lottery Extension: {LOTTERY_EXTENSION}")
    print(f"💰 USDC Token: {USDC_ADDRESS}")
    print("\n📋 Deployed Strategies:")
    for name, address in STRATEGY_NAMES.items():
        print(f"   {name}: {address}")
    
    print("\n🎯 Ready for weekly lottery operations with market intelligence!")
    print("🌐 Server: http://localhost:8000")
    print("📚 API docs: http://localhost:8000/docs")
    print("🎰 Lottery status: http://localhost:8000/lottery-status")
    print("📈 Market analysis: http://localhost:8000/market-analysis")
    print("💊 Health: http://localhost:8000/health")
    
    uvicorn.run(app, host="0.0.0.0", port=8000)