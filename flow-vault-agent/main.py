from fastapi import FastAPI
from pydantic import BaseModel
from langchain_openai import ChatOpenAI
from langchain.agents import AgentExecutor, create_react_agent
from langchain_core.prompts import PromptTemplate
from tools import (
    get_protocol_status,
    deposit_new_funds_into_strategy,
    simulate_yield_harvest_and_deposit,
    trigger_lottery_draw
)
from config import OPENAI_API_KEY, agent_account

# --- Agent Setup ---

# 1. Define the tools the agent can use
tools = [
    get_protocol_status,
    deposit_new_funds_into_strategy,
    simulate_yield_harvest_and_deposit,
    trigger_lottery_draw
]

# 2. Create the prompt template
prompt_template = """
You are the "Vault Manager," a highly efficient and reliable AI agent responsible for operating a no-loss prize savings game on the Flow blockchain.

Your address is: {agent_address}.

Your primary goal is to manage the protocol's funds to ensure a weekly prize can be awarded to a lucky user. You operate with precision and follow a strict operational procedure.

You have access to the following tools:

{tools}

Use the following format for your thought process:

Question: the user's request or the task you need to perform
Thought: You should always think about what to do. First, always check the protocol status to understand the current state. Then, decide the next logical step based on the user's request and the protocol's state.
Action: the action to take, should be one of [{tool_names}]
Action Input: the input to the action
Observation: the result of the action
... (this Thought/Action/Action Input/Observation can repeat N times)
Thought: I now know the final answer.
Final Answer: the final answer to the original input question.

**Operational Procedure:**

1.  **Assessment:** Always start by using the `get_protocol_status` tool to understand the current state of the vault and the prize pool.
2.  **Capital Deployment:** If you see liquid USDC in the vault, your duty is to deploy it using `deposit_new_funds_into_strategy`.
3.  **Yield Simulation (for demo):** To prepare for a lottery draw, you must first fund the prize pool. Use the `simulate_yield_harvest_and_deposit` tool. A reasonable weekly prize might be between 50 and 500 USDC.
4.  **Lottery Execution:** Once you confirm there is a prize pool, and only then, you can execute the weekly draw using `trigger_lottery_draw`.

**Example Scenario: Running the weekly draw.**

Question: It's Friday, time to run the weekly prize draw.
Thought: I need to run the weekly prize draw. First, I must check the protocol's status.
Action: get_protocol_status
Action Input:
Observation: Protocol Status: {{'vault_liquid_usdc': '0.00 USDC', 'current_prize_pool': '0.00 USDC', 'last_lottery_winner': '0x...}}
Thought: The prize pool is currently zero. I cannot trigger a draw. I must first simulate the weekly yield harvest to fund the prize pool. I will simulate a harvest of 150 USDC.
Action: simulate_yield_harvest_and_deposit
Action Input: 150
Observation: Successfully simulated and deposited 150.0 USDC as the prize pool.
Thought: Now that the prize pool is funded, I can trigger the lottery draw.
Action: trigger_lottery_draw
Action Input:
Observation: Lottery draw successful! The new winner is 0xNewWinnerAddress...
Thought: I have successfully completed the weekly draw.
Final Answer: The weekly prize draw is complete. A prize of 150.0 USDC was awarded to the new winner: 0xNewWinnerAddress...

Begin!

Question: {input}
Thought: {agent_scratchpad}
"""

prompt = PromptTemplate.from_template(prompt_template)

# 3. Initialize the LLM and Agent
llm = ChatOpenAI(model="gpt-4o-mini", temperature=0, api_key=OPENAI_API_KEY)
agent = create_react_agent(llm, tools, prompt)
agent_executor = AgentExecutor(agent=agent, tools=tools, verbose=True, handle_parsing_errors=True)

# --- FastAPI Server ---
app = FastAPI(
    title="Flow Vault Manager Agent",
    description="An API for interacting with an autonomous agent that manages a prize savings protocol on Flow.",
)

class AgentRequest(BaseModel):
    command: str

@app.post("/invoke-agent")
async def invoke_agent(request: AgentRequest):
    """
    Receives a natural language command and lets the agent execute it.
    """
    try:
        response = await agent_executor.ainvoke({
            "input": request.command,
            "agent_address": agent_account.address
        })
        return {"success": True, "output": response["output"]}
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.get("/")
def read_root():
    return {"message": "Flow Vault Manager Agent is running."}

# To run the server, use the command: uvicorn main:app --reload
