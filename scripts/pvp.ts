import { ethers } from 'ethers';
import * as readline from 'readline';
import * as fs from 'fs';
import * as path from 'path';
import * as dotenv from 'dotenv';

// Load environment variables
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

// Contract ABI (minimal required functions)
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
  "event PlayerJoined(address indexed player)",
  "event BetPlaced(address indexed player, uint256 amount)",
  "event DiceRolled(address indexed player, uint8[5] dice)",
  "event WinnerDeclared(address indexed winner, uint256 payout)"
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

interface GameState {
  state: number;
  players: [string, string];
  bets: [bigint, bigint];
  dice: [number[], number[]];
  meIdx: number;
}

class DicePokerClient {
  private provider: ethers.JsonRpcProvider;
  private wallet: ethers.Wallet;
  private contract: ethers.Contract;
  private rl: readline.Interface;

  constructor(privateKey: string) {
    this.provider = new ethers.JsonRpcProvider(CONFIG.FLOW_TESTNET.rpc);
    this.wallet = new ethers.Wallet(privateKey, this.provider);
    this.contract = new ethers.Contract(CONFIG.CONTRACT_ADDRESS, DICE_POKER_ABI, this.wallet);
    this.rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout
    });
  }

  private ask(question: string): Promise<string> {
    return new Promise((resolve) => {
      this.rl.question(question, resolve);
    });
  }

  private async getDice(playerIndex: number): Promise<number[]> {
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

  private maskDice(dice: number[], state: number): (number | string)[] {
    let revealed = 0;
    if (state >= 23) revealed = 5;      // after final-two reveal
    else if (state >= 17) revealed = 3; // after die 3
    else if (state >= 11) revealed = 2; // after die 2
    else if (state >= 5) revealed = 1;  // after die 1
    return dice.map((d, i) => i < revealed ? d : "–");
  }

  private async getGameState(): Promise<GameState> {
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

  private async sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  private async logTransaction(action: string, receipt: any, startTime: number, params: any = {}) {
    const logsDir = path.join(process.cwd(), "logs");
    if (!fs.existsSync(logsDir)) {
      fs.mkdirSync(logsDir, { recursive: true });
    }
    
    const logFile = path.join(logsDir, `flow-testnet-545.log`);
    const entry = [
      new Date().toISOString(),
      action,
      `params=${JSON.stringify(params)}`,
      `receipt=${JSON.stringify(receipt)}`,
      `timeMs=${(Date.now() - startTime).toString()}`
    ].join(" | ") + "\n";
    
    fs.appendFileSync(logFile, entry);
  }

  // Game actions
  private async joinGame(): Promise<void> {
    const startTime = Date.now();
    console.log("🎮 Joining game...");
    const tx = await this.contract.joinGame();
    const receipt = await tx.wait();
    await this.logTransaction("joinGame", receipt, startTime);
    console.log("✅ Joined game successfully!");
  }

  private async placeBet(): Promise<void> {
    const amount = await this.ask("💰 Enter bet amount (FLOW): ");
    const wei = ethers.parseEther(amount);
    const startTime = Date.now();
    
    console.log(`💸 Placing bet of ${amount} FLOW...`);
    const tx = await this.contract.placeBet({ value: wei });
    const receipt = await tx.wait();
    await this.logTransaction("placeBet", receipt, startTime, { amount });
    console.log(`✅ Bet placed: ${amount} FLOW`);
  }

  private async callBet(): Promise<void> {
    const currentBet = await this.contract.currentBet();
    const roundCommitted = await this.contract.roundBet(this.wallet.address);
    const toCall = currentBet - roundCommitted;
    
    // Fix: Proper BigInt comparison
    if (toCall <= 0n) {
        console.log("🔔 Nothing to call");
        return;
      }
    
    const startTime = Date.now();
    console.log(`📞 Calling ${ethers.formatEther(toCall)} FLOW...`);
    const tx = await this.contract.call({ value: toCall });
    const receipt = await tx.wait();
    await this.logTransaction("call", receipt, startTime, { amount: ethers.formatEther(toCall) });
    console.log("✅ Call successful");
  }

  private async fold(): Promise<void> {
    const startTime = Date.now();
    console.log("🏳️ Folding...");
    const tx = await this.contract.fold();
    const receipt = await tx.wait();
    await this.logTransaction("fold", receipt, startTime);
    console.log("💥 You folded");
  }

  private async rollDice(): Promise<void> {
    const previousState = Number(await this.contract.currentState());
    const startTime = Date.now();
    
    console.log("🔮 Calling Flow VRF for secure randomness...");
    const tx = await this.contract.rollDice();
    const receipt = await tx.wait();
    await this.logTransaction("rollDice", receipt, startTime);
    console.log("🎲 Dice rolled with cryptographically secure randomness!");

    // Show final results if this was the last roll
    if (previousState === 24) {
      await this.sleep(1000); // Wait for state to update
      const gameState = await this.getGameState();
      const sum1 = gameState.dice[0].reduce((a, b) => a + b, 0);
      const sum2 = gameState.dice[1].reduce((a, b) => a + b, 0);
      
      console.log("\n🏁 Final Hands:");
      console.log(` P1: [${gameState.dice[0].join(", ")}] (sum=${sum1})`);
      console.log(` P2: [${gameState.dice[1].join(", ")}] (sum=${sum2})`);
      console.log(
        sum1 > sum2 ? "🏆 Winner: P1" :
        sum2 > sum1 ? "🏆 Winner: P2" :
        "🤝 It's a tie — pot split"
      );
    }
  }

  private async showVRFInfo(): Promise<void> {
    const cadenceArch = await this.contract.CADENCE_ARCH();
    console.log("\n🔮 Flow VRF Information:");
    console.log(`   Cadence Arch Address: ${cadenceArch}`);
    console.log(`   Randomness Source: Flow Native VRF`);
    console.log(`   Security: Cryptographically secure, tamper-proof`);
    console.log(`   Network: ${CONFIG.FLOW_TESTNET.name}`);
    console.log(`   Chain ID: ${CONFIG.FLOW_TESTNET.chainId}`);
    console.log("   Benefits:");
    console.log("   ✅ Unpredictable dice outcomes");
    console.log("   ✅ No MEV attacks possible");
    console.log("   ✅ Fair for all players");
    console.log("   ✅ Verifiable randomness");
  }

  private async resetGame(): Promise<void> {
    console.log("🔄 Resetting game (if ≥5s have passed)...");
    const tx = await this.contract.resetIfExpired();
    await tx.wait();
    console.log("✅ Game reset. Back to Joining state.");
  }

  public async run(): Promise<void> {
    console.log(`\n🎲 DicePoker PVP Client on ${CONFIG.FLOW_TESTNET.name}`);
    console.log("🔮 Using cryptographically secure randomness from Flow's native VRF!");
    console.log("🏆 Win by highest total of your 5 dice; tie splits the pot.");
    console.log(`🔑 Using wallet: ${this.wallet.address}\n`);

    // Check balance
    const balance = await this.provider.getBalance(this.wallet.address);
    console.log(`💰 Balance: ${ethers.formatEther(balance)} FLOW\n`);

    while (true) {
      try {
        const gameState = await this.getGameState();
        
        console.log(`\n=== ${STATE_NAMES[gameState.state]} ===`);
        console.log(`Players: P1=${gameState.players[0]}  P2=${gameState.players[1]}`);
        console.log(`Bets:    P1=${ethers.formatEther(gameState.bets[0])} FLOW  P2=${ethers.formatEther(gameState.bets[1])} FLOW`);
        console.log(`Dice:    P1=[${this.maskDice(gameState.dice[0], gameState.state).join(", ")}]  P2=[${this.maskDice(gameState.dice[1], gameState.state).join(", ")}]`);

        // Show VRF info when rolling dice
        if ([5, 6, 11, 12, 17, 18, 23, 24].includes(gameState.state)) {
          console.log("🔮 Next dice roll will use Flow's secure VRF randomness!");
        }

        // Build menu
        const menu: Array<{ desc: string; action: () => Promise<void> }> = [];

        // Join game
        if (gameState.state === 0 && gameState.meIdx === -1 && gameState.players.includes(CONFIG.ZERO_ADDRESS)) {
          menu.push({ desc: "🎮 Join Game", action: () => this.joinGame() });
        }

        // Betting rounds
        if (((gameState.state >= 1 && gameState.state <= 4) ||
             (gameState.state >= 7 && gameState.state <= 10) ||
             (gameState.state >= 13 && gameState.state <= 16) ||
             (gameState.state >= 19 && gameState.state <= 22)) &&
            gameState.meIdx !== -1) {
          const turn = gameState.state % 2 === 1 ? 0 : 1;
          if (gameState.meIdx === turn) {
            menu.push({ desc: "💰 Place/Raise Bet", action: () => this.placeBet() });
            menu.push({ desc: "📞 Call", action: () => this.callBet() });
            menu.push({ desc: "🏳️ Fold", action: () => this.fold() });
          }
        }

        // Dice rolling
        if ((gameState.state === 5 || gameState.state === 6) && gameState.meIdx !== -1) {
          const turn = gameState.state === 5 ? 0 : 1;
          if (gameState.meIdx === turn) menu.push({ desc: "🎲 Reveal die 1 (VRF)", action: () => this.rollDice() });
        }
        if ((gameState.state === 11 || gameState.state === 12) && gameState.meIdx !== -1) {
          const turn = gameState.state === 11 ? 0 : 1;
          if (gameState.meIdx === turn) menu.push({ desc: "🎲 Reveal die 2 (VRF)", action: () => this.rollDice() });
        }
        if ((gameState.state === 17 || gameState.state === 18) && gameState.meIdx !== -1) {
          const turn = gameState.state === 17 ? 0 : 1;
          if (gameState.meIdx === turn) menu.push({ desc: "🎲 Reveal die 3 (VRF)", action: () => this.rollDice() });
        }
        if ((gameState.state === 23 || gameState.state === 24) && gameState.meIdx !== -1) {
          const turn = gameState.state === 23 ? 0 : 1;
          if (gameState.meIdx === turn) menu.push({ desc: "🎲🎲 Reveal final 2 dice (VRF)", action: () => this.rollDice() });
        }

        // Always available options
        menu.push({ desc: "👁️ Show Hands", action: async () => {
          console.log(`P1 Dice: [${gameState.dice[0].join(", ")}]`);
          console.log(`P2 Dice: [${gameState.dice[1].join(", ")}]`);
        }});
        menu.push({ desc: "🔮 VRF Info", action: () => this.showVRFInfo() });

        // Reset game
        if (gameState.state === STATE_NAMES.indexOf("GameEnded")) {
          menu.push({ desc: "🔄 Reset Game (if ≥5s)", action: () => this.resetGame() });
        }

        // Exit
        menu.push({ desc: "🚪 Exit", action: async () => {
          console.log("🎉 Thanks for playing DicePoker with Flow VRF!");
          this.rl.close();
          process.exit(0);
        }});

        // Show menu and get choice
        console.log("\nOptions:");
        menu.forEach((item, i) => console.log(`  ${i + 1}) ${item.desc}`));
        
        const choiceStr = await this.ask("Choice: ");
        const choice = parseInt(choiceStr.trim(), 10);
        
        if (isNaN(choice) || choice < 1 || choice > menu.length) {
          console.log("❌ Invalid choice");
          continue;
        }

        await menu[choice - 1].action();

      } catch (error: any) {
        console.error("🚨 Error:", error.message);
        if (error.message && error.message.includes("502")) {
          console.log("🔄 Flow RPC is temporarily down. Waiting 5 seconds...");
          await this.sleep(5000);
        } else {
          console.log("🔄 Retrying in 3 seconds...");
          await this.sleep(3000);
        }
      }
    }
  }
}

// Main execution
async function main() {
  const privateKey = process.env.PRIVATE_KEY;
  if (!privateKey) {
    console.error("❌ PRIVATE_KEY not found in environment variables");
    process.exit(1);
  }

  const client = new DicePokerClient(privateKey);
  await client.run();
}

if (require.main === module) {
  main().catch(console.error);
}

export { DicePokerClient };