# NFT Staking Contracts

Hard staking and soft staking for ERC-721 NFTs. Built with Foundry, Solidity 0.8.24, OpenZeppelin v5.

## Hard vs Soft

| | Hard Staking | Soft Staking |
|---|---|---|
| NFT custody | Transfers to contract | Stays in your wallet |
| Ownership check | Implicit | `ownerOf()` on every action |
| Claim if NFT sold | N/A | Reverts with `OwnershipLost` |
| Unstake if NFT sold | N/A | Succeeds, pays checkpointed rewards only |

## Structure

```
src/
  interfaces/IStaking.sol   — shared interface, StakeInfo struct, events
  HardStaking.sol           — custody-based staking
  SoftStaking.sol           — non-custodial staking
  RewardToken.sol           — ERC-20 reward token, minter role
  MockNFT.sol               — test ERC-721
test/
  HardStaking.t.sol
  SoftStaking.t.sol
```

See [PATTERNS.md](PATTERNS.md) for design decisions and optimisation notes.

## Usage

```bash
forge build
forge test -vvv
forge test --gas-report
forge test --match-contract HardStakingTest
forge test --match-contract SoftStakingTest
```
