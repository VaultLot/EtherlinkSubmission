#!/usr/bin/env python3
"""
Risk Assessment API - ML-powered risk scoring for DeFi strategies
Provides sophisticated risk analysis for deployed strategies using machine learning models
"""

import os
import json
import numpy as np
import pandas as pd
from typing import Dict, List, Optional, Tuple, Any
from datetime import datetime, timedelta
from dataclasses import dataclass
import joblib
from sklearn.ensemble import IsolationForest, RandomForestRegressor
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
import warnings
from dotenv import load_dotenv
load_dotenv() 

warnings.filterwarnings('ignore')


@dataclass
class RiskFactors:
    """Risk factors for strategy assessment"""
    smart_contract_risk: float  # 0-1 scale
    liquidity_risk: float      # 0-1 scale  
    market_risk: float         # 0-1 scale
    operational_risk: float    # 0-1 scale
    technical_risk: float      # 0-1 scale
    composability_risk: float  # 0-1 scale


@dataclass
class RiskAssessment:
    """Complete risk assessment result"""
    strategy_address: str
    risk_score: float           # 0-1 scale (0 = lowest risk, 1 = highest risk)
    risk_level: str            # LOW, MEDIUM, HIGH, CRITICAL
    confidence: float          # 0-1 confidence in assessment
    risk_factors: RiskFactors
    recommendations: List[str]
    timestamp: datetime
    model_version: str


class RiskAssessmentAPI:
    """
    Advanced ML-powered risk assessment for DeFi strategies
    """
    
    def __init__(self, model_path: Optional[str] = None):
        self.model = None
        self.scaler = StandardScaler()
        self.feature_columns = [
            'tvl', 'apy', 'volume_24h', 'liquidity_depth', 'age_days',
            'audit_score', 'governance_score', 'team_score', 'volatility',
            'slippage', 'impermanent_loss_risk', 'smart_contract_complexity'
        ]
        
        # Risk thresholds
        self.risk_thresholds = {
            'low': 0.3,
            'medium': 0.6,
            'high': 0.8
        }
        
        # Strategy-specific risk profiles
        self.strategy_profiles = {
            'lending': {
                'base_risk': 0.2,
                'volatility_sensitivity': 0.3,
                'liquidity_sensitivity': 0.4
            },
            'dex': {
                'base_risk': 0.4,
                'volatility_sensitivity': 0.7,
                'liquidity_sensitivity': 0.6
            },
            'staking': {
                'base_risk': 0.3,
                'volatility_sensitivity': 0.4,
                'liquidity_sensitivity': 0.3
            },
            'lottery': {
                'base_risk': 0.1,
                'volatility_sensitivity': 0.2,
                'liquidity_sensitivity': 0.2
            }
        }
        
        # Load or create model
        if model_path and os.path.exists(model_path):
            try:
                self.load_model(model_path)
                print(f"✅ Risk model loaded from {model_path}")
            except Exception as e:
                print(f"⚠️ Failed to load model: {e}")
                self._create_synthetic_model()
        else:
            self._create_synthetic_model()
        
        print("✅ Risk Assessment API initialized")
    
    def _create_synthetic_model(self):
        """Create a synthetic model for demonstration purposes"""
        print("🔧 Creating synthetic risk assessment model...")
        
        # Generate synthetic training data
        np.random.seed(42)
        n_samples = 1000
        
        # Generate realistic DeFi protocol features
        data = {
            'tvl': np.random.lognormal(15, 2, n_samples),  # TVL in USD
            'apy': np.random.normal(8, 4, n_samples),      # APY percentage
            'volume_24h': np.random.lognormal(14, 1.5, n_samples),
            'liquidity_depth': np.random.lognormal(13, 1, n_samples),
            'age_days': np.random.exponential(200, n_samples),
            'audit_score': np.random.beta(2, 1, n_samples),  # Skewed towards higher scores
            'governance_score': np.random.beta(1.5, 1.5, n_samples),
            'team_score': np.random.beta(2, 1.2, n_samples),
            'volatility': np.random.gamma(2, 0.1, n_samples),
            'slippage': np.random.exponential(0.02, n_samples),
            'impermanent_loss_risk': np.random.beta(1, 3, n_samples),
            'smart_contract_complexity': np.random.beta(1, 2, n_samples)
        }
        
        df = pd.DataFrame(data)
        
        # Clip values to reasonable ranges
        df['apy'] = np.clip(df['apy'], 0, 50)
        df['audit_score'] = np.clip(df['audit_score'], 0, 1)
        df['governance_score'] = np.clip(df['governance_score'], 0, 1)
        df['team_score'] = np.clip(df['team_score'], 0, 1)
        df['volatility'] = np.clip(df['volatility'], 0, 1)
        df['slippage'] = np.clip(df['slippage'], 0, 0.1)
        df['impermanent_loss_risk'] = np.clip(df['impermanent_loss_risk'], 0, 1)
        df['smart_contract_complexity'] = np.clip(df['smart_contract_complexity'], 0, 1)
        
        # Generate synthetic risk scores based on features
        risk_scores = (
            0.3 * (1 - df['audit_score']) +
            0.2 * (1 - df['governance_score']) +
            0.1 * (1 - df['team_score']) +
            0.15 * df['volatility'] +
            0.1 * df['slippage'] * 10 +  # Scale slippage
            0.1 * df['impermanent_loss_risk'] +
            0.05 * df['smart_contract_complexity'] +
            np.random.normal(0, 0.05, n_samples)  # Add noise
        )
        risk_scores = np.clip(risk_scores, 0, 1)
        
        # Train the model
        X = df[self.feature_columns]
        y = risk_scores
        
        X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
        
        # Fit scaler
        self.scaler.fit(X_train)
        X_train_scaled = self.scaler.transform(X_train)
        
        # Train Random Forest model
        self.model = RandomForestRegressor(n_estimators=100, random_state=42, max_depth=10)
        self.model.fit(X_train_scaled, y_train)
        
        # Create anomaly detection model
        self.anomaly_detector = IsolationForest(contamination=0.1, random_state=42)
        self.anomaly_detector.fit(X_train_scaled)
        
        print("✅ Synthetic risk model created and trained")
    
    def load_model(self, model_path: str):
        """Load pre-trained model"""
        model_data = joblib.load(model_path)
        self.model = model_data['model']
        self.scaler = model_data['scaler']
        self.anomaly_detector = model_data.get('anomaly_detector')
        self.feature_columns = model_data.get('feature_columns', self.feature_columns)
    
    def save_model(self, model_path: str):
        """Save trained model"""
        os.makedirs(os.path.dirname(model_path), exist_ok=True)
        model_data = {
            'model': self.model,
            'scaler': self.scaler,
            'anomaly_detector': self.anomaly_detector,
            'feature_columns': self.feature_columns,
            'created_at': datetime.now().isoformat(),
            'version': '1.0'
        }
        joblib.dump(model_data, model_path)
        print(f"✅ Model saved to {model_path}")
    
    def _extract_strategy_features(self, strategy_address: str) -> Dict[str, float]:
        """Extract features for a strategy (mock implementation)"""
        # In production, this would fetch real data from blockchain, APIs, etc.
        # For now, we'll create realistic mock data based on strategy type
        
        strategy_type = self._identify_strategy_type(strategy_address)
        
        # Base features that vary by strategy type
        if strategy_type == 'lending':
            features = {
                'tvl': 1000000,  # $1M TVL
                'apy': 5.5,      # 5.5% APY
                'volume_24h': 100000,
                'liquidity_depth': 500000,
                'age_days': 180,
                'audit_score': 0.85,
                'governance_score': 0.75,
                'team_score': 0.8,
                'volatility': 0.15,
                'slippage': 0.005,
                'impermanent_loss_risk': 0.1,
                'smart_contract_complexity': 0.4
            }
        elif strategy_type == 'dex':
            features = {
                'tvl': 2000000,  # $2M TVL
                'apy': 12.0,     # 12% APY
                'volume_24h': 500000,
                'liquidity_depth': 800000,
                'age_days': 120,
                'audit_score': 0.7,
                'governance_score': 0.65,
                'team_score': 0.75,
                'volatility': 0.35,
                'slippage': 0.02,
                'impermanent_loss_risk': 0.6,
                'smart_contract_complexity': 0.7
            }
        elif strategy_type == 'lottery':
            features = {
                'tvl': 500000,   # $500K TVL
                'apy': 3.0,      # 3% APY
                'volume_24h': 50000,
                'liquidity_depth': 250000,
                'age_days': 60,
                'audit_score': 0.9,
                'governance_score': 0.8,
                'team_score': 0.85,
                'volatility': 0.1,
                'slippage': 0.001,
                'impermanent_loss_risk': 0.05,
                'smart_contract_complexity': 0.3
            }
        else:
            # Default/unknown strategy
            features = {
                'tvl': 500000,
                'apy': 6.0,
                'volume_24h': 100000,
                'liquidity_depth': 300000,
                'age_days': 90,
                'audit_score': 0.6,
                'governance_score': 0.6,
                'team_score': 0.6,
                'volatility': 0.3,
                'slippage': 0.015,
                'impermanent_loss_risk': 0.4,
                'smart_contract_complexity': 0.5
            }
        
        # Add some randomness to simulate real-world variation
        for key in features:
            if key in ['audit_score', 'governance_score', 'team_score']:
                # Audit scores should vary less
                features[key] += np.random.normal(0, 0.05)
                features[key] = np.clip(features[key], 0, 1)
            elif key in ['volatility', 'slippage', 'impermanent_loss_risk', 'smart_contract_complexity']:
                features[key] += np.random.normal(0, 0.02)
                features[key] = np.clip(features[key], 0, 1)
            else:
                # Other features can vary more
                features[key] *= (1 + np.random.normal(0, 0.1))
                features[key] = max(0, features[key])
        
        return features
    
    def _identify_strategy_type(self, strategy_address: str) -> str:
        """Identify strategy type from address (mock implementation)"""
        # In production, this would analyze the contract code or use a registry
        address_lower = strategy_address.lower()
        
        if 'superlend' in address_lower or '1864ada' in address_lower:
            return 'lending'
        elif 'pancake' in address_lower or '888e307' in address_lower:
            return 'dex'
        elif 'lottery' in address_lower or '3dc0390' in address_lower:
            return 'lottery'
        else:
            return 'unknown'
    
    def _calculate_risk_factors(self, features: Dict[str, float]) -> RiskFactors:
        """Calculate individual risk factors"""
        return RiskFactors(
            smart_contract_risk=features['smart_contract_complexity'] * 0.7 + (1 - features['audit_score']) * 0.3,
            liquidity_risk=min(1.0, features['slippage'] * 20) * 0.6 + (1 - min(1.0, features['liquidity_depth'] / 1000000)) * 0.4,
            market_risk=features['volatility'] * 0.5 + features['impermanent_loss_risk'] * 0.5,
            operational_risk=(1 - features['governance_score']) * 0.5 + (1 - features['team_score']) * 0.5,
            technical_risk=features['smart_contract_complexity'] * 0.6 + min(1.0, 1 / max(1, features['age_days'] / 30)) * 0.4,
            composability_risk=features['smart_contract_complexity'] * 0.4 + features['volatility'] * 0.3 + features['slippage'] * 10 * 0.3
        )
    
    def _generate_recommendations(self, risk_score: float, risk_factors: RiskFactors, strategy_type: str) -> List[str]:
        """Generate risk-based recommendations"""
        recommendations = []
        
        if risk_score > 0.8:
            recommendations.append("CRITICAL: Emergency review required - consider immediate exit")
            recommendations.append("Reduce allocation to this strategy to minimal amounts")
        elif risk_score > 0.6:
            recommendations.append("HIGH RISK: Limit allocation to maximum 20% of portfolio")
            recommendations.append("Increase monitoring frequency to daily checks")
        elif risk_score > 0.3:
            recommendations.append("MEDIUM RISK: Limit allocation to maximum 40% of portfolio")
            recommendations.append("Monitor weekly for risk changes")
        else:
            recommendations.append("LOW RISK: Strategy suitable for higher allocations")
            recommendations.append("Continue normal monitoring schedule")
        
        # Specific factor recommendations
        if risk_factors.liquidity_risk > 0.7:
            recommendations.append("High liquidity risk detected - avoid large position sizes")
        
        if risk_factors.smart_contract_risk > 0.6:
            recommendations.append("Smart contract risk elevated - verify latest audit reports")
        
        if risk_factors.market_risk > 0.7:
            recommendations.append("High market risk - consider hedging positions")
        
        if risk_factors.operational_risk > 0.6:
            recommendations.append("Operational concerns - review team and governance structures")
        
        # Strategy-specific recommendations
        if strategy_type == 'dex' and risk_factors.market_risk > 0.5:
            recommendations.append("DEX strategy with high market risk - monitor impermanent loss closely")
        
        if strategy_type == 'lending' and risk_factors.liquidity_risk > 0.5:
            recommendations.append("Lending strategy with liquidity concerns - check utilization rates")
        
        return recommendations[:6]  # Limit to top 6 recommendations
    
    def assess_strategy_risk(self, strategy_address: str) -> float:
        """
        Quick risk assessment returning just the risk score
        """
        try:
            features = self._extract_strategy_features(strategy_address)
            feature_vector = [features[col] for col in self.feature_columns]
            feature_vector_scaled = self.scaler.transform([feature_vector])
            
            risk_score = self.model.predict(feature_vector_scaled)[0]
            return float(np.clip(risk_score, 0, 1))
            
        except Exception as e:
            print(f"❌ Risk assessment error for {strategy_address}: {e}")
            # Return conservative default risk score
            return 0.5
    
    def get_detailed_assessment(self, strategy_address: str) -> RiskAssessment:
        """
        Complete detailed risk assessment
        """
        try:
            # Extract features
            features = self._extract_strategy_features(strategy_address)
            feature_vector = [features[col] for col in self.feature_columns]
            feature_vector_scaled = self.scaler.transform([feature_vector])
            
            # Predict risk score
            risk_score = self.model.predict(feature_vector_scaled)[0]
            risk_score = float(np.clip(risk_score, 0, 1))
            
            # Calculate confidence based on model uncertainty (simplified)
            # In production, this could use ensemble variance or other uncertainty measures
            feature_variance = np.var(feature_vector_scaled)
            confidence = 1 - min(0.4, feature_variance)  # Higher variance = lower confidence
            
            # Determine risk level
            if risk_score < self.risk_thresholds['low']:
                risk_level = 'LOW'
            elif risk_score < self.risk_thresholds['medium']:
                risk_level = 'MEDIUM'
            elif risk_score < self.risk_thresholds['high']:
                risk_level = 'HIGH'
            else:
                risk_level = 'CRITICAL'
            
            # Calculate individual risk factors
            risk_factors = self._calculate_risk_factors(features)
            
            # Identify strategy type
            strategy_type = self._identify_strategy_type(strategy_address)
            
            # Generate recommendations
            recommendations = self._generate_recommendations(risk_score, risk_factors, strategy_type)
            
            # Check for anomalies
            if self.anomaly_detector:
                is_anomaly = self.anomaly_detector.predict(feature_vector_scaled)[0] == -1
                if is_anomaly:
                    recommendations.insert(0, "ANOMALY DETECTED: Strategy exhibits unusual risk patterns")
                    confidence *= 0.8  # Reduce confidence for anomalies
            
            return RiskAssessment(
                strategy_address=strategy_address,
                risk_score=risk_score,
                risk_level=risk_level,
                confidence=confidence,
                risk_factors=risk_factors,
                recommendations=recommendations,
                timestamp=datetime.now(),
                model_version="1.0-synthetic"
            )
            
        except Exception as e:
            print(f"❌ Detailed assessment error for {strategy_address}: {e}")
            
            # Return conservative default assessment
            return RiskAssessment(
                strategy_address=strategy_address,
                risk_score=0.5,
                risk_level='MEDIUM',
                confidence=0.3,
                risk_factors=RiskFactors(0.5, 0.5, 0.5, 0.5, 0.5, 0.5),
                recommendations=["Unable to assess - manual review required"],
                timestamp=datetime.now(),
                model_version="1.0-fallback"
            )
    
    def assess_portfolio_risk(self, strategy_addresses: List[str], allocations: List[float]) -> Dict:
        """
        Assess portfolio-level risk with multiple strategies
        """
        if len(strategy_addresses) != len(allocations):
            raise ValueError("Strategy addresses and allocations must have same length")
        
        if abs(sum(allocations) - 1.0) > 0.01:
            raise ValueError("Allocations must sum to 1.0")
        
        strategy_assessments = []
        portfolio_risk = 0.0
        
        for address, allocation in zip(strategy_addresses, allocations):
            assessment = self.get_detailed_assessment(address)
            strategy_assessments.append({
                'address': address,
                'allocation': allocation,
                'risk_score': assessment.risk_score,
                'risk_level': assessment.risk_level,
                'confidence': assessment.confidence
            })
            
            portfolio_risk += assessment.risk_score * allocation
        
        # Calculate portfolio diversification benefit
        num_strategies = len(strategy_addresses)
        diversification_benefit = min(0.2, (num_strategies - 1) * 0.05)  # Up to 20% risk reduction
        portfolio_risk = max(0, portfolio_risk - diversification_benefit)
        
        # Determine portfolio risk level
        if portfolio_risk < 0.3:
            portfolio_level = 'LOW'
        elif portfolio_risk < 0.6:
            portfolio_level = 'MEDIUM'
        elif portfolio_risk < 0.8:
            portfolio_level = 'HIGH'
        else:
            portfolio_level = 'CRITICAL'
        
        return {
            'portfolio_risk_score': portfolio_risk,
            'portfolio_risk_level': portfolio_level,
            'diversification_benefit': diversification_benefit,
            'num_strategies': num_strategies,
            'strategy_assessments': strategy_assessments,
            'recommendations': self._get_portfolio_recommendations(portfolio_risk, strategy_assessments),
            'timestamp': datetime.now().isoformat()
        }
    
    def _get_portfolio_recommendations(self, portfolio_risk: float, strategy_assessments: List[Dict]) -> List[str]:
        """Generate portfolio-level recommendations"""
        recommendations = []
        
        if portfolio_risk > 0.8:
            recommendations.append("CRITICAL: Portfolio risk extremely high - immediate rebalancing required")
        elif portfolio_risk > 0.6:
            recommendations.append("HIGH: Portfolio risk elevated - consider reducing high-risk allocations")
        elif portfolio_risk > 0.3:
            recommendations.append("MEDIUM: Portfolio risk acceptable but monitor closely")
        else:
            recommendations.append("LOW: Portfolio risk well-managed")
        
        # Check for concentration risk
        high_risk_allocation = sum(s['allocation'] for s in strategy_assessments if s['risk_score'] > 0.7)
        if high_risk_allocation > 0.3:
            recommendations.append(f"Concentration risk: {high_risk_allocation:.1%} in high-risk strategies")
        
        # Check for diversification
        if len(strategy_assessments) < 3:
            recommendations.append("Consider adding more strategies for better diversification")
        
        return recommendations
    
    def get_risk_trends(self, strategy_address: str, days: int = 30) -> Dict:
        """
        Get risk trend analysis (mock implementation)
        In production, this would track historical risk scores
        """
        # Generate mock historical data
        dates = [datetime.now() - timedelta(days=i) for i in range(days, 0, -1)]
        current_risk = self.assess_strategy_risk(strategy_address)
        
        # Simulate some trend with noise
        trend = np.random.normal(0, 0.01, days)
        risk_history = [max(0, min(1, current_risk + sum(trend[:i+1]))) for i in range(days)]
        
        return {
            'strategy_address': strategy_address,
            'period_days': days,
            'current_risk': current_risk,
            'average_risk': np.mean(risk_history),
            'risk_volatility': np.std(risk_history),
            'trend_direction': 'INCREASING' if risk_history[-1] > risk_history[0] else 'DECREASING',
            'trend_magnitude': abs(risk_history[-1] - risk_history[0]),
            'historical_data': [
                {'date': date.isoformat(), 'risk_score': score}
                for date, score in zip(dates, risk_history)
            ]
        }


# ==============================================================================
# USAGE EXAMPLE AND TESTING
# ==============================================================================

if __name__ == "__main__":
    print("🧪 Testing Risk Assessment API...")
    
    # Initialize API
    risk_api = RiskAssessmentAPI()
    
    # Test strategy addresses (using your deployed contracts)
    test_strategies = {
        "Superlend Strategy": "0x1864adaBc679B62Ae69A838309E5fB9435675D1A",
        "PancakeSwap Strategy": "0x888e307EC9DeF2e038d545251f7b7F6c944b96d5",
        "Lottery Strategy": "0x3dC0390c2C4Aad9b342Dac7e6741662d52963577"
    }
    
    print("\n1. Testing individual strategy risk assessment...")
    for name, address in test_strategies.items():
        risk_score = risk_api.assess_strategy_risk(address)
        print(f"   {name}: Risk Score = {risk_score:.3f}")
    
    print("\n2. Testing detailed risk assessment...")
    detailed = risk_api.get_detailed_assessment(test_strategies["PancakeSwap Strategy"])
    print(f"   Strategy: {detailed.strategy_address}")
    print(f"   Risk Score: {detailed.risk_score:.3f}")
    print(f"   Risk Level: {detailed.risk_level}")
    print(f"   Confidence: {detailed.confidence:.3f}")
    print(f"   Recommendations: {len(detailed.recommendations)} items")
    
    print("\n3. Testing portfolio risk assessment...")
    addresses = list(test_strategies.values())
    allocations = [0.4, 0.3, 0.3]  # 40%, 30%, 30%
    
    portfolio = risk_api.assess_portfolio_risk(addresses, allocations)
    print(f"   Portfolio Risk Score: {portfolio['portfolio_risk_score']:.3f}")
    print(f"   Portfolio Risk Level: {portfolio['portfolio_risk_level']}")
    print(f"   Diversification Benefit: {portfolio['diversification_benefit']:.3f}")
    
    print("\n4. Testing risk trends...")
    trends = risk_api.get_risk_trends(test_strategies["Superlend Strategy"])
    print(f"   Current Risk: {trends['current_risk']:.3f}")
    print(f"   Average Risk (30d): {trends['average_risk']:.3f}")
    print(f"   Trend Direction: {trends['trend_direction']}")
    
    # Save the model
    print("\n5. Saving model...")
    model_dir = "ml-risk/models"
    os.makedirs(model_dir, exist_ok=True)
    risk_api.save_model(f"{model_dir}/anomaly_risk_model.joblib")
    
    print("\n✅ Risk Assessment API testing complete!")