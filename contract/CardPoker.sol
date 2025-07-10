// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title DicePoker with Flow VRF
/// @notice Two-player "dice poker": 5 dice each, four betting rounds (before any reveal, after 1st, after 2nd, after 3rd die), then reveal final 2 dice and highest sum wins
/// @dev Uses Flow's native VRF for secure randomness
contract DicePoker {
    enum GameState {
        Joining,
        // Round 1 betting
        Player1Bet1, Player2BetOrCall1, Player1RaiseOrCall1, Player2RaiseOrCall1,
        // Reveal die 1
        Player1Roll1, Player2Roll1,
        // Round 2 betting
        Player1Bet2, Player2BetOrCall2, Player1RaiseOrCall2, Player2RaiseOrCall2,
        // Reveal die 2
        Player1Roll2, Player2Roll2,
        // Round 3 betting
        Player1Bet3, Player2BetOrCall3, Player1RaiseOrCall3, Player2RaiseOrCall3,
        // Reveal die 3
        Player1Roll3, Player2Roll3,
        // Round 4 betting
        Player1Bet4, Player2BetOrCall4, Player1RaiseOrCall4, Player2RaiseOrCall4,
        // Reveal final two
        Player1RollLast, Player2RollLast,
        // End
        DetermineWinner, Tie, GameEnded
    }

    // --- EVENTS ---
    event PlayerJoined(address indexed player);
    event BetPlaced(address indexed player, uint256 amount);
    event DiceRolled(address indexed player, uint8[5] dice);
    event WinnerDeclared(address indexed winner, uint256 payout);

    // --- CONSTANTS ---
    // Address of the Cadence Arch contract for VRF
    address constant public CADENCE_ARCH = 0x0000000000000000000000010000000000000001;

    // --- STATE ---
    GameState public currentState;
    address[2] public players;
    uint256 public pot;
    uint256 public currentBet;
    uint256[2] public bets;           // cumulative per‐game
    uint256[2] private roundBets;     // contributions in current sub‐round
    uint8[5][2] public playerDice;
    bool public gameStarted;
    address public currentBettor;
    address public winner;
    uint256 public gameEndedTimestamp;
    address private owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        currentState = GameState.Joining;
    }

    /// @notice Generate a secure random dice roll using Flow's VRF
    /// @return A random number between 1 and 6 (inclusive)
    function _rollSecureDie() internal view returns (uint8) {
        // Static call to the Cadence Arch contract's revertibleRandom function
        (bool ok, bytes memory data) = CADENCE_ARCH.staticcall(
            abi.encodeWithSignature("revertibleRandom()")
        );
        require(ok, "Failed to fetch random number from Flow VRF");
        
        uint64 randomNumber = abi.decode(data, (uint64));
        
        // Return a number between 1 and 6 (dice values)
        return uint8((randomNumber % 6) + 1);
    }

    /// @notice Generate multiple secure dice rolls
    /// @param count Number of dice to roll
    /// @return Array of dice values
    function _rollMultipleDice(uint8 count) internal view returns (uint8[] memory) {
        uint8[] memory dice = new uint8[](count);
        
        for (uint8 i = 0; i < count; i++) {
            // Get fresh randomness for each die by making separate calls
            (bool ok, bytes memory data) = CADENCE_ARCH.staticcall(
                abi.encodeWithSignature("revertibleRandom()")
            );
            require(ok, "Failed to fetch random number from Flow VRF");
            
            uint64 randomNumber = abi.decode(data, (uint64));
            dice[i] = uint8((randomNumber % 6) + 1);
        }
        
        return dice;
    }

    /// @notice How much `player` has put into the current betting sub-round
    function roundBet(address player) external view returns (uint256) {
        require(player == players[0] || player == players[1], "Not a player");
        uint8 idx = player == players[0] ? 0 : 1;
        return roundBets[idx];
    }

    /// @notice Join the game as player 1 or 2
    function joinGame() external {
        require(currentState == GameState.Joining, "Cannot join now");
        require(players[0] != msg.sender && players[1] != msg.sender, "Already joined");
        require(players[0] == address(0) || players[1] == address(0), "Game full");

        uint8 idx = players[0] == address(0) ? 0 : 1;
        players[idx] = msg.sender;
        emit PlayerJoined(msg.sender);

        if (players[0] != address(0) && players[1] != address(0)) {
            currentState  = GameState.Player1Bet1;
            gameStarted   = true;
            currentBettor = players[0];
        }
    }

    /// @notice Place or raise a bet in any of the four betting rounds
    function placeBet() external payable {
        require(gameStarted, "Game not started");
        uint8 idx = msg.sender == players[0] ? 0 : 1;

        if (currentState <= GameState.Player2RaiseOrCall1) {
            _place(idx, msg.value);
            _advanceBet1();
        } else if (currentState <= GameState.Player2RaiseOrCall2) {
            _place(idx, msg.value);
            _advanceBet2();
        } else if (currentState <= GameState.Player2RaiseOrCall3) {
            _place(idx, msg.value);
            _advanceBet3();
        } else if (currentState <= GameState.Player2RaiseOrCall4) {
            _place(idx, msg.value);
            _advanceBet4();
        } else {
            revert("Not in a betting round");
        }
    }

    function _place(uint8 idx, uint256 amount) internal {
        require(amount > 0, "Bet must be > 0");

        // first wager this sub-round resets currentBet
        if (
            currentState == GameState.Player1Bet1 ||
            currentState == GameState.Player1Bet2 ||
            currentState == GameState.Player1Bet3 ||
            currentState == GameState.Player1Bet4
        ) {
            currentBet = amount;
        } else {
            require(roundBets[idx] + amount >= currentBet, "Underbet");
            if (roundBets[idx] + amount > currentBet) {
                currentBet = roundBets[idx] + amount;
            }
        }

        roundBets[idx] += amount;
        bets[idx]      += amount;
        pot            += amount;
        emit BetPlaced(msg.sender, amount);
    }

    function _advanceBet1() internal {
        if (currentState == GameState.Player1Bet1) {
            currentState  = GameState.Player2BetOrCall1;
            currentBettor = players[1];
        } else if (currentState == GameState.Player2BetOrCall1) {
            currentState  = GameState.Player1RaiseOrCall1;
            currentBettor = players[0];
        } else if (currentState == GameState.Player1RaiseOrCall1) {
            currentState  = GameState.Player2RaiseOrCall1;
            currentBettor = players[1];
        } else {
            // both matched → reveal die 1
            currentState  = GameState.Player1Roll1;
            currentBettor = players[0];
            _resetRound();
        }
    }

    function _advanceBet2() internal {
        if (currentState == GameState.Player1Bet2) {
            currentState  = GameState.Player2BetOrCall2;
            currentBettor = players[1];
        } else if (currentState == GameState.Player2BetOrCall2) {
            currentState  = GameState.Player1RaiseOrCall2;
            currentBettor = players[0];
        } else if (currentState == GameState.Player1RaiseOrCall2) {
            currentState  = GameState.Player2RaiseOrCall2;
            currentBettor = players[1];
        } else {
            currentState  = GameState.Player1Roll2;
            currentBettor = players[0];
            _resetRound();
        }
    }

    function _advanceBet3() internal {
        if (currentState == GameState.Player1Bet3) {
            currentState  = GameState.Player2BetOrCall3;
            currentBettor = players[1];
        } else if (currentState == GameState.Player2BetOrCall3) {
            currentState  = GameState.Player1RaiseOrCall3;
            currentBettor = players[0];
        } else if (currentState == GameState.Player1RaiseOrCall3) {
            currentState  = GameState.Player2RaiseOrCall3;
            currentBettor = players[1];
        } else {
            currentState  = GameState.Player1Roll3;
            currentBettor = players[0];
            _resetRound();
        }
    }

    function _advanceBet4() internal {
        if (currentState == GameState.Player1Bet4) {
            currentState  = GameState.Player2BetOrCall4;
            currentBettor = players[1];
        } else if (currentState == GameState.Player2BetOrCall4) {
            currentState  = GameState.Player1RaiseOrCall4;
            currentBettor = players[0];
        } else if (currentState == GameState.Player1RaiseOrCall4) {
            currentState  = GameState.Player2RaiseOrCall4;
            currentBettor = players[1];
        } else {
            currentState  = GameState.Player1RollLast;
            currentBettor = players[0];
            _resetRound();
        }
    }

    /// @notice Call matches the current bet and advances immediately to the next reveal
    function call() external payable {
        require(gameStarted, "Not started");
        uint8 idx = msg.sender == players[0] ? 0 : 1;

        uint256 toCall = currentBet - roundBets[idx];
        require(toCall > 0, "Nothing to call");
        require(msg.value == toCall, "Incorrect call amount");

        // collect funds
        roundBets[idx] += msg.value;
        bets[idx]      += msg.value;
        pot            += msg.value;
        emit BetPlaced(msg.sender, msg.value);

        // **skip** all raise states and go straight to the next reveal
        if (currentState <= GameState.Player2RaiseOrCall1) {
            // end of round 1 → reveal die 1
            currentState  = GameState.Player1Roll1;
            currentBettor = players[0];
        } else if (currentState <= GameState.Player2RaiseOrCall2) {
            // end of round 2 → reveal die 2
            currentState  = GameState.Player1Roll2;
            currentBettor = players[0];
        } else if (currentState <= GameState.Player2RaiseOrCall3) {
            // end of round 3 → reveal die 3
            currentState  = GameState.Player1Roll3;
            currentBettor = players[0];
        } else if (currentState <= GameState.Player2RaiseOrCall4) {
            // end of round 4 → reveal final two dice
            currentState  = GameState.Player1RollLast;
            currentBettor = players[0];
        } else {
            revert("Not in call phase");
        }

        // clear the per-round counters for the next betting sub-round
        _resetRound();
    }

    /// @notice Fold and concede the pot in any betting sub-round
    function fold() external {
        require(gameStarted, "Not started");
        uint8 idx = msg.sender == players[0] ? 0 : 1;
        require(
            (currentState <= GameState.Player2RaiseOrCall1) ||
            (currentState >= GameState.Player1Bet2 && currentState <= GameState.Player2RaiseOrCall2) ||
            (currentState >= GameState.Player1Bet3 && currentState <= GameState.Player2RaiseOrCall3) ||
            (currentState >= GameState.Player1Bet4 && currentState <= GameState.Player2RaiseOrCall4),
            "Cannot fold now"
        );
        winner = players[1 - idx];
        _finalize();
    }

    /// @notice Reveal dice one‐by‐one for first three, then two at once using secure VRF
    function rollDice() external {
        require(gameStarted, "Not started");
        uint8 idx = msg.sender == players[0] ? 0 : 1;

        // die-1
        if (currentState == GameState.Player1Roll1 && idx == 0) {
            playerDice[idx][0] = _rollSecureDie();
            emit DiceRolled(msg.sender, playerDice[idx]);

            currentState  = GameState.Player2Roll1;
            currentBettor = players[1];

        } else if (currentState == GameState.Player2Roll1 && idx == 1) {
            playerDice[idx][0] = _rollSecureDie();
            emit DiceRolled(msg.sender, playerDice[idx]);

            currentState  = GameState.Player1Bet2;
            currentBettor = players[0];

        // die-2
        } else if (currentState == GameState.Player1Roll2 && idx == 0) {
            playerDice[idx][1] = _rollSecureDie();
            emit DiceRolled(msg.sender, playerDice[idx]);

            currentState  = GameState.Player2Roll2;
            currentBettor = players[1];

        } else if (currentState == GameState.Player2Roll2 && idx == 1) {
            playerDice[idx][1] = _rollSecureDie();
            emit DiceRolled(msg.sender, playerDice[idx]);

            currentState  = GameState.Player1Bet3;
            currentBettor = players[0];

        // die-3
        } else if (currentState == GameState.Player1Roll3 && idx == 0) {
            playerDice[idx][2] = _rollSecureDie();
            emit DiceRolled(msg.sender, playerDice[idx]);

            currentState  = GameState.Player2Roll3;
            currentBettor = players[1];

        } else if (currentState == GameState.Player2Roll3 && idx == 1) {
            playerDice[idx][2] = _rollSecureDie();
            emit DiceRolled(msg.sender, playerDice[idx]);

            currentState  = GameState.Player1Bet4;
            currentBettor = players[0];

        // final two at once using VRF
        } else if (currentState == GameState.Player1RollLast && idx == 0) {
            uint8[] memory lastTwoDice = _rollMultipleDice(2);
            playerDice[idx][3] = lastTwoDice[0];
            playerDice[idx][4] = lastTwoDice[1];
            emit DiceRolled(msg.sender, playerDice[idx]);

            currentState  = GameState.Player2RollLast;
            currentBettor = players[1];

        } else if (currentState == GameState.Player2RollLast && idx == 1) {
            uint8[] memory lastTwoDice = _rollMultipleDice(2);
            playerDice[idx][3] = lastTwoDice[0];
            playerDice[idx][4] = lastTwoDice[1];
            emit DiceRolled(msg.sender, playerDice[idx]);

            currentState = GameState.DetermineWinner;
            _determineWinner();

        } else {
            revert("Not in a reveal phase for you");
        }
    }

    /// @notice Compare sums and finalize
    function _determineWinner() internal {
        uint16 sum0;
        uint16 sum1;
        for (uint8 i = 0; i < 5; i++) {
            sum0 += playerDice[0][i];
            sum1 += playerDice[1][i];
        }
        winner = sum0 > sum1 ? players[0]
               : sum1 > sum0 ? players[1]
                             : address(0);
        _finalize();
    }

    function _finalize() internal {
        if (winner != address(0)) {
            payable(winner).transfer(pot);
        } else {
            payable(players[0]).transfer(pot / 2);
            payable(players[1]).transfer(pot / 2);
        }
        emit WinnerDeclared(winner, pot);
        gameEndedTimestamp = block.timestamp;
        currentState       = GameState.GameEnded;
    }

    /// @notice After 5s post-game, reset is allowed
    function resetIfExpired() external {
        require(currentState == GameState.GameEnded, "Game not ended");
        require(block.timestamp >= gameEndedTimestamp + 5, "Wait 5s");
        _reset();
    }

    function _reset() internal {
        delete players;
        delete bets;
        delete roundBets;
        delete playerDice;
        pot            = 0;
        currentBet     = 0;
        gameStarted    = false;
        winner         = address(0);
        currentState   = GameState.Joining;
        currentBettor  = address(0);
    }

    /// @notice Clear only the per‐round trackers
    function _resetRound() internal {
        roundBets[0] = 0;
        roundBets[1] = 0;
        currentBet   = 0;
    }

    receive() external payable {}
}