// dice poker script for Flow EVM Testnet with VRF!

require("dotenv").config();
const hre      = require("hardhat");
const { ethers, network } = hre;
const fs       = require("fs");
const path     = require("path");
const readline = require("readline");

// Flow EVM Testnet
const CONTRACT_ADDRESS = "0xC0933C5440c656464D1Eb1F886422bE3466B1459"; // Your deployed address
const ZERO_ADDRESS     = "0x0000000000000000000000000000000000000000";

// 28 states, matching the 4-round + 5-reveal flow:
const STATE_NAMES = [
  "Joining",
  // Round 1 betting
  "Player1Bet1","Player2BetOrCall1","Player1RaiseOrCall1","Player2RaiseOrCall1",
  // Reveal die 1
  "Player1Roll1","Player2Roll1",
  // Round 2 betting
  "Player1Bet2","Player2BetOrCall2","Player1RaiseOrCall2","Player2RaiseOrCall2",
  // Reveal die 2
  "Player1Roll2","Player2Roll2",
  // Round 3 betting
  "Player1Bet3","Player2BetOrCall3","Player1RaiseOrCall3","Player2RaiseOrCall3",
  // Reveal die 3
  "Player1Roll3","Player2Roll3",
  // Round 4 betting
  "Player1Bet4","Player2BetOrCall4","Player1RaiseOrCall4","Player2RaiseOrCall4",
  // Reveal final two dice
  "Player1RollLast","Player2RollLast",
  // Finish
  "DetermineWinner","Tie","GameEnded"
];

async function main() {
  console.log(`\n🎲 DicePoker CLI on ${network.name} with Flow VRF`);
  console.log("🔮 Using cryptographically secure randomness from Flow's native VRF!");
  console.log("🏆 Win by highest total of your 5 dice; tie splits the pot.\n");

  // ── prepare logs directory & file ──
  const logsDir = path.join(__dirname, "logs");
  fs.mkdirSync(logsDir, { recursive: true });
  const chainId = network.config.chainId;
  const logFile = path.join(logsDir, `${network.name}-${chainId}.log`);
  async function logTx(action, receipt, startMs, endMs, params = {}) {
    const entry = [
      new Date().toISOString(),
      action,
      `params=${JSON.stringify(params)}`,
      `receipt=${JSON.stringify(receipt)}`,
      `timeMs=${(endMs - startMs).toString()}`
    ].join(" | ") + "\n";
    fs.appendFileSync(logFile, entry);
  }

  // ── pick your account ──
  const signers = await ethers.getSigners();
  console.log("Available accounts:");
  signers.forEach((s,i) => console.log(`  [${i}] ${s.address}`));
  const rl0 = readline.createInterface({ input: process.stdin, output: process.stdout });
  const ask0 = q => new Promise(res => rl0.question(q, res));
  let idx;
  while (true) {
    const a = await ask0("Select account index: ");
    idx = parseInt(a.trim(), 10);
    if (!isNaN(idx) && idx >= 0 && idx < signers.length) break;
    console.log("Invalid, try again.");
  }
  rl0.close();
  const user = signers[idx];
  console.log(`Using account: ${user.address}\n`);

  // ── attach to contract ──
  const poker = await ethers.getContractAt("DicePoker", CONTRACT_ADDRESS, user);

  // helper: fetch full 5-die array with retry logic
  async function getDice(pi) {
    const arr = [];
    for (let j = 0; j < 5; j++) {
      let retries = 3;
      while (retries > 0) {
        try {
          arr.push(Number(await poker.playerDice(pi, j)));
          break;
        } catch (error) {
          retries--;
          if (retries === 0) {
            console.log(`⚠️ RPC error fetching dice, using 0 for display`);
            arr.push(0);
          } else {
            console.log(`🔄 RPC timeout, retrying... (${retries} left)`);
            await new Promise(resolve => setTimeout(resolve, 1000));
          }
        }
      }
    }
    return arr;
  }
  // helper: mask unrevealed dice based on state
  function maskDice(arr, state) {
    let revealed = 0;
    if (state >= 23) revealed = 5;      // after final-two reveal
    else if (state >= 17) revealed = 3; // after die 3
    else if (state >= 11) revealed = 2; // after die 2
    else if (state >= 5)  revealed = 1; // after die 1
    return arr.map((d,i) => i < revealed ? d : "–");
  }

  // ── main loop with error handling ──
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const ask = q => new Promise(res => rl.question(q, res));

  while (true) {
    try {
      const state   = Number(await poker.currentState());
      const players = [await poker.players(0), await poker.players(1)];
      const bets    = [await poker.bets(0),    await poker.bets(1)];
      const raw1    = await getDice(0);
      const raw2    = await getDice(1);
      const meIdx   = players.findIndex(p => p.toLowerCase() === user.address.toLowerCase());

      console.log(`\n=== ${STATE_NAMES[state]} ===`);
      console.log(`Players: P1=${players[0]}  P2=${players[1]}`);
      console.log(`Bets:    P1=${ethers.formatEther(bets[0])} FLOW  P2=${ethers.formatEther(bets[1])} FLOW`);
      console.log(
        `Dice:    P1=[${maskDice(raw1, state).join(", ")}]  ` +
        `P2=[${maskDice(raw2, state).join(", ")}]`
      );

      // Show VRF info when rolling dice
      if ([5, 6, 11, 12, 17, 18, 23, 24].includes(state)) {
        console.log("🔮 Next dice roll will use Flow's secure VRF randomness!");
      }

      // ── build menu ──
      const menu = [];
      // Join
      if (state === 0 && meIdx === -1 && players.includes(ZERO_ADDRESS)) {
        menu.push({ desc: "Join Game", fn: joinGame });
      }
      // Betting (any of the 4 rounds)
      if (
        ((state >= 1 && state <= 4)   ||
         (state >= 7 && state <= 10)  ||
         (state >= 13 && state <= 16) ||
         (state >= 19 && state <= 22))
        && meIdx !== -1
      ) {
        const turn = (state % 2 === 1 ? 0 : 1);
        if (meIdx === turn) {
          menu.push({ desc: "Place/Raise Bet", fn: placeBet });
          menu.push({ desc: "Call",             fn: callBet });
          menu.push({ desc: "Fold",             fn: foldGame });
        }
      }
      // Reveal die 1
      if ((state === 5 || state === 6) && meIdx !== -1) {
        const turn = (state === 5 ? 0 : 1);
        if (meIdx === turn) menu.push({ desc: "🎲 Reveal die 1 (VRF)", fn: rollDice });
      }
      // Reveal die 2
      if ((state === 11 || state === 12) && meIdx !== -1) {
        const turn = (state === 11 ? 0 : 1);
        if (meIdx === turn) menu.push({ desc: "🎲 Reveal die 2 (VRF)", fn: rollDice });
      }
      // Reveal die 3
      if ((state === 17 || state === 18) && meIdx !== -1) {
        const turn = (state === 17 ? 0 : 1);
        if (meIdx === turn) menu.push({ desc: "🎲 Reveal die 3 (VRF)", fn: rollDice });
      }
      // Reveal final two dice
      if ((state === 23 || state === 24) && meIdx !== -1) {
        const turn = (state === 23 ? 0 : 1);
        if (meIdx === turn) menu.push({ desc: "🎲🎲 Reveal final 2 dice (VRF)", fn: rollDice });
      }
      // Always allow showing hands and VRF info
      menu.push({ desc: "Show Hands", fn: showHands });
      menu.push({ desc: "🔮 VRF Info", fn: showVRFInfo });
      // Reset after game end
      if (state === STATE_NAMES.indexOf("GameEnded")) {
        menu.push({ desc: "Reset Game (if ≥5s)", fn: resetGame });
      }
      // Exit
      menu.push({ desc: "Exit", fn: exitCLI });

      // ── print and handle choice ──
      console.log("\nOptions:");
      menu.forEach((m,i) => console.log(`  ${i+1}) ${m.desc}`));
      const choice = parseInt(await ask("Choice: "), 10);
      if (isNaN(choice) || choice < 1 || choice > menu.length) {
        console.log("Invalid"); 
        continue;
      }
      try {
        await menu[choice - 1].fn();
      } catch (err) {
        console.error("⚠️", err.message || err);
        if (err.message && err.message.includes("502")) {
          console.log("🔄 Flow RPC is temporarily down. Waiting 5 seconds...");
          await new Promise(resolve => setTimeout(resolve, 5000));
        }
      }
    } catch (error) {
      console.error("🚨 Network error:", error.message);
      console.log("🔄 Retrying in 3 seconds...");
      await new Promise(resolve => setTimeout(resolve, 3000));
    }
  }

  // ── Handlers ──
  async function joinGame() {
    const start = Date.now();
    const tx    = await poker.joinGame();
    const rcpt  = await tx.wait();
    const end   = Date.now();
    await logTx("joinGame", rcpt, start, end);
    console.log("✅ Joined game");
  }

  async function placeBet() {
    const amt   = await ask("Amount (FLOW): ");
    const wei   = ethers.parseEther(amt);
    const start = Date.now();
    const tx    = await poker.placeBet({ value: wei });
    const rcpt  = await tx.wait();
    const end   = Date.now();
    await logTx("placeBet", rcpt, start, end, { amount: amt });
    console.log(`✅ Bet ${amt} FLOW`);
  }

  async function callBet() {
    // fetch how much they still owe in *this* sub-round
    const current       = await poker.currentBet();
    const roundCommitted= await poker.roundBet(user.address);
    const toCall        = current - roundCommitted;
    if (toCall === 0n) {
      console.log("🔔 Nothing to call");
      return;
    }
    console.log(`Calling ${ethers.formatEther(toCall)} FLOW...`);
    const start = Date.now();
    const tx    = await poker.call({ value: toCall });
    const rcpt  = await tx.wait();
    const end   = Date.now();
    await logTx("call", rcpt, start, end, { amount: ethers.formatEther(toCall) });
    console.log("✅ Called");
  }

  async function foldGame() {
    const start = Date.now();
    const tx    = await poker.fold();
    const rcpt  = await tx.wait();
    const end   = Date.now();
    await logTx("fold", rcpt, start, end);
    console.log("💥 You folded");
  }

  async function rollDice() {
    const prev  = Number(await poker.currentState());
    console.log("🔮 Calling Flow VRF for secure randomness...");
    const start = Date.now();
    const tx    = await poker.rollDice();
    const rcpt  = await tx.wait();
    const end   = Date.now();
    await logTx("rollDice", rcpt, start, end);
    console.log("🎲 Dice rolled with cryptographically secure randomness!");

    // after final-two reveal (state 24 → 25), show totals
    if (prev === 24) {
      const h1   = await getDice(0);
      const h2   = await getDice(1);
      const sum1 = h1.reduce((a,b) => a + b, 0);
      const sum2 = h2.reduce((a,b) => a + b, 0);
      console.log("\n🏁 Final Hands:");
      console.log(` P1: ${h1.join(", ")}  (sum=${sum1})`);
      console.log(` P2: ${h2.join(", ")}  (sum=${sum2})`);
      console.log(
        sum1 > sum2 ? "🏆 Winner: P1"
      : sum2 > sum1 ? "🏆 Winner: P2"
      :                "🤝 It's a tie — pot split"
      );
    }
  }

  async function showHands() {
    const h1 = await getDice(0);
    const h2 = await getDice(1);
    console.log("P1 Dice:", h1.join(", "));
    console.log("P2 Dice:", h2.join(", "));
  }

  async function showVRFInfo() {
    const cadenceArch = await poker.CADENCE_ARCH();
    console.log("\n🔮 Flow VRF Information:");
    console.log(`   Cadence Arch Address: ${cadenceArch}`);
    console.log(`   Randomness Source: Flow Native VRF`);
    console.log(`   Security: Cryptographically secure, tamper-proof`);
    console.log(`   Network: Flow EVM Testnet`);
    console.log(`   Chain ID: 545`);
    console.log("   Benefits:");
    console.log("   ✅ Unpredictable dice outcomes");
    console.log("   ✅ No MEV attacks possible");
    console.log("   ✅ Fair for all players");
    console.log("   ✅ Verifiable randomness");
  }

  async function resetGame() {
    console.log("Resetting game (if ≥5s have passed) …");
    const tx   = await poker.resetIfExpired();
    await tx.wait();
    console.log("✅ Game reset. Back to Joining.");
  }

  function exitCLI() {
    console.log("🎉 Thanks for playing DicePoker with Flow VRF!");
    console.log("🔗 Explore more: https://evm-testnet.flowscan.io");
    process.exit(0);
  }
}

main().catch(e => {
  console.error(e);
  process.exit(1);
});