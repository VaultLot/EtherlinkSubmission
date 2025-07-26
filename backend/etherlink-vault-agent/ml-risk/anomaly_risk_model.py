#!/usr/bin/env python3
"""
Anomaly Detection Risk Model for DeFi Strategy Assessment
Detects unusual patterns in protocol behavior without requiring labeled data
"""

import requests
import pandas as pd
import joblib
from sklearn.ensemble import IsolationForest
from sklearn.preprocessing import StandardScaler
from sklearn.decomposition import PCA
import numpy as np
import os

# Configuration
ETHERSCAN_API = "https://api.etherscan.io/api"
API_KEY = "8SD7GQBGWGTN5HCADISSATZDWSZD1Y82CC"  # Get from etherscan.io

# Established protocols for baseline (known safe patterns)
BASELINE_PROTOCOLS = [
    "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",  # USDC
    "0xdac17f958d2ee523a2206206994597c13d831ec7",  # USDT  
    "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",  # WETH
    "0x7fc66500c84a76ad7e9c93437bfc5ac33e2ddae9",  # AAVE
    "0xc00e94cb662c3520282e6f5717214004a7f26888",  # COMP
]

def fetch_txns(contract):
    """Fetch transaction data from Etherscan API"""
    params = {
        'module': 'account',
        'action': 'txlist',
        'address': contract,
        'startblock': 0,
        'endblock': 99999999,
        'page': 1,
        'offset': 200,  # More data for better patterns
        'sort': 'desc',
        'apikey': API_KEY
    }
    
    url = ETHERSCAN_API
    r = requests.get(url, params=params)
    r.raise_for_status()
    
    data = r.json()
    if data['status'] == '1':
        return pd.DataFrame(data['result'])
    else:
        print(f"API Error: {data.get('message', 'Unknown error')}")
        return pd.DataFrame()

def engineer_risk_features(transactions):
    """Engineer features specifically for anomaly detection"""
    
    # Convert timestamp
    transactions['timestamp'] = pd.to_datetime(transactions['timeStamp'].astype(int), unit='s')
    transactions['value_eth'] = pd.to_numeric(transactions['value'], errors='coerce') / 1e18
    
    # Method detection
    transactions['method'] = transactions['input'].apply(lambda x: 
        'transfer' if str(x).startswith('0xa9059cbb') else
        'approve' if str(x).startswith('0x095ea7b3') else
        'transferFrom' if str(x).startswith('0x23b872dd') else
        'unknown' if str(x) == '0x' else 'other'
    )
    
    # Time-based analysis
    transactions['hour'] = transactions['timestamp'].dt.hour
    transactions['day_of_week'] = transactions['timestamp'].dt.dayofweek
    
    # Advanced risk features
    features = {}
    
    # Activity patterns
    features['total_txns'] = len(transactions)
    features['unique_users'] = transactions['from'].nunique()
    features['user_concentration'] = transactions['from'].value_counts().iloc[0] / len(transactions) if len(transactions) > 0 else 0
    
    # Value patterns
    features['avg_value'] = transactions['value_eth'].mean()
    features['median_value'] = transactions['value_eth'].median()
    features['value_std'] = transactions['value_eth'].std()
    features['value_skew'] = transactions['value_eth'].skew()
    features['zero_value_ratio'] = (transactions['value_eth'] == 0).mean()
    
    # Temporal patterns
    features['time_span_days'] = (transactions['timestamp'].max() - transactions['timestamp'].min()).days
    features['txns_per_day'] = features['total_txns'] / max(1, features['time_span_days'])
    features['weekend_activity'] = transactions['day_of_week'].isin([5, 6]).mean()
    features['night_activity'] = transactions['hour'].isin(range(22, 6)).mean()
    
    # Method diversity
    method_counts = transactions['method'].value_counts()
    features['method_diversity'] = len(method_counts)
    features['method_entropy'] = -sum((method_counts / len(transactions)) * np.log2(method_counts / len(transactions) + 1e-10))
    
    # Gas patterns (potential risk indicator)
    transactions['gasPrice'] = pd.to_numeric(transactions['gasPrice'], errors='coerce')
    features['avg_gas_price'] = transactions['gasPrice'].mean()
    features['gas_price_volatility'] = transactions['gasPrice'].std()
    
    # Failed transaction ratio (risk indicator)
    features['failed_tx_ratio'] = (transactions['txreceipt_status'] == '0').mean()
    
    # Recent activity surge (potential manipulation)
    recent_7d = transactions[transactions['timestamp'] > (transactions['timestamp'].max() - pd.Timedelta(days=7))]
    features['recent_activity_surge'] = len(recent_7d) / max(1, len(transactions)) * 52  # Annualized
    
    return features

def process_protocol_data(contract_address):
    """Process transaction data for a protocol"""
    print(f"Processing {contract_address}...")
    
    transactions = fetch_txns(contract_address)
    
    if transactions.empty:
        print(f"No data for {contract_address}")
        return None
    
    features = engineer_risk_features(transactions)
    
    print(f"  {len(transactions)} transactions, {features['unique_users']} unique users")
    
    return features

class DeFiAnomalyDetector:
    """Anomaly detection for DeFi protocol risk assessment"""
    
    def __init__(self, contamination=0.1):
        self.contamination = contamination
        self.isolation_forest = IsolationForest(
            contamination=contamination,
            random_state=42,
            n_estimators=100
        )
        self.scaler = StandardScaler()
        self.feature_names = None
        self.is_trained = False
    
    def train_on_baseline(self, baseline_contracts):
        """Train anomaly detector on established protocols"""
        print("Training anomaly detector on baseline protocols...")
        
        baseline_features = []
        successful_contracts = []
        
        for contract in baseline_contracts:
            features = process_protocol_data(contract)
            if features:
                baseline_features.append(features)
                successful_contracts.append(contract)
        
        if not baseline_features:
            raise ValueError("No valid baseline data found")
        
        # Convert to DataFrame
        df = pd.DataFrame(baseline_features)
        self.feature_names = df.columns.tolist()
        
        print(f"Training on {len(df)} baseline protocols")
        print(f"Features: {len(self.feature_names)}")
        
        # Scale features
        X_scaled = self.scaler.fit_transform(df)
        
        # Train anomaly detector
        self.isolation_forest.fit(X_scaled)
        
        # Get baseline scores for reference
        baseline_scores = self.isolation_forest.decision_function(X_scaled)
        print(f"Baseline score range: {baseline_scores.min():.3f} to {baseline_scores.max():.3f}")
        
        self.is_trained = True
        return successful_contracts
    
    def assess_protocol_risk(self, contract_address):
        """Assess risk of a protocol using anomaly detection"""
        if not self.is_trained:
            raise ValueError("Model not trained. Call train_on_baseline() first.")
        
        # Extract features
        features = process_protocol_data(contract_address)
        if not features:
            return {"error": "Could not fetch data", "risk_score": 1.0}
        
        # Convert to DataFrame with same structure
        df = pd.DataFrame([features])
        
        # Ensure same features
        for feature in self.feature_names:
            if feature not in df.columns:
                df[feature] = 0
        df = df[self.feature_names]
        
        # Scale and predict
        X_scaled = self.scaler.transform(df)
        anomaly_score = self.isolation_forest.decision_function(X_scaled)[0]
        is_anomaly = self.isolation_forest.predict(X_scaled)[0] == -1
        
        # Convert to risk score (0 = safe, 1 = risky)
        # More negative anomaly scores = higher risk
        risk_score = max(0, min(1, (0.5 - anomaly_score) / 1.0))
        
        return {
            "contract": contract_address,
            "risk_score": risk_score,
            "is_anomaly": is_anomaly,
            "anomaly_score": anomaly_score,
            "risk_level": self._categorize_risk(risk_score),
            "features": features
        }
    
    def _categorize_risk(self, risk_score):
        """Categorize risk score into levels"""
        if risk_score < 0.3:
            return "LOW"
        elif risk_score < 0.7:
            return "MEDIUM"
        else:
            return "HIGH"
    
    def save_model(self, output_dir="models"):
        """Save trained model"""
        os.makedirs(output_dir, exist_ok=True)
        
        model_data = {
            'isolation_forest': self.isolation_forest,
            'scaler': self.scaler,
            'feature_names': self.feature_names,
            'contamination': self.contamination
        }
        
        joblib.dump(model_data, f'{output_dir}/anomaly_risk_model.joblib')
        print(f"✅ Anomaly detection model saved to {output_dir}/")
    
    @classmethod
    def load_model(cls, model_path="models/anomaly_risk_model.joblib"):
        """Load trained model"""
        model_data = joblib.load(model_path)
        
        detector = cls(contamination=model_data['contamination'])
        detector.isolation_forest = model_data['isolation_forest']
        detector.scaler = model_data['scaler']
        detector.feature_names = model_data['feature_names']
        detector.is_trained = True
        
        return detector

def main():
    """Main training function"""
    print("🔬 DeFi Anomaly Detection Risk Model")
    print("=" * 40)
    
    try:
        # Initialize detector
        detector = DeFiAnomalyDetector(contamination=0.15)
        
        # Train on baseline protocols
        successful_contracts = detector.train_on_baseline(BASELINE_PROTOCOLS)
        
        # Save model
        detector.save_model()
        
        # Test on a new protocol (example)
        print("\n🧪 Testing anomaly detection...")
        test_contract = successful_contracts[0]  # Test on known good contract
        result = detector.assess_protocol_risk(test_contract)
        
        print(f"Test contract: {test_contract}")
        print(f"Risk Score: {result['risk_score']:.3f}")
        print(f"Risk Level: {result['risk_level']}")
        print(f"Is Anomaly: {result['is_anomaly']}")
        
        print("\n🎉 Anomaly detection model training completed!")
        print(f"   - Trained on {len(successful_contracts)} baseline protocols")
        print(f"   - Model saved to models/anomaly_risk_model.joblib")
        print(f"   - Ready for protocol risk assessment")
        
    except Exception as e:
        print(f"❌ Error during training: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()