# DAO Quadratic Voting 🏛️

A fully on-chain Decentralized Autonomous Organization (DAO) governance system implementing Quadratic Voting. Built with Solidity and Foundry, this protocol allows communities to vote on funding and signaling proposals fairly, mitigating the influence of whales through mathematically accurate quadratic vote pricing.

## Features ✨
- Quadratic Voting Engine: The cost of voting increases quadratically (1 vote = 1 token, 2 votes = 4 tokens, 3 votes = 9 tokens), ensuring a more democratic and balanced decision-making process.
- Dynamic Thresholds: Approval thresholds adjust dynamically based on the total budget, active participants, and pending proposals, using exact integer math to prevent precision loss.
- Pull-over-Push Architecture (DoS Protection): Implements the Pull-over-Push design pattern for refunds and signaling proposal execution, making the contract completely immune to Denial of Service (DoS) attacks regardless of the number of participants.
- Custom ERC20 Integration: Uses a dedicated `VotingToken` with strict minting and burning access controls.
- Gas Optimized: 
  * Uses Solidity Custom Errors instead of revert strings.
  * Implements `immutable` variables for one-time configurations.
  * Efficient array manipulation for proposal tracking.

## Prerequisites 📋
- Foundry installed on your system.

## Setup & Installation 🛠️

1. Clone the repository:
   git clone https://github.com/your-username/DAO-Quadratic-Voting.git
   cd DAO-Quadratic-Voting

2. Install dependencies (OpenZeppelin contracts):
   forge install OpenZeppelin/openzeppelin-contracts --no-commit

3. Build the project:
   forge build

## Testing 🧪
Run the Foundry test suite to verify the quadratic math, threshold logic, and DoS protections:
   forge test

To view detailed traces and gas consumption:
   forge test -vvvv

## Smart Contract Architecture 🏗️
- QuadraticVoting.sol: The core governance engine. Manages proposals, quadratic vote staking/withdrawing, and threshold execution.
- VotingToken.sol: The ERC20 token used as the voting currency. Restricted to the voting engine.
- IExecutableProposal.sol: The standard interface that external funding proposals must implement to receive DAO funds and execute logic.

## License 📄
This project is licensed under the MIT License.

