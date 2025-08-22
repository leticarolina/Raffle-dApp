# 🎟️ Web3 Raffle DApp

A decentralized raffle system built with **Solidity, Foundry, and Next.js/React**, integrated with **Chainlink VRF v2.5** and **Chainlink Automation**.  
This project demonstrates a full-stack Web3 workflow: secure smart contract development, robust testing, and frontend integration.

> ⚠️ **Note**: The contract is currently deployed on **Sepolia Testnet**.  

## 📸 Demo and Deployment

- Smart Contract: [0xdB9ED786cAF806b929C52eDC18a350eDAB9ADbfa](https://sepolia.etherscan.io/address/0xdB9ED786cAF806b929C52eDC18a350eDAB9ADbfa)

- [Live Website](https://raffle-d-app.vercel.app/)  

- Raffle UI:  
![Raffle UI Screenshot](/front-end/public/ui.png)  

## 🎲 How It Works

- Players enter the raffle by paying `0.001 ETH` into the contract.
- Every interval of `2 minutes`, Chainlink Automation checks:
  - Is the raffle open and not calculating a winner?
  - Has enough time (2 minutes) passed since the last draw?
  - Are there players and balance?
- If conditions are met, it requests randomness from **Chainlink VRF v2.5**.
- A random winner is selected, prize transferred, players reset, and the raffle reopens.

## 🚀 Features

- **Decentralized Raffle Contract**
  - Players enter the raffle by sending 0.001 ETH
  - Uses **Chainlink VRF** for a fair random winner selection
  - **Chainlink Automation** closes raffle, draws winners, and resets automatically  
  - Gas-optimized Solidity with **custom errors**, `constant` and `immutable` vars  
  - Assumes ETH transfer succeeds with `.call`.

- **Frontend (React + Next.js)**
  - Clean UI for entering raffles and monitoring status
  - Real-time updates (raffle state, player count, time until next draw)
  - Responsive design with real-time updates  

- **Testing & Tooling**
  - Full **Foundry** test suite: unit, integration, and local Anvil tests
  - Integration Tests **Mocked VRFCoordinator + Automation** for local development  
  - Deployment & interaction scripts with `forge script`  
  - Local VRF subscription flow (create, fund, add/remove consumers)

## 🛠️ Tech Stack

- **Smart Contracts**: Solidity (0.8.x) with Foundry  
- **Frontend**: Next.js (App Router) + React + TailwindCSS  
- **Web3 Libraries**: wagmi + viem  
- **Oracles**: Chainlink VRF v2.5, Chainlink Automation  
- **Local Dev/Test**: Anvil (Foundry)  

## 📂 Project Structure

```bash
Raffle-VRF-dApp/
│
├── front-end/                     # React + Next.js frontend
│   └── app/                       # Main frontend components (page.js, UI, etc.)
│
├── raffle-contract/               # Foundry-based smart contracts
│   ├── src/
│   │   └── Raffle.sol             # Core raffle contract
│   │
│   ├── script/                    # Deployment & interaction scripts
│   │   ├── DeployRaffle.s.sol
│   │   ├── HelperConfig.s.sol
│   │   └── Interactions.s.sol
│   │
│   ├── test/                      # Test suite
│   │   ├── integration/
│   │   │   └── Integration.t.sol
│   │   ├── mocks/
│   │   │   ├── TokenToFundVRF.sol
│   │   │   └── WinnerCannotReceiveEth.sol
│   │   ├── unit/
│   │   │   └── RaffleTest.t.sol
│   │   └── utils/
│   │       └── BaseTest.t.sol
│   │
│   └── foundry.toml               # Foundry config
│
└── README.md
```

## ⚙️ Setup & Run

```bash
git clone https://github.com/yourusername/Raffle-VRF-dApp.git

cd raffle-contract
forge build
forge test
```

Frontend (React/Next.js)  

```bash
cd front-end  
npm install  
npm run dev  
```

### Author

[Leticia Azevedo](https://www.letiazevedo.com)
