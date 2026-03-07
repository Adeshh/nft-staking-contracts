// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IStaking {
    struct StakeInfo {
        address owner;
        uint64 stakedAt;
        uint128 accruedRewards;
    }

    event Staked(address indexed user, uint256 indexed tokenId);
    event Unstaked(address indexed user, uint256 indexed tokenId, uint256 rewards);
    event RewardsClaimed(address indexed user, uint256 indexed tokenId, uint256 rewards);
    event RewardRateUpdated(uint128 oldRate, uint128 newRate);

    function stake(uint256 tokenId) external;
    function unstake(uint256 tokenId) external;
    function claimRewards(uint256 tokenId) external;
    function pendingRewards(uint256 tokenId) external view returns (uint256);
}
