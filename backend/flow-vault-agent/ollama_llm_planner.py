# Replace your ollama_llm_planner.py with this OpenAI-focused version

"""
Enhanced LLM Planner with OpenAI support for reliable AI strategy recommendations
"""

import json
import os
import requests
from typing import Dict, Any, Optional
from dotenv import load_dotenv
from langchain.tools import tool

load_dotenv()

class OpenAILLMPlanner:
    """LLM Planner using OpenAI for reliable strategy generation"""
    
    def __init__(self, config: Dict[str, Any]):
        """Initialize with OpenAI configuration"""
        self.config = config
        self.provider = config.get('provider', 'openai')
        self.model = config.get('model', 'gpt-4o-mini')
        self.temperature = config.get('temperature', 0.1)
        self.max_tokens = config.get('max_tokens', 1500)
        
        # OpenAI configuration
        self.api_key = os.getenv('OPENAI_API_KEY')
        if not self.api_key:
            raise ValueError("OPENAI_API_KEY not found in environment variables")
        
        print(f"🤖 LLM Provider: {self.provider}")
        print(f"🧠 Model: {self.model}")
    
    def generate_vault_strategy(self, market_data: Dict[str, Any], vault_status: Dict[str, Any]) -> Dict[str, Any]:
        """Generate vault management strategy using OpenAI"""
        
        prompt = f"""
You are an expert DeFi vault manager for a Flow blockchain prize savings protocol.

Current Vault Status:
- Liquid USDC: {vault_status.get('liquid_usdc', 0)} USDC
- Prize Pool: {vault_status.get('prize_pool', 0)} USDC  
- Last Winner: {vault_status.get('last_winner', 'None')}
- Situation: {vault_status.get('situation', 'Normal operations')}

Market Context:
- Flow VRF Available: {market_data.get('flow_vrf_available', True)}
- Risk Model Available: {market_data.get('risk_model_available', True)}
- Gas Conditions: {market_data.get('gas_price', 'Normal')}

TASK: Generate a safe vault management strategy focusing on:
1. Prize pool optimization for weekly VRF lottery
2. User fund safety (top priority) 
3. Risk management and security
4. Weekly lottery prize generation

Respond with ONLY valid JSON in this exact format:
{{
    "strategy_type": "vault_management",
    "primary_action": "optimize_prize_pool",
    "risk_level": "low",
    "actions": [
        {{
            "action_type": "simulate_yield_harvest_and_deposit",
            "parameters": {{
                "amount_usdc": 150.0
            }},
            "priority": 1,
            "reasoning": "Generate weekly lottery prize pool"
        }}
    ],
    "expected_outcome": {{
        "prize_pool_target": 150.0,
        "risk_score": 0.2,
        "estimated_timeline": "immediate"
    }},
    "recommendations": [
        "Create modest weekly prize pool",
        "Maintain low risk approach",
        "Focus on VRF lottery system"
    ]
}}
"""
        
        return self._generate_with_openai(prompt)
    
    def _generate_with_openai(self, prompt: str) -> Dict[str, Any]:
        """Generate strategy using OpenAI API"""
        try:
            response = requests.post(
                "https://api.openai.com/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json"
                },
                json={
                    "model": self.model,
                    "messages": [
                        {
                            "role": "system", 
                            "content": "You are a DeFi vault manager. Respond only with valid JSON strategy objects. No additional text."
                        },
                        {
                            "role": "user", 
                            "content": prompt
                        }
                    ],
                    "temperature": self.temperature,
                    "max_tokens": self.max_tokens
                },
                timeout=30
            )
            
            if response.status_code != 200:
                print(f"❌ OpenAI API error: {response.status_code} - {response.text}")
                return self._fallback_strategy()
            
            result = response.json()
            content = result['choices'][0]['message']['content']
            
            print(f"🤖 OpenAI Response: {content[:200]}...")
            
            # Extract JSON from response
            strategy = self._extract_json_from_response(content)
            return strategy if strategy else self._fallback_strategy()
            
        except Exception as e:
            print(f"⚠️ OpenAI generation failed: {e}")
            return self._fallback_strategy()
    
    def _extract_json_from_response(self, content: str) -> Optional[Dict[str, Any]]:
        """Extract JSON strategy from LLM response"""
        try:
            # Try parsing as direct JSON
            return json.loads(content)
        except json.JSONDecodeError:
            try:
                # Look for JSON within the response
                import re
                json_match = re.search(r'\{.*\}', content, re.DOTALL)
                if json_match:
                    return json.loads(json_match.group())
            except:
                pass
        return None
    
    def _fallback_strategy(self) -> Dict[str, Any]:
        """Fallback strategy when LLM fails"""
        return {
            "strategy_type": "vault_management",
            "primary_action": "optimize_prize_pool",
            "risk_level": "low",
            "actions": [
                {
                    "action_type": "simulate_yield_harvest_and_deposit",
                    "parameters": {"amount_usdc": 150.0},
                    "priority": 1,
                    "reasoning": "Fallback: Generate modest prize pool for weekly lottery"
                }
            ],
            "expected_outcome": {
                "prize_pool_target": 150.0,
                "risk_score": 0.2,
                "estimated_timeline": "immediate"
            },
            "recommendations": [
                "Use fallback strategy due to LLM unavailability",
                "Generate modest prize pool for weekly lottery"
            ]
        }
    
    def check_api_available(self) -> bool:
        """Check if OpenAI API is accessible"""
        try:
            response = requests.post(
                "https://api.openai.com/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json"
                },
                json={
                    "model": "gpt-4o-mini",
                    "messages": [{"role": "user", "content": "test"}],
                    "max_tokens": 5
                },
                timeout=10
            )
            return response.status_code == 200
        except Exception as e:
            print(f"⚠️ OpenAI API not available: {e}")
            return False


# Enhanced agent tool using OpenAI LLM planner
@tool
def ai_strategy_advisor(current_situation: str = "general_analysis") -> str:
    """
    Use OpenAI to analyze current vault situation and recommend strategies.
    
    Args:
        current_situation: Description of the current situation to analyze
    """
    print(f"Tool: ai_strategy_advisor - Situation: {current_situation}")
    
    # Initialize OpenAI LLM planner
    llm_config = {
        'provider': 'openai',
        'model': 'gpt-4o-mini',
        'temperature': 0.1,
        'max_tokens': 1500
    }
    
    try:
        planner = OpenAILLMPlanner(llm_config)
        
        # Check if OpenAI API is available
        if not planner.check_api_available():
            return """
❌ OpenAI API not available. 

Please check:
1. OPENAI_API_KEY is set in .env file
2. API key is valid and has credits
3. Internet connection is working

Using fallback rule-based strategy instead.
            """
        
        # Get current vault status (you could make this dynamic by calling other tools)
        vault_status = {
            "liquid_usdc": 290.0,  # From your health check
            "prize_pool": 0.0,
            "last_winner": "0x0000000000000000000000000000000000000000",
            "strategy_type": "vrf_lottery",
            "situation": current_situation
        }
        
        market_data = {
            "flow_vrf_available": True,
            "gas_price": "normal",
            "risk_model_available": True,
            "situation_description": current_situation
        }
        
        # Generate strategy using OpenAI
        strategy = planner.generate_vault_strategy(market_data, vault_status)
        
        return f"""
🤖 AI Strategy Recommendation (OpenAI):

Strategy Type: {strategy['strategy_type']}
Primary Action: {strategy['primary_action']}
Risk Level: {strategy['risk_level']}

Actions to Take:
{json.dumps(strategy['actions'], indent=2)}

Expected Outcome:
{json.dumps(strategy['expected_outcome'], indent=2)}

AI Recommendations:
{json.dumps(strategy['recommendations'], indent=2)}
        """
        
    except Exception as e:
        return f"❌ AI strategy advisor failed: {e}\n\nUsing fallback: Recommend 150 USDC yield harvest for weekly lottery."


# Test function
def test_openai_connection():
    """Test OpenAI connection"""
    config = {
        'provider': 'openai',
        'model': 'gpt-4o-mini',
        'temperature': 0.1,
        'max_tokens': 100
    }
    
    try:
        planner = OpenAILLMPlanner(config)
        available = planner.check_api_available()
        print(f"✅ OpenAI API Available: {available}")
        return available
    except Exception as e:
        print(f"❌ OpenAI Test Failed: {e}")
        return False


if __name__ == "__main__":
    print("🧪 Testing OpenAI LLM Planner...")
    test_openai_connection()