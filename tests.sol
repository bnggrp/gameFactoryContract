// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./BaseGamePlatform.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock USDC", "mUSDC") {
        _mint(msg.sender, 1000000 * 10**18);
    }
}

contract BaseGamePlatformTest is Test {
    BaseGamePlatform platform;
    MockERC20 usdc;
    
    address admin = vm.addr(1);
    address player1 = vm.addr(2);
    address player2 = vm.addr(3);
    address attacker = vm.addr(999);

    uint256 constant WAGER_ETH = 1 ether;
    uint256 constant WAGER_ERC20 = 100 * 10**18;

    function setUp() public {
        vm.deal(player1, 10 ether);
        vm.deal(player2, 10 ether);
        
        usdc = new MockERC20();
        platform = new BaseGamePlatform(admin);

        // Fund players with mock USDC
        usdc.transfer(player1, WAGER_ERC20 * 2);
        usdc.transfer(player2, WAGER_ERC20 * 2);
    }

    // ---- ETH Games ----
    function testCreateEthGame() public {
        vm.prank(player1);
        platform.createGame{value: WAGER_ETH}(WAGER_ETH, address(0));
        
        (uint256 gameId, , , ) = _getLastGame();
        (address p1, , uint256 wager, , , , ) = platform.games(gameId);
        
        assertEq(p1, player1);
        assertEq(wager, WAGER_ETH);
        assertEq(address(platform).balance, WAGER_ETH);
    }

    function testJoinAndResolveEthGame() public {
        // Create
        vm.prank(player1);
        platform.createGame{value: WAGER_ETH}(WAGER_ETH, address(0));
        (uint256 gameId, , , ) = _getLastGame();

        // Join
        vm.prank(player2);
        platform.joinGame{value: WAGER_ETH}(gameId);
        
        // Resolve
        uint256 winnerBalanceBefore = player1.balance;
        vm.prank(player1);
        platform.resolveGame(gameId, player1, keccak256(abi.encodePacked(player1, player2)));
        
        // Verify
        (, , , , , uint256 resolvedAt, address winner) = platform.games(gameId);
        assertEq(resolvedAt > 0, true);
        assertEq(winner, player1);
        assertEq(player1.balance, winnerBalanceBefore + (WAGER_ETH * 18 / 10)); // 1.8x payout
    }

    // ---- ERC20 Games ----
    function testCreateERC20Game() public {
        vm.startPrank(player1);
        usdc.approve(address(platform), WAGER_ERC20);
        platform.createGame(WAGER_ERC20, address(usdc));
        vm.stopPrank();

        (uint256 gameId, , , ) = _getLastGame();
        (, , uint256 wager, address token, , , ) = platform.games(gameId);
        
        assertEq(wager, WAGER_ERC20);
        assertEq(token, address(usdc));
        assertEq(usdc.balanceOf(address(platform)), WAGER_ERC20);
    }

    // ---- Edge Cases ----
    function testFail_JoinWithWrongAmount() public {
        vm.prank(player1);
        platform.createGame{value: WAGER_ETH}(WAGER_ETH, address(0));
        (uint256 gameId, , , ) = _getLastGame();

        vm.prank(player2);
        platform.joinGame{value: WAGER_ETH - 1}(gameId); // Reverts
    }

    function testDisputeFlow() public {
        // Setup game
        vm.prank(player1);
        platform.createGame{value: WAGER_ETH}(WAGER_ETH, address(0));
        (uint256 gameId, , , ) = _getLastGame();
        vm.prank(player2);
        platform.joinGame{value: WAGER_ETH}(gameId);

        // Fast-forward 2 hours + 1 second
        vm.warp(block.timestamp + platform.DISPUTE_TIMEOUT() + 1);

        // Open dispute
        vm.expectEmit(true, true, false, true);
        emit DisputeOpened(gameId, player1);
        vm.prank(player1);
        platform.openDispute(gameId);

        // Admin resolves
        vm.expectEmit(true, true, false, true);
        emit AdminResolution(gameId, player2);
        vm.prank(admin);
        platform.adminResolve(gameId, player2);
    }

    function testReentrancyAttack() public {
        // Setup
        vm.prank(player1);
        platform.createGame{value: WAGER_ETH}(WAGER_ETH, address(0));
        (uint256 gameId, , , ) = _getLastGame();
        vm.prank(player2);
        platform.joinGame{value: WAGER_ETH}(gameId);

        // Attacker tries to reenter during resolution
        ReentrancyAttacker attackerContract = new ReentrancyAttacker(platform);
        vm.prank(address(attackerContract));
        platform.resolveGame(gameId, address(attackerContract), keccak256("malicious"));

        // Verify platform funds intact
        assertEq(address(platform).balance, 0.2 ether); // 10% fee taken
    }

    // ---- Helpers ----
    function _getLastGame() internal view returns (uint256 id, address p1, address p2, uint256 wager) {
        id = platform.nextGameId() - 1;
        (p1, p2, wager, , , , ) = platform.games(id);
    }
}

contract ReentrancyAttacker {
    BaseGamePlatform platform;
    constructor(BaseGamePlatform _platform) {
        platform = _platform;
    }

    function attack(uint256 gameId) external {
        platform.resolveGame(gameId, address(this), keccak256("malicious"));
    }

    receive() external payable {
        // Attempt reentrancy
        platform.resolveGame(0, address(this), keccak256("malicious"));
    }
}