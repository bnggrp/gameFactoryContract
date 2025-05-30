# gameFactoryContract
smart contract for game factory - host multiple instance of multiplayer games 
# Base Game Platform - Smart Contracts

[![Built with Foundry](https://img.shields.io/badge/Built%20with-Foundry-FF6944?logo=ethereum)](https://book.getfoundry.sh/)

A gas-optimized, multi-token gaming platform for Base Mainnet. Supports ETH/ERC20 wagers, dispute resolution, and customizable game logic.

## Features

✅ **Single-Contract Design** - No per-game deployments  
✅ **Native ETH & ERC20 Support** (USDC ready)  
✅ **Dispute Resolution** - Timeout + admin fallback  
✅ **10% Platform Fee** - Configurable recipient  
✅ **Production-Ready** - Reentrancy protection, input validation  

## Contract Architecture

```solidity
src/
├── BaseGamePlatform.sol        // Main contract (all games)
├── interfaces/
│   └── IERC20.sol              // OpenZeppelin interface
└── test/
    └── BaseGamePlatform.t.sol   // Foundry tests