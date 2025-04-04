# 🎰 Decentralized Fortune (dFortune)

A fully transparent, community-driven lottery protocol built on Ethereum Virtual Machine (EVM) chains, leveraging Solidity smart contracts and Foundry for trustless, verifiable fairness.

## 🌟 Overview
dFortune redefines lotteries with Web3-native features:
- **Provably fair draws** via Chainlink VRF
- **NFT-based tickets** with collectible traits
- **DAO governance** powered by $FORT tokens
- **Cross-chain accessibility** (Ethereum + Polygon)
- **Lossless mechanics** to reward loyal players

## 🚀 Features

### Smart Contracts (Solidity)
1. **NFT Tickets (ERC-721)**
   - Each ticket is a unique NFT with metadata (rarity, draw ID, owner history)
   - "Golden Ticket" trait grants lifetime discounts
2. **Provable Randomness**
   - Integrated Chainlink VRF for tamper-proof draws
   - On-chain verification of randomness proofs
3. **Dynamic Prize Pool**
   - 70% to grand winner, 20% to secondary prizes, 10% to DAO treasury
   - Unclaimed prizes generate yield via Aave/Compound integration
4. **DAO Governance**
   - $FORT token holders vote on:
     - Ticket price adjustments
     - Prize distribution ratios
     - Charity donations (5% of proceeds)
5. **Lossless Mechanics**
   - Players receive 10% refund in $FORT tokens after 10 consecutive losses
   - Loyalty tiers with escalating rewards

### Tech Stack
- **Smart Contracts**: Solidity (0.8.18+)
- **Development Framework**: Foundry (Forge, Cast, Anvil)
- **Oracles**: Chainlink VRF v2
- **NFT Standard**: ERC-721 (OpenZeppelin)
- **Frontend**: Next.js + Wagmi + RainbowKit

## 📜 Smart Contracts

### Core Contracts
1. **TicketNFT.sol** - ERC-721 ticket minting/management
2. **PrizePool.sol** - Prize distribution and yield strategies
3. **dFortuneDAO.sol** - Governance with Snapshot integration
4. **Randomness.sol** - Chainlink VRF coordinator
5. **FORT.sol** - ERC-20 governance token

## ⚙️ Installation

```bash
# Clone repo
git clone https://github.com/your-username/dFortune.git
cd dFortune

# Install Foundry (if not installed)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install dependencies
forge install

# Configure environment
cp .env.example .env
# Add your INFURA_API_KEY, PRIVATE_KEY, etc.