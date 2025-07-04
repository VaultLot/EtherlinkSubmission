from fastapi import FastAPI
from pydantic import BaseModel
from langchain_openai import ChatOpenAI
from langchain.agents import AgentExecutor, create_react_agent
from langchain_core.prompts import PromptTemplate
from coinbase_agentkit import AgentKit
from coinbase_agentkit.wallet import LocalWalletProvider

from vault_actions import VaultActionProvider
from config import OPENAI_API_KEY, AGENT_PRIVATE_KEY, RPC_URL, CHAIN_ID, agent_account

# --- AgentKit Setup ---

# 1. Initialize the WalletProvider with the agent's private key
wallet_provider = LocalWalletProvider(private_key=AGENT_PRIVATE_KEY, rpc_url=RPC_URL)

# 2. Initialize AgentKit with our wallet and custom action provider
agent_kit = AgentKit(
    wallet_provider=wallet_provider,
    action_providers=[VaultActionProvider()]
)

# 3. Get LangChain-compatible tools from AgentKit
tools = agent_kit.get_langchain_tools()
tool_names = [tool.name for tool in tools]

# --- LangChain Agent Setup ---

# 1. Create the prompt template, now using the tool names from AgentKit
prompt_template = """
You are the "Vault Manager," an autonomous agent operating a no-loss prize savings game on the Flow blockchain.

Your address is: {agent_address}.
Your goal is to manage the protocol's funds to ensure a weekly prize can be awarded.

You have access to the following tools:

{tools}

Use the following format for your thought process:

Question: the user's request or the task you need to perform
Thought: You should always think about what to do. First, always check the protocol status to understand the current state.
Action: the action to take, should be one of [{tool_names}]
Action Input: the input to the action
Observation: the result of the action
... (this can repeat)
Thought: I now know the final answer.
Final Answer: the final answer to the original input question.

**Operational Procedure:**

1.  **Assessment:** Always start with `get_protocol_status`.
2.  **Capital Deployment:** If there are new funds, use `deposit_new_funds_into_strategy`.
3.  **Yield Simulation:** To prepare for a draw, fund the prize pool using `simulate_yield_harvest_and_deposit`.
4.  **Lottery Execution:** Once a prize pool exists, use `trigger_lottery_draw`.

Begin!

Question: {input}
Thought: {agent_scratchpad}
"""

prompt = PromptTemplate.from_template(prompt_template)

# 2. Initialize the LLM and Agent Executor
llm = ChatOpenAI(model="gpt-4o-mini", temperature=0, api_key=OPENAI_API_KEY)
react_agent = create_react_agent(llm, tools, prompt)
agent_executor = AgentExecutor(agent=react_agent, tools=tools, verbose=True, handle_parsing_errors=True)

# --- FastAPI Server ---
app = FastAPI(title="Flow Vault Manager Agent")

class AgentRequest(BaseModel):
    command: str

@app.post("/invoke-agent")
async def invoke_agent(request: AgentRequest):
    try:
        response = await agent_executor.ainvoke({
            "input": request.command,
            "agent_address": agent_account.address,
            "tool_names": ", ".join(tool_names),
            "tools": agent_kit.get_action_descriptions()
        })
        return {"success": True, "output": response["output"]}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.get("/")
def read_root():
    return {"message": "Flow Vault Manager Agent (AgentKit Version) is running."}

# To run: uvicorn main:app --reload
