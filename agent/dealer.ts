import Anthropic from '@anthropic-ai/sdk';
import { createWalletClient, createPublicClient, http, parseEther, formatEther } from 'viem';
import { ethers } from 'ethers';
import * as dotenv from 'dotenv';

dotenv.config();

// Flow Testnet Configuration
const FLOW_TESTNET = {
  id: 545,
  name: 'Flow Testnet',
  nativeCurrency: {
    decimals: 18,
    name: 'Flow',
    symbol: 'FLOW',
  },
  rpcUrls: {
    default: {
      http: ['https://testnet.evm.nodes.onflow.org'],
    },
  },
  blockExplorers: {
    default: { name: 'FlowScan', url: 'https://evm-testnet.flowscan.io' },
  },
  testnet: true,
} as const;

const CONFIG = {
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
] as const;

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

interface PlayerProfile {
  address: string;
  balance: string;
  transactionCount: number;
  riskLevel: 'conservative' | 'moderate' | 'aggressive' | 'whale';
  personality: string;
}

interface GameState {
  state: number;
  stateName: string;
  players: [string, string];
  bets: [string, string];
  dice: [number[], number[]];
  myIndex: number;
  isMyTurn: boolean;
  pot: string;
  revealedDice: number;
}

class ClaudePokerAgent {
  private anthropic: Anthropic;
  private walletClient: any;
  private publicClient: any;
  private contract: any;
  private personality: string;
  private opponentProfile: PlayerProfile | null = null;

  constructor(privateKey: string, personality: string = "confident_professional") {
    this.personality = personality;
    this.setupClients(privateKey);
    this.setupClaude();
  }

  private setupClients(privateKey: string) {
    // Setup Viem clients for Flow testnet
    this.walletClient = createWalletClient({
      chain: FLOW_TESTNET,
      transport: http('https://testnet.evm.nodes.onflow.org'),
      account: privateKey as `0x${string}`,
    });

    this.publicClient = createPublicClient({
      chain: FLOW_TESTNET,
      transport: http('https://testnet.evm.nodes.onflow.org'),
    });

    // Setup ethers contract for easier interaction
    const provider = new ethers.JsonRpcProvider('https://testnet.evm.nodes.onflow.org');
    const wallet = new ethers.Wallet(privateKey, provider);
    this.contract = new ethers.Contract(CONFIG.CONTRACT_ADDRESS, DICE_POKER_ABI, wallet);
  }

  private setupClaude() {
    this.anthropic = new Anthropic({
      apiKey: process.env.ANTHROPIC_API_KEY!,
    });
  }

  private async askClaude(prompt: string): Promise<string> {
    try {
      const response = await this.anthropic.messages.create({
        model: 'claude-3-5-haiku-20241022',
        max_tokens: 300,
        temperature: 0.8,
        system: this.getSystemPrompt(),
        messages: [
          {
            role: 'user',
            content: prompt
          }
        ]
      });

      const content = response.content[0];
      if (content.type === 'text') {
        return content.text;
      }
      return "I'm thinking...";
    } catch (error) {
      console.error("Claude API error:", error);
      return this.getFallbackResponse();
    }
  }

  private getSystemPrompt(): string {
    const personalities = {
      confident_professional: `You are a confident, witty poker professional playing DicePoker on Flow blockchain. 
        You analyze opponents' on-chain activity and make clever references to their wallet history. 
        You're sharp, analytical, but with a great sense of humor. Always stay in character.`,
      
      friendly_competitor: `You are a friendly but competitive poker player with a knack for light-hearted trash talk. 
        You notice details about opponents and make playful comments about their blockchain activity. 
        Keep it fun but competitive.`,
      
      analytical_shark: `You are a data-driven poker shark who treats on-chain analysis like advanced poker tells. 
        You speak in probabilities but with entertaining quips about opponents' financial habits. 
        Make everything about the numbers and patterns.`,
      
      charming_gambler: `You are a charming, old-school gambler who's embraced the digital age. 
        You make witty observations about opponents' wallets and transaction history with style and flair. 
        Think James Bond meets crypto trader.`
    };

    return personalities[this.personality as keyof typeof personalities] || personalities.confident_professional + `

You are playing DicePoker on Flow blockchain testnet:
- 5 dice per player
- 4 betting rounds 
- VRF randomness for dice rolls
- Highest sum wins

When making decisions, respond with:
ACTION: [join/bet_small/bet_medium/bet_large/call/fold/roll/wait]
MESSAGE: [your witty table talk incorporating opponent analysis]

Keep messages entertaining, 1-2 sentences max. Reference opponent's wallet stats when available.`;
  }

  private async getGameState(): Promise<GameState> {
    const state = Number(await this.contract.currentState());
    const players = [
      await this.contract.players(0),
      await this.contract.players(1)
    ] as [string, string];
    
    const bets = [
      await this.contract.bets(0),
      await this.contract.bets(1)
    ];
    
    const dice = [
      await this.getDice(0),
      await this.getDice(1)
    ] as [number[], number[]];
    
    const myIndex = players.findIndex(
      p => p.toLowerCase() === this.walletClient.account.address.toLowerCase()
    );

    const revealedDice = this.getRevealedDiceCount(state);

    return {
      state,
      stateName: STATE_NAMES[state],
      players,
      bets: [ethers.formatEther(bets[0] || 0n), ethers.formatEther(bets[1] || 0n)] as [string, string],
      dice,
      myIndex,
      isMyTurn: this.isMyTurn(state, myIndex),
      pot: ethers.formatEther((bets[0] || 0n) + (bets[1] || 0n)),
      revealedDice
    };
  }

  private async getDice(playerIndex: number): Promise<number[]> {
    const dice: number[] = [];
    for (let i = 0; i < 5; i++) {
      try {
        const value = await this.contract.playerDice(playerIndex, i);
        dice.push(Number(value));
      } catch (error) {
        dice.push(0);
      }
    }
    return dice;
  }

  private async analyzeOpponent(address: string): Promise<PlayerProfile> {
    try {
      const balance = await this.publicClient.getBalance({ address });
      const txCount = await this.publicClient.getTransactionCount({ address });
      
      const balanceFloat = parseFloat(ethers.formatEther(balance));
      
      let riskLevel: 'conservative' | 'moderate' | 'aggressive' | 'whale';
      let personality = "";
      
      if (balanceFloat > 1000) {
        riskLevel = 'whale';
        personality = "🐋 Whale alert! This player's got serious FLOW backing";
      } else if (balanceFloat > 100) {
        riskLevel = 'aggressive';
        personality = "💰 Well-funded player, probably not afraid to throw down";
      } else if (balanceFloat > 10) {
        riskLevel = 'moderate';
        personality = "📊 Respectable stack, plays with measured confidence";
      } else {
        riskLevel = 'conservative';
        personality = "🤏 Playing it safe with that wallet size";
      }

      if (txCount > 1000) {
        personality += " - seasoned blockchain veteran 🏆";
      } else if (txCount > 100) {
        personality += " - active on-chain player 🎮";
      } else if (txCount < 10) {
        personality += " - fresh to the Flow scene 🌱";
      }

      return {
        address,
        balance: ethers.formatEther(balance),
        transactionCount: txCount,
        riskLevel,
        personality
      };
    } catch (error) {
      return {
        address,
        balance: "0",
        transactionCount: 0,
        riskLevel: 'conservative',
        personality: "Mysterious wallet - keeping their cards close"
      };
    }
  }

  private buildGamePrompt(gameState: GameState): string {
    let opponentInfo = "";
    if (this.opponentProfile) {
      opponentInfo = `
OPPONENT ANALYSIS:
- Balance: ${this.opponentProfile.balance} FLOW
- Transactions: ${this.opponentProfile.transactionCount}
- Risk Level: ${this.opponentProfile.riskLevel}
- Profile: ${this.opponentProfile.personality}
`;
    }

    const myDice = gameState.dice[gameState.myIndex] || [0, 0, 0, 0, 0];
    const opponentDice = gameState.dice[gameState.myIndex === 0 ? 1 : 0] || [0, 0, 0, 0, 0];

    return `
CURRENT POKER SITUATION:

Game State: ${gameState.stateName}
Pot Size: ${gameState.pot} FLOW
My Dice (revealed): [${myDice.slice(0, gameState.revealedDice).join(", ")}]
Opponent Dice (revealed): [${opponentDice.slice(0, gameState.revealedDice).join(", ")}]
Dice Revealed: ${gameState.revealedDice}/5
It's your turn: ${gameState.isMyTurn}
${opponentInfo}

Decide your action and generate witty table talk that incorporates opponent analysis!
Be entertaining and strategic. Reference their wallet stats in your banter when available.

Available actions:
- join: Join the game
- bet_small: Bet 0.1 FLOW  
- bet_medium: Bet 0.5 FLOW
- bet_large: Bet 1.0 FLOW
- call: Match opponent's bet
- fold: Give up this round
- roll: Roll dice when it's reveal time
- wait: Do nothing (not your turn)
`;
  }

  private parseClaudeResponse(response: string): { action: string; message: string } {
    const actionMatch = response.match(/ACTION:\s*(\w+)/i);
    const messageMatch = response.match(/MESSAGE:\s*(.+?)(?=\n|$)/is);
    
    const action = actionMatch ? actionMatch[1].toLowerCase() : "wait";
    const message = messageMatch ? messageMatch[1].trim() : response.trim();
    
    return { action, message };
  }

  private async executeAction(action: string): Promise<string> {
    try {
      switch (action) {
        case "join":
          console.log("🤖 Agent joining game...");
          const joinTx = await this.contract.joinGame();
          await joinTx.wait();
          return "✅ Joined the game!";

        case "bet_small":
          return await this.placeBet("0.1");
        case "bet_medium":
          return await this.placeBet("0.5");
        case "bet_large":
          return await this.placeBet("1.0");

        case "call":
          const currentBet = await this.contract.currentBet();
          const roundCommitted = await this.contract.roundBet(this.walletClient.account.address);
          const toCall = currentBet - roundCommitted;
          
          if (toCall <= 0n) {
            return "🔔 Nothing to call";
          }
          
          console.log(`📞 Agent calling ${ethers.formatEther(toCall)} FLOW...`);
          const callTx = await this.contract.call({ value: toCall });
          await callTx.wait();
          return `✅ Called ${ethers.formatEther(toCall)} FLOW`;

        case "fold":
          console.log("🏳️ Agent folding...");
          const foldTx = await this.contract.fold();
          await foldTx.wait();
          return "💥 Folded";

        case "roll":
          console.log("🎲 Agent rolling dice with VRF...");
          const rollTx = await this.contract.rollDice();
          await rollTx.wait();
          return "🎲 Dice rolled with VRF!";

        default:
          return "⏳ Waiting...";
      }
    } catch (error: any) {
      return `❌ Action failed: ${error.message}`;
    }
  }

  private async placeBet(amount: string): Promise<string> {
    console.log(`💰 Agent betting ${amount} FLOW...`);
    const wei = parseEther(amount);
    const tx = await this.contract.placeBet({ value: wei });
    await tx.wait();
    return `✅ Bet ${amount} FLOW`;
  }

  private isMyTurn(gameState: number, myIndex: number): boolean {
    const bettingStates = [1, 2, 3, 4, 7, 8, 9, 10, 13, 14, 15, 16, 19, 20, 21, 22];
    const rollingStates = [5, 6, 11, 12, 17, 18, 23, 24];
    
    if (gameState === 0) return myIndex === -1;
    
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

  private getRevealedDiceCount(state: number): number {
    if (state >= 23) return 5;
    if (state >= 17) return 3;
    if (state >= 11) return 2;
    if (state >= 5) return 1;
    return 0;
  }

  private getFallbackResponse(): string {
    const responses = [
      "Let's keep this interesting...",
      "Time to make a move!",
      "The dice gods are watching...",
      "Fortune favors the bold!",
      "Strategy over luck, always."
    ];
    return responses[Math.floor(Math.random() * responses.length)];
  }

  private async sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  public async runAgent(): Promise<void> {
    console.log(`\n🤖 Claude Poker Agent Starting on Flow EVM Testnet`);
    console.log(`🔑 Agent wallet: ${this.walletClient.account.address}`);
    console.log(`🎭 Personality: ${this.personality}`);
    console.log(`🧠 Powered by: Claude 3.5 Haiku`);
    console.log(`🕵️ On-chain opponent analysis: ENABLED`);
    console.log(`🎯 Ready to play poker with VRF randomness!\n`);

    // Check balance
    const balance = await this.publicClient.getBalance({ 
      address: this.walletClient.account.address 
    });
    console.log(`💰 Agent balance: ${ethers.formatEther(balance)} FLOW\n`);

    let gameRunning = true;
    while (gameRunning) {
      try {
        // Get current game state
        const gameState = await this.getGameState();
        console.log(`\n🎮 ${gameState.stateName} - Pot: ${gameState.pot} FLOW`);

        // Analyze opponent if we haven't already
        const opponentAddress = gameState.myIndex === 0 ? 
          gameState.players[1] : gameState.players[0];
          
        if (opponentAddress !== CONFIG.ZERO_ADDRESS && !this.opponentProfile) {
          console.log("🕵️ Analyzing opponent...");
          this.opponentProfile = await this.analyzeOpponent(opponentAddress);
          console.log(`📊 ${this.opponentProfile.personality}`);
        }

        if (gameState.isMyTurn) {
          // Ask Claude for decision
          const prompt = this.buildGamePrompt(gameState);
          const claudeResponse = await this.askClaude(prompt);
          const { action, message } = this.parseClaudeResponse(claudeResponse);
          
          console.log(`\n🤖 Agent: "${message}"`);
          
          // Execute the action
          const result = await this.executeAction(action);
          console.log(result);
          
          await this.sleep(2000);
        } else {
          // Check if game ended
          if (gameState.state === 27) { // GameEnded
            console.log("\n🏁 Game ended! Resetting...");
            this.opponentProfile = null;
            await this.sleep(10000);
            
            try {
              const resetTx = await this.contract.resetIfExpired();
              await resetTx.wait();
              console.log("🔄 Game reset");
            } catch (error) {
              console.log("⏳ Waiting for reset...");
            }
          } else {
            console.log("⏳ Waiting for opponent...");
            await this.sleep(5000);
          }
        }

      } catch (error: any) {
        console.error("🚨 Agent error:", error.message);
        if (error.message?.includes("502")) {
          console.log("🔄 Flow RPC down, waiting 10 seconds...");
          await this.sleep(10000);
        } else {
          await this.sleep(5000);
        }
      }
    }
  }
}

// Main execution
async function main() {
  const agentKey = process.env.AGENT_PRIVATE_KEY || process.env.PRIVATE_KEY_1;
  const personality = process.env.AGENT_PERSONALITY || "confident_professional";
  
  if (!agentKey) {
    console.error("❌ AGENT_PRIVATE_KEY or PRIVATE_KEY_1 not found");
    process.exit(1);
  }

  if (!process.env.ANTHROPIC_API_KEY) {
    console.error("❌ ANTHROPIC_API_KEY not found");
    console.log("💡 Get one from: https://console.anthropic.com");
    process.exit(1);
  }

  const agent = new ClaudePokerAgent(agentKey, personality);
  await agent.runAgent();
}

if (require.main === module) {
  main().catch(console.error);
}

export { ClaudePokerAgent };