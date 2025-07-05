import json
import os
import requests
from typing import Dict, Any, Optional
from dotenv import load_dotenv
from langchain.tools import tool

load_dotenv()

class OllamaLLMPlanner:
    """LLM Planner supporting both OpenAI and Ollama (local) models"""
    
    def __init__(self, config: Dict[str, Any]):
        """Initialize with support for multiple LLM providers"""
        self.config = config
        self.provider = config.get('provider', 'ollama')  # Default to ollama
        self.model = config.get('model', 'llama3.2')
        self.temperature = config.get('temperature', 0.1)
        self.max_tokens = config.get('max_tokens', 2000)
        
        if self.provider == 'openai':
            self.api_key = os.getenv('OPENAI_API_KEY')
            if not self.api_key:
                print("⚠️ OPENAI_API_KEY not found, falling back to Ollama")
                self.provider = 'ollama'
        
        # Ollama configuration
        self.ollama_host = config.get('ollama_host', 'http://localhost:11434')
        
        print(f"🤖 LLM Provider: {self.provider}")
        print(f"🧠 Model: {self.model}")
    
    def generate_vault_strategy(self, market_data: Dict[str, Any], vault_status: Dict[str, Any]) -> Dict[str, Any]:
        """Generate vault management strategy using local LLM"""
        
        prompt = f"""
You are an expert DeFi vault manager for a Flow blockchain prize savings protocol. 

Current Vault Status:
{json.dumps(vault_status, indent=2)}

Market Data:
{json.dumps(market_data, indent=2)}

Generate a safe vault management strategy. Focus on:
1. Prize pool optimization (VRF lottery system)
2. Risk management and fund safety
3. Yield opportunities while maintaining security
4. User fund protection as top priority

Respond with ONLY a valid JSON object in this exact format:
{{
    "strategy_type": "vault_management",
    "primary_action": "optimize_prize_pool|harvest_yield|trigger_lottery|emergency_exit",
    "risk_level": "low|medium|high", 
    "actions": [
        {{
            "action_type": "simulate_yield_harvest_and_deposit|trigger_lottery_draw|deploy_to_strategy_with_risk_check",
            "parameters": {{
                "amount_usdc": 150.0
            }},
            "priority": 1,
            "reasoning": "Brief explanation"
        }}
    ],
    "expected_outcome": {{
        "prize_pool_target": 200.0,
        "risk_score": 0.2,
        "estimated_timeline": "1-7 days"
    }},
    "recommendations": [
        "Brief actionable recommendations"
    ]
}}
"""
        
        if self.provider == 'ollama':
            return self._generate_with_ollama(prompt)
        else:
            return self._generate_with_openai(prompt)
    

    # Replace the _generate_with_ollama method in ollama_llm_planner.py

def _generate_with_ollama(self, prompt: str) -> Dict[str, Any]:
    """Generate strategy using local Ollama model with better error handling"""
    try:
        # Try the newer Ollama API format first
        response = requests.post(
            f"{self.ollama_host}/api/generate",
            json={
                "model": self.model,
                "prompt": prompt,
                "stream": False,
                "format": "json",  # Request JSON format
                "options": {
                    "temperature": self.temperature,
                    "num_predict": self.max_tokens,
                    "stop": ["```", "END"]
                }
            },
            timeout=60
        )
        
        if response.status_code != 200:
            print(f"⚠️ Ollama API error (status {response.status_code}): {response.text}")
            return self._fallback_strategy()
        
        result = response.json()
        content = result.get('response', '')
        
        print(f"🤖 Ollama Response: {content[:200]}...")
        
        # Extract JSON from response
        strategy = self._extract_json_from_response(content)
        
        if not strategy:
            print("⚠️ Could not parse Ollama response as JSON, using fallback")
            return self._fallback_strategy()
        
        return strategy
        
    except requests.exceptions.Timeout:
        print("⚠️ Ollama request timed out, using fallback")
        return self._fallback_strategy()
    except requests.exceptions.ConnectionError:
        print("⚠️ Could not connect to Ollama, using fallback")
        return self._fallback_strategy()
    except Exception as e:
        print(f"⚠️ Ollama generation failed: {e}")
        return self._fallback_strategy()

def check_ollama_available(self) -> bool:
    """Check if Ollama is running and model is available"""
    try:
        # Check if Ollama is running
        response = requests.get(f"{self.ollama_host}/api/tags", timeout=5)
        if response.status_code != 200:
            print(f"⚠️ Ollama not responding (status {response.status_code})")
            return False
        
        # Check if our model is available
        models = response.json().get('models', [])
        model_names = [model.get('name', '').split(':')[0] for model in models]
        
        if self.model not in model_names:
            print(f"⚠️ Model {self.model} not found. Available: {model_names}")
            print(f"   Run: ollama pull {self.model}")
            return False
        
        print(f"✅ Ollama model {self.model} is available")
        return True
        
    except Exception as e:
        print(f"⚠️ Ollama not available: {e}")
        return False
    
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
                    "messages": [{"role": "user", "content": prompt}],
                    "temperature": self.temperature,
                    "max_tokens": self.max_tokens
                },
                timeout=30
            )
            
            if response.status_code != 200:
                raise Exception(f"OpenAI API error: {response.text}")
            
            result = response.json()
            content = result['choices'][0]['message']['content']
            
            print(f"🤖 OpenAI Response: {content[:200]}...")
            
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
    
    def check_ollama_available(self) -> bool:
        """Check if Ollama is running and model is available"""
        try:
            # Check if Ollama is running
            response = requests.get(f"{self.ollama_host}/api/tags", timeout=5)
            if response.status_code != 200:
                return False
            
            # Check if our model is available
            models = response.json().get('models', [])
            model_names = [model.get('name', '').split(':')[0] for model in models]
            
            if self.model not in model_names:
                print(f"⚠️ Model {self.model} not found. Available: {model_names}")
                print(f"   Run: ollama pull {self.model}")
                return False
            
            return True
            
        except Exception as e:
            print(f"⚠️ Ollama not available: {e}")
            return False


@tool
def ai_strategy_advisor(current_situation: str = "general_analysis") -> str:
    """
    Use local AI to analyze current vault situation and recommend strategies.
    
    Args:
        current_situation: Description of the current situation to analyze
    """
    print(f"Tool: ai_strategy_advisor - Situation: {current_situation}")
    
    # Initialize Ollama LLM planner
    llm_config = {
        'provider': 'ollama',
        'model': 'llama3.2',  # or 'qwen2.5', 'mistral', etc.
        'temperature': 0.1,
        'max_tokens': 1500,
        'ollama_host': 'http://localhost:11434'
    }
    
    try:
        planner = OllamaLLMPlanner(llm_config)
        
        # Check if Ollama is available
        if not planner.check_ollama_available():
            return """
❌ Local AI (Ollama) not available. 

To set up local AI:
1. Install Ollama: https://ollama.ai
2. Pull a model: ollama pull llama3.2
3. Start Ollama: ollama serve
4. Retry this command

Using fallback rule-based strategy instead.
            """
        
        # Get current vault status (you could make this dynamic)
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
        
        # Generate strategy using local AI
        strategy = planner.generate_vault_strategy(market_data, vault_status)
        
        return f"""
🤖 AI Strategy Recommendation:

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


# Setup instructions for users
def setup_ollama_instructions():
    return """
🤖 Setting Up Local AI (Ollama) for Vault Management

1. Install Ollama:
   curl -fsSL https://ollama.ai/install.sh | sh

2. Pull a model (choose one):
   ollama pull llama3.2        # 2B params, fast
   ollama pull qwen2.5:7b      # 7B params, better reasoning
   ollama pull mistral         # Good balance

3. Start Ollama:
   ollama serve

4. Test it:
   ollama run llama3.2 "Hello"

5. Update your config to use the model:
   model: 'llama3.2' or 'qwen2.5:7b' or 'mistral'

Now your vault agent will have local AI reasoning! 🎉
    """

if __name__ == "__main__":
    print(setup_ollama_instructions())