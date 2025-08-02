
🤖 Autonomous Rebalancing Engine
Every 5 Minutes:

🧠 ML Risk Assessment: Uses your trained risk models to evaluate strategy safety
📊 Market Analysis: Monitors volatility, liquidity, and market stress
🔍 Opportunity Scanning: Identifies optimal yield opportunities across chains

Every 4 Hours:

⚡ Optimal Allocation: ML calculates best fund distribution
💰 Smart Execution: Automatically deploys funds to optimal strategies
🎯 Performance Tracking: Learns from results to improve decisions

Immediate Response:

🚨 Emergency Exits: Automatically exits if strategy risk > 80%
🔄 Market Adaptation: Reduces risk in stress conditions
📈 Yield Maximization: Moves funds to better opportunities

# 1. Start the enhanced agent
python enhanced_etherlink_agent.py

# 2. Test autonomous rebalancing
python autonomous_demo.py

# 3. Monitor autonomous decisions
curl -X GET "http://localhost:8000/rebalancing-status"

# 4. Force immediate rebalance
curl -X POST "http://localhost:8000/force-rebalance"


# Etherlink Prize Savings: The AI-Powered Savings Game

**Where financial growth meets the thrill of the win. We are turning passive savings into an active, rewarding experience you can't lose.**

***

## 💭 The Problem: The Saver's Dilemma

Trillions of dollars sit in traditional savings accounts, eroded by inflation and earning negligible interest. It's safe, but it's a losing game. On the other end of the spectrum, billions are spent on lotteries, chasing life-changing wins but almost always resulting in a total loss of capital.

This creates a massive dilemma for everyday people:
* **The Safe Path:** Earn virtually nothing on your savings.
* **The Risky Path:** Gamble your savings for a shot at high rewards.

This is the market gap. People want the security of savings combined with the excitement and upside of a lottery, without the risk of loss.

***

## 🚀 Our Solution: The AI-Powered, No-Loss Savings Game

**Etherlink Prize Savings** is the first AI-managed, prize-linked savings protocol on the Etherlink blockchain. We've created a **positive-sum game** where users can't lose. By depositing funds, you are not only saving your money securely but also automatically entering a weekly draw to win the entire prize pool generated from the collective yield.

Think of us as an **intelligent, gamified bank account**. Your money is always safe, always yours, but now it also gives you a weekly shot at a better financial future.

### How It Works in 4 Simple Steps

| Step                | Action                                                                                                                     | Technical Implementation                                                                                                                                     |
| :------------------ | :------------------------------------------------------------------------------------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **1. Deposit & Pool** | Users deposit USDC into a single, secure, non-custodial smart contract vault on Etherlink.                                      | Users interact with the React frontend, which calls the `deposit()` function on the `Vault.sol` contract.                                                      |
| **2. AI Generates Prize** | Our AI agent simulates yield generation, creating and funding the weekly prize pool.                                         | The agent's backend calls `simulate_yield_harvest_and_deposit()`, which mints MockUSDC and deposits it into the `EtherlinkVrfYieldStrategy.sol` contract.               |
| **3. Provably Fair Draw** | The agent triggers the weekly lottery, using **Etherlink's Native VRF** for a cryptographically secure and random winner selection. | The agent calls `trigger_lottery_draw()`, which executes the `harvestStrategy()` function on the `Vault.sol` contract, initiating the VRF draw in the strategy. |
| **4. Win or Save** | One lucky winner receives the entire prize pool. Everyone else keeps 100% of their initial deposit.                      | The `EtherlinkVrfYieldStrategy` contract automatically transfers the prize to the winner's address. All other users' shares in the `Vault` remain untouched.        |

***

## 🏛️ The Philosophy: Why A "Positive-Sum Game"?

Finance is too often a zero-sum game. Lotteries are a *negative-sum* game by design. **Etherlink Prize Savings** is built on the principle of a **positive-sum game**:

* **The Winner:** Receives a prize far greater than they could have earned alone.
* **The Participants:** Lose nothing. Their savings remain intact and they benefit from a fun, engaging experience.
* **The Ecosystem:** Grows as more users are onboarded to a safe, compelling Web3 product, increasing overall liquidity and activity on Etherlink.

This philosophy is embodied by our AI agent: it works for the collective good, optimizing the prize potential while guaranteeing the safety of the individual's capital.

***

## 🔑 Key Features & Technical Innovation

We've built a sophisticated system that blends cutting-edge AI with robust blockchain security.

### 🏦 No-Loss Savings Vault & ERC4626 Architecture
* **What it is:** Your principal deposit is always safe. Only the generated yield is contributed to the prize pool.
* **Technical Detail:** Our `Vault.sol` contract is designed based on the principles of the **ERC4626 Tokenized Vault Standard**. This ensures a clear separation between user deposits (represented as shares) and the yield-generating strategies, making it impossible for the prize mechanism to touch user principal.

### 🤖 AI-Powered Autonomous Agent
* **What it is:** The protocol is managed by a sophisticated backend agent that handles all operations, from funding the prize pool to triggering draws and assessing risk.
* **Technical Detail:** The agent is built in Python using **FastAPI** for the server, **LangChain** for structuring LLM interactions, and **OpenAI's GPT-4o-mini** as the reasoning engine. It can interpret high-level commands (e.g., "run the weekly lottery cycle") and execute a multi-step, on-chain plan. This grounds intelligent automation in a transparent, verifiable system.

### 🎲 Provably Fair Lottery with Etherlink Native VRF
* **What it is:** We use Etherlink's built-in Verifiable Random Function for cryptographically secure and auditable randomness, ensuring every lottery draw is transparent and fair.
* **Technical Detail:** Our `EtherlinkVrfYieldStrategy.sol` contract directly integrates with Etherlink's native VRF contract at `0x0000000000000000000000010000000000000001`. This avoids reliance on external oracles, providing a higher level of security and decentralization.

### 📊 ML-Driven Risk Management
* **What it is:** The agent uses a machine learning model to assess the risk of potential DeFi strategies before deploying capital.
* **Technical Detail:** The agent loads a pre-trained `.joblib` anomaly detection model. The `assess_strategy_risk()` tool can analyze a strategy's on-chain metrics (if on Ethereum) to generate a risk score, preventing the agent from allocating funds to high-risk protocols.

### 🔗 FCL & EVM Dual-Compatibility
* **What it is:** A seamless user experience for everyone, whether they use a native Etherlink wallet or a standard EVM wallet like MetaMask.
* **Technical Detail:** Our React frontend uses `wagmi` for EVM wallet connections and `@onEtherlink/fcl` for native Etherlink integration. We've built custom hooks (`useFCLStatus`) to detect the user's connection type and provide a tailored UI, showcasing the power of Etherlink's EVM compatibility.

***

## 🏗️ Technical Architecture

Our system is composed of three core, interconnected components designed for security, scalability, and intelligence.

```mermaid
graph TD
    subgraph Frontend (React / Next.js)
        A[User Interface] -->|Deposit/Withdraw| B(Wagmi / FCL Hooks)
    end

    subgraph Etherlink EVM Testnet
        C[Vault.sol]
        D[EtherlinkVrfYieldStrategy.sol]
        E[MockUSDC.sol]
        F[Etherlink Native VRF]

        B -->|deposit()| C
        C -->|depositToStrategy()| D
        D -->|requestRandomness()| F
    end

    subgraph "AI Agent Backend (Python / FastAPI)"
        G[API Endpoints]
        H[LangChain Agent Executor]
        I[OpenAI GPT-4o-mini]
        J[ML Risk Model]
        K[Web3.py]

        G --> H
        H -- "What should I do?" --> I
        H -- "Assess this strategy" --> J
        H -- "Execute transaction" --> K
    end

    K -->|trigger_lottery_draw()| C
    K -->|simulate_yield_harvest_and_deposit()| E
    E -->|approve() & depositYield()| D

    style Frontend fill:#cde4ff
    style "Etherlink EVM Testnet" fill:#d5f0d5
    style "AI Agent Backend (Python / FastAPI)" fill:#ffeacc
```

### Core Contracts (Deployed on Etherlink Testnet)
| Contract             | Address                                      | Description                                                          |
| :------------------- | :------------------------------------------- | :------------------------------------------------------------------- |
| **MockUSDC** | `0x4edbDC8Ed8Ca935513A2F06e231EE42FB6ed1d15` | An ERC20 token used for deposits and prize pools.                    |
| **Lottery Vault** | `0xBaE8f26eDa40Ab353A34ce38F8917318d226318F` | The main vault where users deposit and withdraw funds.               |
| **Etherlink VRF Strategy** | `0xf5DC9ca0518B45C3E372c3bC7959a4f3d1B18901` | The strategy that holds the prize pool and interacts with Etherlink's VRF. |

***

## 📊 Key Differentiators

We're not just another DeFi protocol. We're creating a new category of financial product.

| Solution                | Your Return                        | Management                  | Risk of Loss           | Gamified |
| :---------------------- | :--------------------------------- | :-------------------------- | :--------------------- | :------- |
| **Etherlink Prize Savings** | **Principal + Chance to Win Yield** | **Fully Passive (AI-Managed)** | **🔥 None** | **✅ Yes** |
| Traditional Savings     | Principal + ~1% APY                | Passive                     | None                   | ❌ No      |
| Lotteries / Gambling    | -100% (Usually)                    | Active                      | Very High              | ✅ Yes      |
| Yield Aggregators (Yearn) | Principal + Yield                  | Passive                     | Smart Contract Risk    | ❌ No      |

***

## 💰 Business Model & Go-To-Market

Our revenue model is simple, transparent, and fully aligned with our users' success.

* **Primary Revenue Stream: Performance Fee**
    * We will take a small percentage (e.g., 10%) of the **generated yield only**.
    * **Example:** If the prize pool for a week is $1,000, the winner receives $900 and the protocol receives $100 to fund operations and growth.
    * **The Guarantee:** If there is no yield, there are no fees. We only earn when our users win.

### Go-To-Market Strategy
* **Phase 1: Launch on Etherlink Testnet & Build Community (Current)**
    * Engage with the Etherlink community through social media, developer forums, and hackathons.
    * Gather user feedback to refine the product and user experience.
* **Phase 2: Mainnet Launch with Real Yield Strategies**
    * Integrate with audited, blue-chip protocols on Etherlink (e.g., Increment Finance) to generate real yield.
    * Launch a marketing campaign focused on the "no-loss" value proposition to attract initial liquidity.
* **Phase 3: Scale & Expand**
    * Introduce new features like premium prize tiers, team-based savings games, and NFT-based rewards.
    * Explore multi-chain yield optimization, using the AI agent to find the best risk-adjusted returns across the entire Web3 ecosystem.

***

## 🗺️ Future Development & Roadmap

This project provides a robust foundation. The next phase will focus on transitioning from a simulated environment to a live, fully autonomous, yield-bearing protocol.

* **Implement Real Yield Strategies on Etherlink:**
    * Integrate with established Etherlink protocols like **Increment Finance** or **Etherlinkswap** to generate real yield from user deposits.
    * Develop and deploy new Cadence-based yield strategies to leverage Etherlink's unique capabilities for gas efficiency and composability.
* **Enhance the ML Risk Model:**
    * Train the risk assessment model on historical data from actual Etherlink DeFi protocols.
    * Build a data pipeline to continuously fetch on-chain data to keep the model updated and relevant.
    * Allow the agent to dynamically retrain the model based on new information and market conditions.
* **Expand Agent's Autonomous Capabilities:**
    * Enable the agent to autonomously decide *when* and *how much* capital to allocate to different strategies based on risk/reward calculations.
    * Implement logic for the agent to automatically rebalance the portfolio if a strategy's risk profile changes.
    * Use **Account Linking** on Etherlink to allow the agent to securely manage vault operations with clear permissions and user-controlled recovery mechanisms, creating a truly secure autonomous system.
* **UX Enhancements with Cadence:**
    * Leverage Cadence to introduce features impossible on traditional EVM chains, such as **sponsored/batched transactions** for a gasless user experience and **walletless onboarding** for mainstream adoption.

***

## ❓ Addressing Key Questions (FAQ)

#### "Is this just another lottery?"
No. It's a savings protocol first. Traditional lotteries require you to spend and lose your money for a chance to win. With us, your deposit is never spent. You are essentially getting a free lottery ticket every week, just for saving your money. The prize is created from the *yield*, not the principal.

#### "If I don't win, do I lose anything?"
Absolutely not. This is the core of our "no-loss" guarantee. If you don't win, your initial deposit remains untouched and is available for you to withdraw at any time.

#### "Is my money safe?"
Security is our highest priority.
1.  **Non-Custodial:** You always maintain full ownership of your funds. We can never access your deposited principal.
2.  **No-Loss Guarantee:** The smart contracts are architected to ensure only generated yield is moved to the prize pool. Your deposit is isolated and safe.
3.  **Future-Proofing:** When real yield strategies are implemented, they will be restricted to a whitelist of heavily audited, battle-tested protocols, and our AI will continuously monitor for risks.

***

## 🔧 Quick Start & Installation

This project contains a full-stack application with smart contracts, an AI backend, and a React frontend.

### Prerequisites
* Node.js v18+
* Python 3.9+
* An EVM-compatible wallet (e.g., MetaMask) funded on the Etherlink Testnet.

### Installation & Setup
1.  **Clone the Repository:**
    ```bash
    git clone <your-repo-url>
    cd <repo-folder>
    ```

2.  **Set Up AI Backend:**
    ```bash
    cd <backend-folder>
    python3 -m venv venv
    source venv/bin/activate  # On Windows: venv\Scripts\activate
    pip install -r requirements.txt
    cp .env.example .env
    ```
    * Fill in your `AGENT_PRIVATE_KEY` and `OPENAI_API_KEY` in the `.env` file.

3.  **Set Up Frontend:**
    ```bash
    cd <frontend-folder>
    npm install
    ```

### Running the Application
1.  **Start the AI Agent Backend:**
    ```bash
    cd <backend-folder>
    uvicorn main:app --reload
    ```
    The agent is now running on `http://localhost:8000`.

2.  **Start the Frontend:**
    ```bash
    cd <frontend-folder>
    npm run dev
    ```
    Access the user interface at `http://localhost:3000`.

***

## 🤖 Agent Demo Guide: A Full Operational Cycle

You can interact with the live agent using these `curl` commands to simulate a full operational week.

1.  **Check System Health**
    * **What it does:** Confirms the agent is online, connected to the Etherlink blockchain, and can communicate with our smart contracts.
    * **Command:**
        ```bash
        curl http://localhost:8000/health
        ```

2.  **Generate the Prize Pool**
    * **What it does:** Simulates yield generation. The agent mints 150 USDC and deposits it into the strategy contract to create this week's prize.
    * **Command:**
        ```bash
        curl -X POST http://localhost:8000/generate-yield \
             -H "Content-Type: application/json" \
             -d '{"amount_usdc": 150.0}'
        ```

3.  **Check the Status**
    * **What it does:** Shows the prize pool is now funded and ready for the draw.
    * **Command:**
        ```bash
        curl http://localhost:8000/enhanced-status
        ```

4.  **Trigger the Lottery Draw**
    * **What it does:** Instructs the agent to trigger the lottery, calling the smart contract that uses Etherlink's native VRF to select a winner.
    * **Command:**
        ```bash
        curl -X POST http://localhost:8000/trigger-lottery
        ```

5.  **Confirm the Winner**
    * **What it does:** Confirms the draw is complete and shows the winner's address.
    * **Command:**
        ```bash
        curl http://localhost:8000/enhanced-status
        ```

6.  **Ask the AI for a Strategy**
    * **What it does:** Demonstrates the agent's intelligence. It analyzes the current state and uses GPT-4 to recommend a strategic course of action.
    * **Command:**
        ```bash
        curl -X POST http://localhost:8000/ai-strategy \
             -H "Content-Type: application/json" \
             -d '{"command": "What should I do next after successfully running the lottery?"}'
        ```

7.  **Run an Emergency Risk Check**
    * **What it does:** Showcases the agent's security focus by running an emergency risk assessment across all strategies.
    * **Command:**
        ```bash
        curl http://localhost:8000/emergency-status
        ```

***

## 🌐 The Vision: Onboarding the Next Billion Users to Web3

Our vision is to make saving and wealth creation accessible, fun, and rewarding for everyone. We believe **Etherlink Prize Savings** can become the default savings account for the next generation of internet users—a place where your money is not only safe but is also constantly working to give you a shot at a better financial future.

By abstracting away the complexities of DeFi with a powerful AI and a simple, engaging interface, we are building a "killer app" that solves a real-world problem for a global audience, right here on Etherlink.







 --- CONTRACT DEPLOYMENT SUMMARY --- 
------------------------------------
   Mock USDC Token:     0x4edbDC8Ed8Ca935513A2F06e231EE42FB6ed1d15
   Vault Factory:       0xa87fe90A07DE4E10398F2203A9F3Bd8b98Cf902D
   Lottery Vault:       0xBaE8f26eDa40Ab353A34ce38F8917318d226318F
   Etherlink VRF Strategy:   0xf5DC9ca0518B45C3E372c3bC7959a4f3d1B18901
------------------------------------

VRF strategy added and configured to Vault

🔮 VRF Integration Details:
   The Etherlink VRF Strategy uses the Cadence Arch contract at:
   0x0000000000000000000000010000000000000001
   This provides secure, on-chain randomness.


