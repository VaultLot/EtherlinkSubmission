#!/usr/bin/env python3
"""
Risk Assessment API for Yield Optimization
Provides simple interface for strategy risk evaluation
"""

import joblib
import numpy as np
import os
import sys

# Ensure we can import from same directory
current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, current_dir)

from anomaly_risk_model import DeFiAnomalyDetector

class RiskAssessmentAPI:
    """Simple API interface for risk assessment"""
    
    def __init__(self, model_path="models/anomaly_risk_model.joblib"):
        # Convert to absolute path if relative
        if not os.path.isabs(model_path):
            current_dir = os.path.dirname(os.path.abspath(__file__))
            model_path = os.path.join(current_dir, model_path)
        
        try:
            self.detector = DeFiAnomalyDetector.load_model(model_path)
            print("✅ Risk model loaded successfully")
        except FileNotFoundError:
            print("❌ Risk model not found. Run anomaly_risk_model.py first.")
            self.detector = None
    
    def assess_strategy_risk(self, strategy_address):
        """
        Assess risk of a DeFi strategy
        
        Returns:
            float: Risk score (0.0 = safe, 1.0 = risky)
        """
        if not self.detector:
            return 0.5  # Default moderate risk if model unavailable
        
        result = self.detector.assess_protocol_risk(strategy_address)
        return result.get('risk_score', 0.5)
    
    def get_detailed_assessment(self, strategy_address):
        """
        Get detailed risk assessment
        
        Returns:
            dict: Detailed risk information
        """
        if not self.detector:
            return {"error": "Model not available", "risk_score": 0.5}
        
        return self.detector.assess_protocol_risk(strategy_address)
    
    def is_strategy_safe(self, strategy_address, risk_threshold=0.5):
        """
        Simple safe/unsafe classification
        
        Args:
            strategy_address: Contract address to assess
            risk_threshold: Risk score above which strategy is considered unsafe
            
        Returns:
            bool: True if safe, False if risky
        """
        risk_score = self.assess_strategy_risk(strategy_address)
        return risk_score < risk_threshold

# Example integration with yield optimizer
class YieldOptimizerWithRisk:
    """Example integration showing how to use risk assessment"""
    
    def __init__(self):
        self.risk_api = RiskAssessmentAPI()
        self.max_risk_tolerance = 0.6  # Realistic for DeFi protocols
    
    def select_safe_strategy(self, available_strategies):
        """
        Select safest strategy from available options
        
        Args:
            available_strategies: List of strategy objects with .address and .apy
            
        Returns:
            Best safe strategy or None if all are too risky
        """
        safe_strategies = []
        
        for strategy in available_strategies:
            risk_score = self.risk_api.assess_strategy_risk(strategy.address)
            
            if risk_score < self.max_risk_tolerance:
                safe_strategies.append({
                    'strategy': strategy,
                    'risk_score': risk_score,
                    'risk_adjusted_apy': strategy.apy * (1 - risk_score)  # Penalize risk
                })
        
        if not safe_strategies:
            return None
        
        # Return strategy with best risk-adjusted APY
        best = max(safe_strategies, key=lambda x: x['risk_adjusted_apy'])
        return best['strategy']

# Test script
if __name__ == "__main__":
    print("🧪 Testing Risk Assessment API")
    
    # Initialize API
    risk_api = RiskAssessmentAPI()
    
    # Test contracts
    test_contracts = [
        "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",  # USDC (should be safe)
        "0xdac17f958d2ee523a2206206994597c13d831ec7",  # USDT (should be safe)
    ]
    
    for contract in test_contracts:
        print(f"\nTesting {contract}:")
        
        # Simple risk score
        risk_score = risk_api.assess_strategy_risk(contract)
        print(f"  Risk Score: {risk_score:.3f}")
        
        # Safety check
        is_safe = risk_api.is_strategy_safe(contract)
        print(f"  Is Safe: {is_safe}")
        
        # Detailed assessment
        details = risk_api.get_detailed_assessment(contract)
        if 'risk_level' in details:
            print(f"  Risk Level: {details['risk_level']}")
    
    # Test your VRF strategy
    print(f"\n🎯 Testing Your VRF Strategy:")
    vrf_address = "0xf5DC9ca0518B45C3E372c3bC7959a4f3d1B18901"
    
    try:
        risk_score = risk_api.assess_strategy_risk(vrf_address)
        print(f"  VRF Risk Score: {risk_score:.3f}")
        
        is_safe = risk_api.is_strategy_safe(vrf_address)
        print(f"  VRF Is Safe: {is_safe}")
        
        details = risk_api.get_detailed_assessment(vrf_address)
        if 'risk_level' in details:
            print(f"  VRF Risk Level: {details['risk_level']}")
        else:
            print(f"  VRF Assessment: {details}")
            
    except Exception as e:
        print(f"  VRF Test Error: {e}")
        print("  Note: This might be expected since VRF is on Flow testnet, not Ethereum")