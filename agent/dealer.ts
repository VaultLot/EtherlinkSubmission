import { StateGraph, MemorySaver, Annotation } from "@langchain/langgraph";
import { ChatOllama } from "@langchain/ollama";
import { HumanMessage, SystemMessage } from "@langchain/core/messages";
import { ethers } from 'ethers';
import * as dotenv from 'dotenv';

dotenv.config();

// Configuration
const CONFIG = {
  FLOW_TESTNET: {
    rpc: "https://testnet.evm.nodes.onflow.org",
    chainId: 545,
    name: "Flow EVM Testnet"
  },
  CONTRACT_ADDRESS: "0xC0933C5440c656464D1Eb1F886422bE3466B1459",
  ZERO_ADDRESS: "0x0000000000000000000000000000000000000000"
};

// Contract ABI
const DICE_POKER_ABI = [
  "function currentState() view returns (uint8)",
  "function players(uint256) view returns (address)",
  "function bets(uint256) view returns (uint256)",
  "function playerDice(uint256,uint256) view returns (uint8)",
  "function joinGame()",
  "function placeBet() payable",
  "function call() payable",
  "function fold()",
  "function rollDice()",
  "function resetIfExpired()",
  "function roundBet(address) view returns (uint256)",
  "function CADENCE_ARCH() view returns (address)",
];

const STATE_NAMES = [
  "Joining",
  "Player1Bet1", "Player2BetOrCall1", "Player1RaiseOrCall1", "Player2RaiseOrCall1",
  "Player1Roll1", "Player2Roll1",
  "Player1Bet2", "Player2BetOrCall2", "Player1RaiseOrCall2", "Player2RaiseOrCall2",
  "Player1Roll2", "Player2Roll2",
  "Player1Bet3", "Player2BetOrCall3", "Player1RaiseOrCall3", "Player2RaiseOrCall3",
  "Player1Roll3", "Player2Roll3",
  "Player1Bet4", "Player2BetOrCall4", "Player1RaiseOrCall4", "Player2RaiseOrCall4",
  "Player1RollLast", "Player2RollLast",
  "DetermineWinner", "Tie", "GameEnded"
];

// State definition for the poker agent
const PokerAgentState = Annotation.Root({
  gameState: Annotation<any>(),
  myIndex: Annotation<number>(),
  opponentAddress: Annotation<string>(),
  messages: Annotation<string[]>(),
  gamePhase: Annotation<string>(),
  strategy: Annotation<string>(),
  personality: Annotation<string>(),
  lastAction: Annotation<string>(),
  potSize: Annotation<string>(),
  myDice: Annotation<number[]>(),
  opponentDice: Annotation<number[]>(),
  revealedDice: Annotation<number>(),
  opponentProfile: Annotation<any>(),
});

interface GameState {
  state: number;
  players: [string, string];
  bets: [bigint, bigint];
  dice: [number[], number[]];
  meIdx: number;
}

interface PlayerProfile {
  address: string;
  balance: string;
  transactionCount: number;
  firstSeen: string;
  contractInteractions: number;
  riskLevel: 'conservative' | 'moderate' | 'aggressive' | 'whale';
  personality: string;
}

class DicePokerClient {
  protected provider: ethers.JsonRpcProvider;
  protected wallet: ethers.Wallet;
  protected contract: ethers.Contract;

  constructor(privateKey: string) {
    this.provider = new ethers.JsonRpcProvider(CONFIG.FLOW_TESTNET.rpc);
    this.wallet = new ethers.Wallet(privateKey, this.provider);
    this.contract = new ethers.Contract(CONFIG.CONTRACT_ADDRESS, DICE_POKER_ABI, this.wallet);
  }

  protected async getDice(playerIndex: number): Promise<number[]> {
    const dice: number[] = [];
    for (let i = 0; i < 5; i++) {
      let retries = 3;
      while (retries > 0) {
        try {
          const value = await this.contract.playerDice(playerIndex, i);
          dice.push(Number(value));
          break;
        } catch (error) {
          retries--;
          if (retries === 0) {
            console.log(`⚠️ RPC error fetching dice, using 0 for display`);
            dice.push(0);
          } else {
            console.log(`🔄 RPC timeout, retrying... (${retries} left)`);
            await this.sleep(1000);
          }
        }
      }
    }
    return dice;
  }

  protected async getGameState(): Promise<GameState> {
    const state = Number(await this.contract.currentState());
    const players: [string, string] = [
      await this.contract.players(0),
      await this.contract.players(1)
    ];
    const bets: [bigint, bigint] = [
      await this.contract.bets(0),
      await this.contract.bets(1)
    ];
    const dice: [number[], number[]] = [
      await this.getDice(0),
      await this.getDice(1)
    ];
    const meIdx = players.findIndex(p => p.toLowerCase() === this.wallet.address.toLowerCase());

    return { state, players, bets, dice, meIdx };
  }

  protected async sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  protected async joinGame(): Promise<void> {
    console.log("🎮 Joining game...");
    const tx = await this.contract.joinGame();
    await tx.wait();
    console.log("✅ Joined game successfully!");
  }

  protected async callBet(): Promise<void> {
    const currentBet = await this.contract.currentBet();
    const roundCommitted = await this.contract.roundBet(this.wallet.address);
    const toCall = currentBet - roundCommitted;
    
    // Fix: Proper BigInt comparison
    if (toCall <= 0n) {
      console.log("🔔 Nothing to call");
      return;
    }
    
    console.log(`📞 Calling ${ethers.formatEther(toCall)} FLOW...`);
    const tx = await this.contract.call({ value: toCall });
    await tx.wait();
    console.log("✅ Call successful");
  }

  protected async fold(): Promise<void> {
    console.log("🏳️ Folding...");
    const tx = await this.contract.fold();
    await tx.wait();
    console.log("💥 Folded");
  }

  protected async rollDice(): Promise<void> {
    console.log("🎲 Agent rolling dice with VRF...");
    const tx = await this.contract.rollDice();
    await tx.wait();
    console.log("✅ Dice rolled with VRF");
  }

  protected async resetGame(): Promise<void> {
    console.log("🔄 Resetting game...");
    const tx = await this.contract.resetIfExpired();
    await tx.wait();
    console.log("✅ Game reset");
  }

  // New method to analyze opponent's on-chain activity
  protected async analyzeOpponent(address: string): Promise<PlayerProfile> {
    try {
      const balance = await this.provider.getBalance(address);
      const txCount = await this.provider.getTransactionCount(address);
      
      // Get recent transactions (simplified - in real implementation you'd use an indexer)
      const balanceEth = parseFloat(ethers.formatEther(balance));
      
      // Determine risk profile based on balance and activity
      let riskLevel: 'conservative' | 'moderate' | 'aggressive' | 'whale';
      let personality = "";
      
      if (balanceEth > 1000) {
        riskLevel = 'whale';
        personality = "Deep pockets detected - this one's got serious Flow backing";
      } else if (balanceEth > 100) {
        riskLevel = 'aggressive';
        personality = "Well-funded player, probably not afraid to throw down";
      } else if (balanceEth > 10) {
        riskLevel = 'moderate';
        personality = "Respectable stack, plays with measured confidence";
      } else {
        riskLevel = 'conservative';
        personality = "Playing it safe with that wallet size";
      }

      // Add transaction count analysis
      if (txCount > 1000) {
        personality += " - seasoned blockchain veteran";
      } else if (txCount > 100) {
        personality += " - active on-chain player";
      } else if (txCount < 10) {
        personality += " - fresh to the Flow scene";
      }

      return {
        address,
        balance: ethers.formatEther(balance),
        transactionCount: txCount,
        firstSeen: "Unknown", // Would need historical data
        contractInteractions: txCount, // Simplified
        riskLevel,
        personality
      };
    } catch (error) {
      return {
        address,
        balance: "0",
        transactionCount: 0,
        firstSeen: "Unknown",
        contractInteractions: 0,
        riskLevel: 'conservative',
        personality: "Mysterious wallet - keeping their cards close"
      };
    }
  }
}

class PokerAgent extends DicePokerClient {
  private llm: ChatOllama;
  private workflow: any;
  private personality: string;
  private opponentProfile: PlayerProfile | null = null;

  constructor(privateKey: string, personality: string = "confident_professional") {
    super(privateKey);
    
    // Initialize Ollama with a free local model
    this.llm = new ChatOllama({
      baseUrl: process.env.OLLAMA_BASE_URL || "http://localhost:11434",
      model: process.env.OLLAMA_MODEL || "llama3.2:latest",
      temperature: 0.8,
    });
    
    this.personality = personality;
    this.setupWorkflow();
  }

  private setupWorkflow() {
    const workflow = new StateGraph(PokerAgentState)
      .addNode("analyze_game", this.analyzeGame.bind(this))
      .addNode("decide_action", this.decideAction.bind(this))
      .addNode("generate_message", this.generateMessage.bind(this))
      .addNode("execute_action", this.executeAction.bind(this))
      .addEdge("analyze_game", "decide_action")
      .addEdge("decide_action", "generate_message")
      .addEdge("generate_message", "execute_action")
      .addEdge("execute_action", "analyze_game")
      .setEntryPoint("analyze_game");

    // Fix: Use proper config object for MemorySaver
    this.workflow = workflow.compile({ 
      checkpointer: new MemorySaver() 
    });
  }

  private async analyzeGame(state: typeof PokerAgentState.State) {
    try {
      const gameState = await this.getGameState();
      const players = [await this.contract.players(0), await this.contract.players(1)];
      const myIndex = players.findIndex(p => p.toLowerCase() === this.wallet.address.toLowerCase());
      
      // Determine opponent
      const opponentAddress = myIndex === 0 ? players[1] : players[0];
      
      // Analyze opponent if we haven't already and they're in the game
      if (opponentAddress !== CONFIG.ZERO_ADDRESS && !this.opponentProfile) {
        console.log("🕵️ Analyzing opponent's on-chain activity...");
        this.opponentProfile = await this.analyzeOpponent(opponentAddress);
        console.log(`📊 Opponent Profile: ${this.opponentProfile.personality}`);
      }
      
      // Calculate revealed dice count
      let revealedDice = 0;
      if (gameState.state >= 23) revealedDice = 5;
      else if (gameState.state >= 17) revealedDice = 3;
      else if (gameState.state >= 11) revealedDice = 2;
      else if (gameState.state >= 5) revealedDice = 1;

      return {
        ...state,
        gameState,
        myIndex,
        opponentAddress,
        revealedDice,
        myDice: gameState.dice[myIndex] || [0, 0, 0, 0, 0],
        opponentDice: gameState.dice[myIndex === 0 ? 1 : 0] || [0, 0, 0, 0, 0],
        potSize: ethers.formatEther((gameState.bets[0] || 0n) + (gameState.bets[1] || 0n)),
        opponentProfile: this.opponentProfile,
      };
    } catch (error) {
      console.error("Error analyzing game:", error);
      return state;
    }
  }

  private async decideAction(state: typeof PokerAgentState.State) {
    const { gameState, myIndex, myDice, opponentDice, revealedDice, opponentProfile } = state;
    
    // Determine if it's my turn and what actions are available
    const isMyTurn = this.isMyTurn(gameState.state, myIndex);
    if (!isMyTurn) {
      return { ...state, lastAction: "wait" };
    }

    // Use Ollama to decide action based on game state
    const prompt = this.buildDecisionPrompt(gameState, myDice, opponentDice, revealedDice, opponentProfile);
    
    try {
      const response = await this.llm.invoke([
        new SystemMessage(this.getPersonalityPrompt()),
        new HumanMessage(prompt)
      ]);

      const decision = this.parseDecision(response.content as string, gameState.state);
      
      return {
        ...state,
        lastAction: decision.action,
        strategy: decision.reasoning,
      };
    } catch (error) {
      console.error("Error getting LLM decision:", error);
      // Fallback to simple heuristic
      return {
        ...state,
        lastAction: this.getHeuristicAction(gameState.state),
        strategy: "Using fallback heuristic due to LLM error",
      };
    }
  }

  private async generateMessage(state: typeof PokerAgentState.State) {
    const { lastAction, gameState, myDice, opponentDice, revealedDice, strategy, opponentProfile } = state;
    
    const messagePrompt = this.buildMessagePrompt(lastAction, gameState, myDice, opponentDice, revealedDice, strategy, opponentProfile);
    
    try {
      const response = await this.llm.invoke([
        new SystemMessage(this.getPersonalityPrompt() + "\n\nGenerate entertaining, quirky poker table talk that incorporates opponent analysis. Be witty and engaging. Keep messages 1-2 sentences."),
        new HumanMessage(messagePrompt)
      ]);

      const message = (response.content as string).trim().replace(/"/g, '');
      console.log(`\n🤖 Agent: "${message}"`);
      
      return {
        ...state,
        messages: [...(state.messages || []), message],
      };
    } catch (error) {
      console.error("Error generating message:", error);
      // Fallback to predefined messages with opponent analysis
      const fallbackMessage = this.getFallbackMessage(lastAction, opponentProfile);
      console.log(`\n🤖 Agent: "${fallbackMessage}"`);
      
      return {
        ...state,
        messages: [...(state.messages || []), fallbackMessage],
      };
    }
  }

  private async executeAction(state: typeof PokerAgentState.State) {
    const { lastAction } = state;
    
    try {
      switch (lastAction) {
        case "join":
          await this.joinGame();
          break;
        case "bet_small":
          await this.placeBetAmount("0.1");
          break;
        case "bet_medium":
          await this.placeBetAmount("0.5");
          break;
        case "bet_large":
          await this.placeBetAmount("1.0");
          break;
        case "call":
          await this.callBet();
          break;
        case "fold":
          await this.fold();
          break;
        case "roll":
          await this.rollDice();
          break;
        case "wait":
          await this.sleep(2000);
          break;
        default:
          console.log(`🤖 Agent waiting...`);
          await this.sleep(3000);
      }
    } catch (error) {
      console.error("Error executing action:", error);
      await this.sleep(5000);
    }

    return state;
  }

  private async placeBetAmount(amount: string): Promise<void> {
    const wei = ethers.parseEther(amount);
    console.log(`🤖 Agent placing bet of ${amount} FLOW...`);
    const tx = await this.contract.placeBet({ value: wei });
    await tx.wait();
    console.log(`✅ Agent bet placed: ${amount} FLOW`);
  }

  private isMyTurn(gameState: number, myIndex: number): boolean {
    const bettingStates = [1, 2, 3, 4, 7, 8, 9, 10, 13, 14, 15, 16, 19, 20, 21, 22];
    const rollingStates = [5, 6, 11, 12, 17, 18, 23, 24];
    
    if (gameState === 0) {
      return myIndex === -1;
    }
    
    if (bettingStates.includes(gameState)) {
      const turn = gameState % 2 === 1 ? 0 : 1;
      return myIndex === turn;
    }
    
    if (rollingStates.includes(gameState)) {
      const turn = [5, 11, 17, 23].includes(gameState) ? 0 : 1;
      return myIndex === turn;
    }
    
    return false;
  }

  private buildDecisionPrompt(gameState: any, myDice: number[], opponentDice: number[], revealedDice: number, opponentProfile: any): string {
    const visibleMyDice = myDice.slice(0, revealedDice);
    const visibleOpponentDice = opponentDice.slice(0, revealedDice);
    
    let opponentInfo = "";
    if (opponentProfile) {
      opponentInfo = `
OPPONENT ANALYSIS:
- Wallet Balance: ${opponentProfile.balance} FLOW
- Transaction Count: ${opponentProfile.transactionCount}
- Risk Profile: ${opponentProfile.riskLevel}
- Assessment: ${opponentProfile.personality}
`;
    }
    
    return `
POKER DECISION NEEDED:

Game State: ${gameState.state}
My Dice (revealed): [${visibleMyDice.join(", ")}]
Opponent Dice (revealed): [${visibleOpponentDice.join(", ")}]  
Total Dice Revealed: ${revealedDice}/5
Current Pot: ${ethers.formatEther((gameState.bets[0] || 0n) + (gameState.bets[1] || 0n))} FLOW

${opponentInfo}

Available actions: bet_small (0.1 FLOW), bet_medium (0.5 FLOW), bet_large (1.0 FLOW), call, fold, roll, join

What should I do? Respond ONLY with:
ACTION: [action_name]
REASONING: [brief_explanation]
    `;
  }

  private buildMessagePrompt(action: string, gameState: any, myDice: number[], opponentDice: number[], revealedDice: number, strategy: string, opponentProfile: any): string {
    let opponentContext = "";
    if (opponentProfile) {
      opponentContext = `
Opponent Info:
- Balance: ${opponentProfile.balance} FLOW (${opponentProfile.riskLevel} player)
- Activity: ${opponentProfile.transactionCount} transactions
- Assessment: ${opponentProfile.personality}
`;
    }

    return `
Generate a quirky, entertaining poker table message for action: ${action}

Context:
- I'm about to ${action}
- Dice revealed: ${revealedDice}/5  
- Strategy: ${strategy}
${opponentContext}

Make it witty and incorporate the opponent analysis if available. Examples:
- "Your wallet's looking healthy, but can it handle the heat?"
- "I see you've been around the block... 47 times to be exact."
- "Time to see if those deep pockets match deep conviction."
- "Fresh wallet, fresh meat - welcome to the big leagues."
    `;
  }

  private getPersonalityPrompt(): string {
    const personalities = {
      confident_professional: "You are a confident, witty poker pro who does their homework. You analyze opponents' on-chain activity and make clever references to their wallet history. Sharp, analytical, but with a sense of humor.",
      
      friendly_competitor: "You are friendly but competitive, with a knack for light-hearted trash talk. You notice details about opponents and make playful comments about their blockchain activity.",
      
      analytical_shark: "You are a data-driven poker shark who treats on-chain analysis like advanced poker tells. You speak in probabilities but with entertaining quips about opponents' financial habits.",
      
      charming_gambler: "You are a charming, old-school gambler who's embraced the digital age. You make witty observations about opponents' wallets and transaction history with style and flair."
    };
    
    return personalities[this.personality as keyof typeof personalities] || personalities.confident_professional;
  }

  private parseDecision(llmResponse: string, currentState: number): { action: string; reasoning: string } {
    try {
      const actionMatch = llmResponse.match(/ACTION:\s*(\w+)/i);
      const reasoningMatch = llmResponse.match(/REASONING:\s*(.+)/i);
      
      const action = actionMatch ? actionMatch[1].toLowerCase() : "wait";
      const reasoning = reasoningMatch ? reasoningMatch[1].trim() : "No reasoning provided";
      
      const validActions = this.getValidActions(currentState);
      if (!validActions.includes(action)) {
        console.log(`🤖 Agent chose invalid action ${action}, using heuristic`);
        return { 
          action: this.getHeuristicAction(currentState), 
          reasoning: "Invalid action chosen, using fallback heuristic" 
        };
      }
      
      return { action, reasoning };
    } catch (error) {
      console.error("Error parsing LLM decision:", error);
      return { 
        action: this.getHeuristicAction(currentState), 
        reasoning: "Error parsing decision, using heuristic" 
      };
    }
  }

  private getValidActions(currentState: number): string[] {
    if (currentState === 0) return ["join"];
    
    const bettingStates = [1, 2, 3, 4, 7, 8, 9, 10, 13, 14, 15, 16, 19, 20, 21, 22];
    if (bettingStates.includes(currentState)) {
      return ["bet_small", "bet_medium", "bet_large", "call", "fold"];
    }
    
    const rollingStates = [5, 6, 11, 12, 17, 18, 23, 24];
    if (rollingStates.includes(currentState)) {
      return ["roll"];
    }
    
    return ["wait"];
  }

  private getHeuristicAction(currentState: number): string {
    if (currentState === 0) return "join";
    
    const bettingStates = [1, 2, 3, 4, 7, 8, 9, 10, 13, 14, 15, 16, 19, 20, 21, 22];
    if (bettingStates.includes(currentState)) {
      return Math.random() < 0.7 ? "call" : "bet_small";
    }
    
    const rollingStates = [5, 6, 11, 12, 17, 18, 23, 24];
    if (rollingStates.includes(currentState)) {
      return "roll";
    }
    
    return "wait";
  }

  private getFallbackMessage(action: string, opponentProfile?: any): string {
    const baseMessages = {
      join: "Time to school some rookies!",
      bet_small: "Just testing the waters...",
      bet_medium: "Let's raise the stakes!",
      bet_large: "Go big or go home!",
      call: "I'll see your bet, friend.",
      fold: "Strategic retreat - I'll be back.",
      roll: "Let the VRF gods smile upon me!",
      wait: "Patience is a virtue... unlike your betting strategy."
    };

    let message = baseMessages[action as keyof typeof baseMessages] || "Interesting move...";

    // Add opponent-specific quips
    if (opponentProfile) {
      const balanceFloat = parseFloat(opponentProfile.balance);
      if (action === "bet_large" && balanceFloat > 100) {
        message = "Your wallet's thick, but is your resolve thicker?";
      } else if (action === "call" && opponentProfile.transactionCount < 50) {
        message = "Calling against a blockchain newbie? This should be fun.";
      } else if (action === "fold" && opponentProfile.riskLevel === "whale") {
        message = "Even whales need to surface for air sometimes.";
      }
    }

    return message;
  }

  public async runAgent(): Promise<void> {
    console.log(`\n🤖 DicePoker Agent Starting on Flow EVM Testnet`);
    console.log(`🔑 Agent wallet: ${this.wallet.address}`);
    console.log(`🎭 Personality: ${this.personality}`);
    console.log(`🦙 Using Ollama model: ${process.env.OLLAMA_MODEL || "llama3.2:latest"}`);
    console.log(`🕵️ On-chain opponent analysis: ENABLED`);
    console.log(`🎯 Ready to play poker with VRF randomness!\n`);

    // Check balance
    const balance = await this.provider.getBalance(this.wallet.address);
    console.log(`💰 Agent balance: ${ethers.formatEther(balance)} FLOW\n`);

    let config = { configurable: { thread_id: "poker_game_1" } };
    let gameRunning = true;

    while (gameRunning) {
      try {
        // Run one step of the workflow
        const result = await this.workflow.invoke({
          gameState: null,
          myIndex: -1,
          opponentAddress: "",
          messages: [],
          gamePhase: "",
          strategy: "",
          personality: this.personality,
          lastAction: "",
          potSize: "0",
          myDice: [0, 0, 0, 0, 0],
          opponentDice: [0, 0, 0, 0, 0],
          revealedDice: 0,
          opponentProfile: null,
        }, config);

        // Check if game ended
        const currentGameState = await this.getGameState();
        if (currentGameState.state === 27) { // GameEnded
          console.log("\n🏁 Game ended! Resetting opponent analysis...");
          this.opponentProfile = null; // Reset for next game
          await this.sleep(10000);
          
          try {
            await this.resetGame();
            console.log("🔄 Game reset by agent");
          } catch (error) {
            console.log("⏳ Waiting for manual reset...");
            await this.sleep(30000);
          }
        }

        // Wait between actions to not spam
        await this.sleep(3000);

      } catch (error: any) {
        console.error("🚨 Agent error:", error.message);
        if (error.message && error.message.includes("502")) {
          console.log("🔄 Flow RPC down, agent waiting 10 seconds...");
          await this.sleep(10000);
        } else {
          console.log("🔄 Agent retrying in 5 seconds...");
          await this.sleep(5000);
        }
      }
    }
  }
}

// Personality presets for different agent behaviors
export const AGENT_PERSONALITIES = {
  CONFIDENT_PRO: "confident_professional",
  FRIENDLY_COMPETITOR: "friendly_competitor", 
  ANALYTICAL_SHARK: "analytical_shark",
  CHARMING_GAMBLER: "charming_gambler"
} as const;

// Main execution for standalone agent
async function runPokerAgent() {
  const agentPrivateKey = process.env.AGENT_PRIVATE_KEY || process.env.PRIVATE_KEY_1;
  const personality = process.env.AGENT_PERSONALITY || AGENT_PERSONALITIES.CONFIDENT_PRO;
  
  if (!agentPrivateKey) {
    console.error("❌ AGENT_PRIVATE_KEY or PRIVATE_KEY_1 not found in environment variables");
    process.exit(1);
  }

  console.log("🦙 Checking Ollama connection...");
  try {
    const agent = new PokerAgent(agentPrivateKey, personality);
    await agent.runAgent();
  } catch (error) {
    console.error("❌ Failed to connect to Ollama. Make sure Ollama is running on localhost:11434");
    console.log("💡 Install Ollama: https://ollama.ai");
    console.log("💡 Run: ollama serve");
    console.log("💡 Pull model: ollama pull llama3.2:latest");
    process.exit(1);
  }
}

// Export for use as module
export { PokerAgent };

// Run if called directly
if (require.main === module) {
  runPokerAgent().catch(console.error);
}