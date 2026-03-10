# Optimisations & Design Patterns

Notes on key decisions made while building this.

---

## Storage layout

`StakeInfo` packs into two 32-byte slots:
- slot 1: `owner` (20 bytes) + `stakedAt` (8 bytes) — 28 bytes, 4 spare
- slot 2: `accruedRewards` (16 bytes)

`uint64` for timestamps is safe until year 584,542,046. `uint128` for reward balances — no realistic overflow given any sane reward rate.

## Custom errors

`revert CustomError()` is cheaper than `require(condition, "string")` — error selectors are 4 bytes vs ABI-encoding a string. Also cleaner to decode on the frontend.

## Batch ops

`MAX_BATCH_SIZE = 20` caps the loop to keep gas predictable and well under block limits. Loop bodies cache `tokenIds.length` once and use `unchecked { ++i }` since the index can never overflow with a 20-item cap.

In `stakeBatch`, `_userStakedTokens[msg.sender]` is pulled into a local storage reference so the slot lookup doesn't repeat on every iteration.

## Checks-Effects-Interactions

State is always written before any external call. `ReentrancyGuard` is an extra belt-and-suspenders on top — not a substitute for CEI, just an additional layer.

## transferFrom vs safeTransferFrom on unstake

On returning the NFT to the user, `transferFrom` is used instead of `safeTransferFrom`. `safeTransferFrom` invokes `onERC721Received` on the recipient, which opens a reentrancy vector if the recipient is a contract. CEI + guard already make this safe, but `transferFrom` keeps it simpler and avoids an unnecessary external call.

## SoftStaking — ownership check

`_stillOwnsNFT` wraps `ownerOf()` in a `try/catch`. A burned token reverts on `ownerOf`, which would otherwise permanently brick the user's stake record. The catch treats it as ownership lost, allowing the staker to still call `unstake()` and clean up (they get 0 rewards since no checkpoint was done).

## checkpoint()

Without it, rewards earned between the last claim and an NFT transfer are silently forfeited. `checkpoint()` lets the user snapshot those rewards into `accruedRewards` before transferring. On `unstake()`, only `accruedRewards` is paid out if ownership has changed.

## Per-second rewards

`rewards = (block.timestamp - stakedAt) * rewardRate` — no epochs, no snapshots. Validators can shift `block.timestamp` by ~15 seconds, which is negligible at any reasonable reward rate.

## Security notes

- No unbounded loops anywhere — all user-token arrays are bounded by `MAX_BATCH_SIZE` on write and the full array only iterated in `_removeFromUserTokens` which is O(n) on the user's staked count.
- `uint128(earned)` cast in `SoftStaking.checkpoint()` is safe in practice — overflowing it would require accumulating rewards continuously for billions of years at a 1 token/sec rate.
- RewardToken has no supply cap by design — reward emission is naturally bounded by real time elapsed and the rate set by the owner.
