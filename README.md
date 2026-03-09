# NFT Staking Contracts

Two staking models for ERC-721 NFTs in one repo — hard staking (custody-based) and soft staking (non-custodial) — built with Foundry and Solidity 0.8.24.

## Hard vs Soft Staking

| | Hard Staking | Soft Staking |
|---|---|---|
| NFT custody | Transfers to contract | Stays in your wallet |
| Ownership verification | Implicit — contract holds it | `ownerOf()` checked on every action |
| NFT usability while staked | Not accessible | Still in your wallet |
| Risk | Can't use NFT elsewhere | NFT can be sold mid-stake |
| Reward claim | Always pays full rewards | Reverts with `OwnershipLost` if transferred |
| Unstake if NFT sold | N/A | Succeeds, pays only checkpointed rewards |

## Architecture

```
nft-staking-contracts/
├── src/
│   ├── interfaces/
│   │   └── IStaking.sol        # Shared interface: StakeInfo struct, events, function sigs
│   ├── HardStaking.sol         # Custody-based staking
│   ├── SoftStaking.sol         # Non-custodial staking
│   ├── RewardToken.sol         # ERC-20 reward token with minter role
│   └── MockNFT.sol             # Bare ERC-721 for testing
└── test/
    ├── HardStaking.t.sol
    └── SoftStaking.t.sol
```

## Design Decisions

**Checks-Effects-Interactions** — State is always updated before any external calls (NFT transfers, token mints). Prevents reentrancy at the logic level in addition to the guard.

**ReentrancyGuard** on all state-mutating functions that touch external contracts (`stake`, `unstake`, `claimRewards`, `checkpoint`).

**Custom errors** (`NotTokenOwner`, `TokenNotStaked`, `OwnershipLost`, etc.) instead of require strings. Lower gas at revert time, better ABI encoding for callers.

**Batch operations with `MAX_BATCH_SIZE = 20`** — Stake or unstake up to 20 NFTs in one transaction. The cap prevents unbounded loops that could exceed the block gas limit.

**Struct packing** — `StakeInfo` uses `uint64` for `stakedAt` (valid until year 584,542,046) and `uint128` for `accruedRewards`, so the entire struct fits in two storage slots alongside the `address owner`.

**`checkpoint()` in SoftStaking** — Lets a staker lock in earned rewards into `accruedRewards` before transferring their NFT. Without this, any rewards accrued since the last checkpoint are lost when ownership changes.

**`try/catch` in `_stillOwnsNFT`** — Handles burned or non-standard NFTs gracefully. A burned token would cause `ownerOf()` to revert, which we catch and treat as ownership lost.

**Per-second reward rate** — Simple, predictable math: `rewards = (block.timestamp - stakedAt) * rewardRate`. No complex epoch or snapshot logic.

**Minter role on RewardToken** — Staking contracts are granted minter permission via `setMinter()`. The reward token itself has no fixed supply cap, allowing any number of staking contracts to mint independently.

## Usage

```bash
# Install dependencies
forge install

# Build
forge build

# Run all tests
forge test -vvv

# Gas report
forge test --gas-report

# Run specific contract tests
forge test --match-contract HardStakingTest
forge test --match-contract SoftStakingTest

# Run a specific test
forge test --match-test test_stake_transfersNFTToContract
```
