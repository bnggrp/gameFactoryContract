// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract BaseGamePlatform is ReentrancyGuard {
    // ------ Structs ------
    struct Game {
        address player1;
        address player2;
        uint256 wager;
        address wagerToken; // address(0) = ETH
        uint256 createdAt;
        uint256 resolvedAt;
        address winner;
        bytes32 gameStateHash; // For custom game logic
    }

    // ------ Constants ------
    uint256 public constant FEE_PERCENT = 10; // 10% platform fee
    uint256 public constant DISPUTE_TIMEOUT = 2 hours;

    // ------ State ------
    address public immutable feeRecipient;
    mapping(uint256 => Game) public games;
    uint256 public nextGameId;

    // ------ Events ------
    event GameCreated(uint256 indexed gameId, address indexed player1, uint256 wager, address wagerToken);
    event GameJoined(uint256 indexed gameId, address indexed player2);
    event GameResolved(uint256 indexed gameId, address indexed winner, uint256 payout);
    event DisputeOpened(uint256 indexed gameId, address indexed disputer);
    event AdminResolution(uint256 indexed gameId, address indexed winner);

    // ------ Errors ------
    error InvalidWager();
    error Unauthorized();
    error GameNotActive();
    error InvalidResolution();
    error DisputeTimeoutNotReached();

    constructor(address _feeRecipient) {
        feeRecipient = _feeRecipient;
    }

    // ------ Core Functions ------
    function createGame(uint256 wager, address wagerToken) external payable nonReentrant {
        if (wager == 0) revert InvalidWager();
        
        // Handle ETH/ERC20 deposit
        if (wagerToken == address(0)) {
            if (msg.value != wager) revert InvalidWager();
        } else {
            IERC20(wagerToken).transferFrom(msg.sender, address(this), wager);
        }

        games[nextGameId] = Game({
            player1: msg.sender,
            player2: address(0),
            wager: wager,
            wagerToken: wagerToken,
            createdAt: block.timestamp,
            resolvedAt: 0,
            winner: address(0),
            gameStateHash: keccak256(abi.encode("INIT")) // Customize per game
        });

        emit GameCreated(nextGameId, msg.sender, wager, wagerToken);
        nextGameId++;
    }

    function joinGame(uint256 gameId) external payable nonReentrant {
        Game storage game = games[gameId];
        if (game.player1 == address(0)) revert InvalidWager();
        if (game.player2 != address(0)) revert GameNotActive();

        // Handle ETH/ERC20 deposit
        if (game.wagerToken == address(0)) {
            if (msg.value != game.wager) revert InvalidWager();
        } else {
            IERC20(game.wagerToken).transferFrom(msg.sender, address(this), game.wager);
        }

        game.player2 = msg.sender;
        emit GameJoined(gameId, msg.sender);
    }

    // ------ Game Resolution ------
    function resolveGame(uint256 gameId, address winner, bytes32 stateProof) external nonReentrant {
        Game storage game = games[gameId];
        if (game.player2 == address(0)) revert GameNotActive();
        if (winner != game.player1 && winner != game.player2) revert InvalidResolution();

        // Verify game state (customize per game logic)
        require(
            stateProof == keccak256(abi.encodePacked(game.player1, game.player2)), 
            "Invalid state proof"
        );

        _payout(gameId, winner);
    }

    function openDispute(uint256 gameId) external {
        Game storage game = games[gameId];
        if (msg.sender != game.player1 && msg.sender != game.player2) revert Unauthorized();
        if (block.timestamp < game.createdAt + DISPUTE_TIMEOUT) revert DisputeTimeoutNotReached();
        
        emit DisputeOpened(gameId, msg.sender);
    }

    // ------ Admin Functions ------
    function adminResolve(uint256 gameId, address winner) external onlyOwner {
        Game storage game = games[gameId];
        if (winner != game.player1 && winner != game.player2) revert InvalidResolution();
        
        _payout(gameId, winner);
        emit AdminResolution(gameId, winner);
    }

    // ------ Internal ------
    function _payout(uint256 gameId, address winner) private {
        Game storage game = games[gameId];
        game.winner = winner;
        game.resolvedAt = block.timestamp;

        uint256 totalPot = game.wager * 2;
        uint256 fee = (totalPot * FEE_PERCENT) / 100;
        uint256 payout = totalPot - fee;

        if (game.wagerToken == address(0)) {
            (bool success, ) = winner.call{value: payout}("");
            require(success, "ETH transfer failed");
            (success, ) = feeRecipient.call{value: fee}("");
            require(success, "Fee transfer failed");
        } else {
            IERC20(game.wagerToken).transfer(winner, payout);
            IERC20(game.wagerToken).transfer(feeRecipient, fee);
        }

        emit GameResolved(gameId, winner, payout);
    }

    // ------ Modifiers ------
    modifier onlyOwner() {
        require(msg.sender == feeRecipient, "Unauthorized");
        _;
    }
}