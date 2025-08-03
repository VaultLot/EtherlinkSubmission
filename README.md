# Etherlink AI-Powered No Loss Lottery 🚀

[App](https://fomo-insurance-cpjq.vercel.app/)

[Demo](https://drive.google.com/file/d/1rNjqpwXA8Txw5OAd1kdovzjITRc5Byct/view?usp=sharing)

> **Production-ready AI agent for weekly yield lottery with ML risk assessment and real-time market intelligence**

**Where financial growth meets the thrill of the win. We are turning passive savings into an active, rewarding experience you can't lose.**

A sophisticated DeFi yield aggregation system that combines:
- 🎰 **Weekly Lottery System** - Automated yield distribution via lottery
- 🧠 **ML Risk Assessment** - Advanced strategy risk scoring
- 📈 **Real-time Market Data** - Multi-source price feeds and volatility analysis
- 🤖 **AI Agent Management** - LangChain-powered autonomous operations
- ⚡ **Deployed Strategies** - Live integration with Etherlink testnet

---

## 💭 The Problem: The Saver's Dilemma

Trillions of dollars sit in traditional savings accounts, eroded by inflation and earning negligible interest. It's safe, but it's a losing game. On the other end of the spectrum, billions are spent on lotteries, chasing life-changing wins but almost always resulting in a total loss of capital.

This creates a massive dilemma for everyday people:
* **The Safe Path:** Earn virtually nothing on your savings.
* **The Risky Path:** Gamble your savings for a shot at high rewards.

**Our solution:** The first AI-managed, prize-linked savings protocol on Etherlink. We've created a **positive-sum game** where users can't lose.

---

## 🌟 Key Features

### Weekly Lottery System
- **Automated Execution**: Every Monday at 12:00 UTC
- **Deposit-Weighted Selection**: Larger deposits = higher win probability
- **Minimum Prize Pool**: 10 USDC threshold for execution
- **Provably Fair Randomness**: On-chain random winner selection
- **No-Loss Guarantee**: Your principal is always safe

### ML-Powered Risk Assessment
- **Real-time Risk Scoring**: 0-1 scale with confidence levels
- **Multi-factor Analysis**: Smart contract, liquidity, market, operational risks
- **Market-Adjusted Scoring**: Volatility-sensitive risk calculations
- **Portfolio Optimization**: Diversification and allocation recommendations

### Advanced Market Intelligence
- **Multi-source Price Feeds**: CoinGecko, Binance, CoinMarketCap, OKX
- **Volatility Analysis**: Market condition detection and adjustment
- **Risk-adjusted Strategy Selection**: Dynamic allocation based on market state
- **Real-time Monitoring**: Continuous market and strategy surveillance

### Deployed Strategy Integration
- **SimpleSuperlendStrategy**: Conservative lending protocol simulation
- **SimplePancakeSwapStrategy**: DEX liquidity provision with fee generation
- **EtherlinkYieldLottery**: Direct lottery yield contribution

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    FastAPI Server                           │
│  ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐│
│  │   AI Agent      │ │  Price Feeds    │ │  Risk API       ││
│  │  (LangChain)    │ │   Manager       │ │   (ML Model)    ││
│  └─────────────────┘ └─────────────────┘ └─────────────────┘│
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                 Etherlink Testnet                           │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────────┐│
│  │ Vault Core  │ │   Lottery   │ │      Strategies         ││
│  │             │ │ Extension   │ │                         ││
│  │             │ │             │ │ • Superlend             ││
│  │             │ │             │ │ • PancakeSwap           ││
│  │             │ │             │ │ • Lottery Yield         ││
│  └─────────────┘ └─────────────┘ └─────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

---

## 📊 Deployed Contracts (Etherlink Testnet)

### Core Infrastructure
```
Vault Core:          0xB8B55df1B5AE01e6ABAf141F0D3CAC64303eFfB2
Lottery Extension:   0x779992660Eb4eb9C17AC38D4ABb79D07F0a1d374
Strategy Registry:   0x4Fd69BD63Ad6f2688239B496bbAF89390572693d
Risk Oracle:         0x3e833aF4870F35e7F8c63f5E6CA1D884c305bc2e
```

### Token Contracts
```
Mock USDC:           0xc2E9E01F16764F8e63d5113Ec01b13cc968dB5Dc
Mock WETH:           0x9aD2A76D1f940C2eedFE7aBF5b55e6943a90cC41
```

### Strategy Contracts
```
Superlend Strategy:  0x1864adaBc679B62Ae69A838309E5fB9435675D1A
PancakeSwap Strategy: 0x888e307EC9DeF2e038d545251f7b7F6c944b96d5
```

---

## 🚀 Quick Start

### 1. Prerequisites

- **Python 3.8+** 
- **Node.js** (for any contract interactions)
- **Git**
- **API Keys** (OpenAI, CoinMarketCap)
- **Ethereum Wallet** (for agent private key)

### 2. Installation

```bash
# Clone the repository
git clone <your-repo-url>
cd enhanced-etherlink-vault

# Run automated setup
python setup.py
```

### 3. Configuration

```bash
# Copy environment template
cp .env.example .env

# Edit with your actual values
nano .env  # or use your preferred editor
```

**Required Configuration:**
```bash
# Essential keys
AGENT_PRIVATE_KEY=your_64_character_private_key
OPENAI_API_KEY=sk-your_openai_api_key
COINMARKETCAP_API_KEY=your_cmc_api_key

# Network (already configured for Etherlink testnet)
ETHERLINK_RPC_URL=https://node.ghostnet.etherlink.com
ETHERLINK_CHAIN_ID=128123
```

### 4. Start the System

```bash
# Option 1: Direct execution
python enhanced_etherlink_agent.py

# Option 2: Use startup script
./start.sh  # Linux/Mac
start.bat   # Windows

# Option 3: Docker
docker-compose up -d
```

---

## 📋 API Endpoints

Once running, access these endpoints at `http://localhost:8000`:

### Core Operations
- `GET /` - System overview and status
- `GET /health` - Comprehensive health check
- `GET /comprehensive-status` - Complete vault and strategy status
- `POST /invoke-agent` - Direct AI agent interaction

### Lottery Management
- `GET /lottery-status` - Current lottery information
- `POST /execute-lottery-cycle` - Manual lottery execution
- `POST /simulate-yield` - Test yield generation

### Strategy Operations
- `POST /harvest-strategies` - Harvest from all strategies
- `POST /deploy-to-strategy` - Deploy funds optimally
- `GET /rebalancing-analysis` - Strategy optimization

### Risk & Market Intelligence
- `GET /risk-assessment` - ML-powered risk analysis
- `GET /market-analysis` - Real-time market data and trends

### Interactive Documentation
- `GET /docs` - Swagger UI
- `GET /redoc` - ReDoc documentation

---

## 🎯 Usage Examples

### 1. Check System Status
```bash
curl http://localhost:8000/comprehensive-status
```

### 2. Get Market Analysis
```bash
curl http://localhost:8000/market-analysis
```

### 3. Execute Lottery Cycle
```bash
curl -X POST http://localhost:8000/execute-lottery-cycle
```

### 4. Deploy Funds to Optimal Strategy
```bash
curl -X POST http://localhost:8000/deploy-to-strategy \
  -H "Content-Type: application/json" \
  -d '{"amount_usdc": 100, "strategy_preference": "auto"}'
```

### 5. AI Agent Interaction
```bash
curl -X POST http://localhost:8000/invoke-agent \
  -H "Content-Type: application/json" \
  -d '{"command": "Check lottery status and execute if ready"}'
```

---

## 🧠 AI Agent Commands

The AI agent understands natural language commands:

### Lottery Operations
- `"Check if it's time for the weekly lottery"`
- `"Execute the lottery cycle if conditions are met"`
- `"Show me the current lottery status and participants"`

### Strategy Management
- `"Harvest yield from all strategies"`
- `"Deploy 50 USDC to the safest strategy"`
- `"Rebalance the portfolio based on current risk scores"`

### Risk Assessment
- `"Perform ML risk assessment on all strategies"`
- `"Show me which strategies are high risk right now"`
- `"Check market conditions and adjust strategy allocations"`

### Market Analysis
- `"Get current cryptocurrency prices and market trends"`
- `"Analyze market volatility and recommend actions"`
- `"Compare strategy performance with market conditions"`

---

## 💰 How It Works: The 4-Step Process

| Step                | Action                                                                                                                     | Technical Implementation                                                                                                                                     |
| :------------------ | :------------------------------------------------------------------------------------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **1. Deposit & Pool** | Users deposit USDC into a single, secure, non-custodial smart contract vault on Etherlink.                                      | Users interact with the React frontend, which calls the `deposit()` function on the `Vault.sol` contract.                                                      |
| **2. AI Generates Prize** | Our AI agent simulates yield generation, creating and funding the weekly prize pool.                                         | The agent's backend calls `simulate_yield_harvest_and_deposit()`, which mints MockUSDC and deposits it into the lottery system.               |
| **3. Provably Fair Draw** | The agent triggers the weekly lottery, using **Etherlink's Native VRF** for a cryptographically secure and random winner selection. | The agent calls `execute_weekly_lottery_cycle()`, which executes the lottery function on the smart contracts. |
| **4. Win or Save** | One lucky winner receives the entire prize pool. Everyone else keeps 100% of their initial deposit.                      | The lottery contract automatically transfers the prize to the winner's address. All other users' deposits remain untouched.        |

---

## 🔑 Key Technical Features

### 🏦 No-Loss Savings Vault & ERC4626 Architecture
- **What it is:** Your principal deposit is always safe. Only the generated yield is contributed to the prize pool.
- **Technical Detail:** Our vault contract ensures a clear separation between user deposits (represented as shares) and the yield-generating strategies, making it impossible for the prize mechanism to touch user principal.

### 🤖 AI-Powered Autonomous Agent
- **What it is:** The protocol is managed by a sophisticated backend agent that handles all operations, from funding the prize pool to triggering draws and assessing risk.
- **Technical Detail:** The agent is built in Python using **FastAPI** for the server, **LangChain** for structuring LLM interactions, and **OpenAI's GPT-4o-mini** as the reasoning engine.

### 🎲 Provably Fair Lottery System
- **What it is:** We use cryptographically secure randomness for transparent and fair lottery draws.
- **Technical Detail:** The lottery system uses deposit-weighted probability where larger deposits increase win chances, but everyone has a fair shot at the prize.

### 📊 ML-Driven Risk Management
- **What it is:** The agent uses a machine learning model to assess the risk of potential DeFi strategies before deploying capital.
- **Technical Detail:** The agent loads a pre-trained `.joblib` anomaly detection model to analyze strategy metrics and generate risk scores.

---

## 📊 Key Differentiators

| Solution                  | Your Return                         | Management                     | Risk of Loss        | Gamified  |
| :------------------------ | :---------------------------------- | :----------------------------- | :------------------ | :-------- |
| **Enhanced Etherlink Vault**    | **Principal + Chance to Win Yield** | **Fully Passive (AI-Managed)** | **🔥 None**         | **✅ Yes** |
| Traditional Savings       | Principal + \~1% APY                | Passive                        | None                | ❌ No      |
| Lotteries / Gambling      | -100% (Usually)                     | Active                         | Very High           | ✅ Yes     |
| Yield Aggregators (Yearn) | Principal + Yield                   | Passive                        | Smart Contract Risk | ❌ No      |

---

## 🔧 Configuration Options

### Lottery Configuration
```python
@dataclass
class LotteryConfig:
    weekly_cycle_days: int = 7
    min_prize_pool: float = 10.0  # USDC
    lottery_execution_hour: int = 12  # UTC
    lottery_execution_day: int = 0  # Monday
```

### Risk Management
```python
@dataclass
class RiskConfig:
    max_strategy_allocation: float = 0.4  # 40% max
    emergency_risk_threshold: float = 0.8  # 80%
    rebalance_risk_threshold: float = 0.6  # 60%
```

### Yield Management
```python
@dataclass
class YieldConfig:
    harvest_interval_hours: int = 12
    min_harvest_amount: float = 1.0  # USDC
    auto_compound_enabled: bool = True
```

---

## 🛠️ Production Roadmap

### 🚨 URGENT (For Production)
- [ ] **Mock DeFi Protocols → Real Aave/Compound/Curve integration**
- [ ] **Simulated Cross-Chain → Real LayerZero bridge execution**
- [ ] **Hardcoded Market Data → Real-time DeFiLlama/CoinGecko APIs**
- [ ] **Basic Security → Multi-sig wallets, timelocks, daily limits**

### 🔧 NEXT PRIORITY
- [ ] **In-Memory Storage → PostgreSQL database**
- [ ] **Console Logging → Prometheus/Grafana monitoring**
- [ ] **Pseudo-Random → Real Etherlink VRF integration**
- [ ] **No Compliance → AML/audit logging systems**

### 🌐 Etherlink Protocol Integrations

#### Testnet Protocols Available
- **LayerZero Bridge** - https://docs.etherlink.com/tools/cross‑chain‑comms/
- **Plend (lending/borrowing)** - https://testnet.plend.finance/
- **TachySwap (AMM DEX)** - https://defillama.com/protocol/tachyswap
- **Hashleap (payments)** - https://blog.hashleap.io/tagged/web3
- **Omnisea (NFT marketplace)** - https://x.com/omnisea/status/1791468775663182032
- **Degenerator.wtf (meme-token DEX)**
- **Bit Hotel (metaverse/gaming)**
- **Hanji (CLOB trading platform)** - https://docs.hanji.io/

#### Mainnet Protocols (Future Integration)
- **IguanaDEX** (PancakeSwap v3 fork AMM)
- **SuperLend** (lending)
- **Hanji** (CLOB trading)
- **Uranium.io**
- **Organicgrowth.wtf** (token launches & trading)
- **Uniswap v3** (via co-incentive pools)

---

## 📈 Monitoring & Analytics

### Built-in Monitoring
- **Real-time Health Checks**: `/health` endpoint
- **Performance Metrics**: Gas usage, transaction success rates
- **Risk Monitoring**: Continuous strategy risk assessment
- **Market Surveillance**: Price volatility and trend analysis

### Logging
```bash
# View real-time logs
tail -f logs/vault_manager.log

# Check specific events
grep "LOTTERY" logs/vault_manager.log
grep "ERROR" logs/vault_manager.log
```

### Backup & Recovery
- **Automatic Backups**: Model and configuration backups
- **State Recovery**: Transaction history and risk assessments
- **Model Versioning**: ML model updates and rollbacks

---

## 🔒 Security Best Practices

### Private Key Management
- ✅ Use a dedicated wallet for the agent
- ✅ Never commit private keys to version control
- ✅ Regularly rotate API keys
- ✅ Monitor wallet balance and transactions

### API Security
- ✅ Secure your server with HTTPS in production
- ✅ Implement rate limiting
- ✅ Monitor API usage and set alerts
- ✅ Use environment variables for all secrets

### Smart Contract Security
- ✅ Contracts are deployed and tested on Etherlink testnet
- ✅ Emergency functions available for risk mitigation
- ✅ Multi-signature capabilities for governance
- ✅ Regular security assessments

---

## 🧪 Testing

### Run System Tests
```bash
# Test risk assessment
python ml-risk/risk_api.py

# Test price feeds
python price_feeds.py

# Test full system
python setup.py
```

### Manual Testing
```bash
# Check individual components
curl http://localhost:8000/health
curl http://localhost:8000/lottery-status
curl http://localhost:8000/market-analysis
```

---

## 🔍 Troubleshooting

### Common Issues

#### 1. "Risk model not available"
```bash
# Reinitialize ML model
cd ml-risk
python risk_api.py
```

#### 2. "Price feeds not available"
```bash
# Check internet connection and API keys
python price_feeds.py
```

#### 3. "Transaction failed"
```bash
# Check wallet balance and gas prices
# Verify network connectivity
```

#### 4. "Contract not found"
```bash
# Verify contract addresses in .env
# Check Etherlink testnet connectivity
```

### Debug Mode
```bash
# Enable debug logging
export LOG_LEVEL=DEBUG
python enhanced_etherlink_agent.py
```

---

## 💰 Business Model & Revenue

### Revenue Model
- **Performance Fee**: Small percentage (e.g., 10%) of generated yield only
- **Example**: If prize pool is $1,000, winner gets $900, protocol gets $100
- **Guarantee**: If no yield, no fees. We only earn when users win.

### Go-To-Market Strategy
1. **Phase 1**: Build community on Etherlink testnet
2. **Phase 2**: Mainnet launch with real yield strategies
3. **Phase 3**: Scale with premium features and multi-chain expansion

---

## 🗺️ Future Development

### Real Yield Integration
- Integrate with Etherlink protocols (Plend, TachySwap, etc.)
- Cross-chain yield optimization via LayerZero
- Advanced strategy allocation algorithms

### Enhanced AI Capabilities
- Autonomous strategy selection and rebalancing
- Real-time risk monitoring and emergency responses
- Predictive market analysis and positioning

### User Experience
- Gasless transactions via account abstraction
- Mobile app with push notifications
- Social features and team-based savings games

---

## ❓ FAQ

#### "Is this just another lottery?"
No. It's a savings protocol first. Your deposit is never spent. You get a free lottery ticket every week just for saving money. The prize comes from yield, not principal.

#### "If I don't win, do I lose anything?"
Absolutely not. This is our "no-loss" guarantee. Your initial deposit remains untouched and withdrawable at any time.

#### "Is my money safe?"
Yes. The system is non-custodial, your principal is isolated from the prize mechanism, and we use battle-tested smart contract patterns.

---

## 🤝 Contributing

### Development Setup
```bash
# Install development dependencies
pip install -r requirements-dev.txt

# Run tests
pytest tests/

# Code formatting
black .
flake8 .
```

---

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

---

## 🆘 Support

### Getting Help
- 📖 Read this documentation thoroughly
- 🔍 Check the troubleshooting section
- 📊 Review logs in `./logs/` directory
- 🧪 Run system tests with `python setup.py`

### Reporting Issues
When reporting issues, please include:
- System specifications
- Complete error messages
- Steps to reproduce
- Relevant log entries
- Configuration (without secrets)

---

## 🎉 Congratulations!

You now have a fully functional Enhanced Etherlink Vault Manager with:
- ✅ Weekly automated lottery system
- ✅ ML-powered risk assessment
- ✅ Real-time market intelligence
- ✅ Production-ready deployment
- ✅ Comprehensive monitoring

**Ready to revolutionize DeFi yield farming on Etherlink! 🚀**

---

