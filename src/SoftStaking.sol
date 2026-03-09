// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IStaking.sol";
import "./RewardToken.sol";

// non-custodial staking — NFT stays in wallet, ownership re-verified on every action
contract SoftStaking is IStaking, ReentrancyGuard, Ownable {
    error NotTokenOwner();
    error TokenNotStaked();
    error AlreadyStaked();
    error OwnershipLost();
    error ZeroRewardRate();

    IERC721 public immutable nftContract;
    RewardToken public immutable rewardToken;

    uint128 public rewardRate;

    mapping(uint256 => StakeInfo) public stakes;
    mapping(address => uint256[]) private _userStakedTokens;

    constructor(address _nftContract, address _rewardToken, uint128 _rewardRate) Ownable(msg.sender) {
        if (_rewardRate == 0) revert ZeroRewardRate();
        nftContract = IERC721(_nftContract);
        rewardToken = RewardToken(_rewardToken);
        rewardRate = _rewardRate;
    }

    // no transferFrom — just records who staked and when

    function stake(uint256 tokenId) external nonReentrant {
        if (nftContract.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        if (stakes[tokenId].owner != address(0)) revert AlreadyStaked();

        stakes[tokenId] = StakeInfo({owner: msg.sender, stakedAt: uint64(block.timestamp), accruedRewards: 0});
        _userStakedTokens[msg.sender].push(tokenId);

        emit Staked(msg.sender, tokenId);
    }

    // unstaking

    // pays only checkpointed rewards if NFT was transferred away
    function unstake(uint256 tokenId) external nonReentrant {
        StakeInfo memory info = stakes[tokenId];
        if (info.owner != msg.sender) revert TokenNotStaked();

        uint256 rewards;
        if (_stillOwnsNFT(msg.sender, tokenId)) {
            rewards = _calculateRewards(info);
        } else {
            rewards = uint256(info.accruedRewards);
        }

        delete stakes[tokenId];
        _removeFromUserTokens(msg.sender, tokenId);

        if (rewards > 0) rewardToken.mint(msg.sender, rewards);
        emit Unstaked(msg.sender, tokenId, rewards);
    }

    // rewards

    function claimRewards(uint256 tokenId) external nonReentrant {
        StakeInfo storage info = stakes[tokenId];
        if (info.owner != msg.sender) revert TokenNotStaked();
        if (!_stillOwnsNFT(msg.sender, tokenId)) revert OwnershipLost();

        uint256 rewards = _calculateRewards(info);
        info.accruedRewards = 0;
        info.stakedAt = uint64(block.timestamp);

        if (rewards > 0) rewardToken.mint(msg.sender, rewards);
        emit RewardsClaimed(msg.sender, tokenId, rewards);
    }

    function pendingRewards(uint256 tokenId) external view returns (uint256) {
        StakeInfo memory info = stakes[tokenId];
        if (info.owner == address(0)) return 0;
        if (!_stillOwnsNFT(info.owner, tokenId)) return uint256(info.accruedRewards);
        return _calculateRewards(info);
    }

    // lock in accrued rewards before transferring the NFT

    function checkpoint(uint256 tokenId) external nonReentrant {
        StakeInfo storage info = stakes[tokenId];
        if (info.owner != msg.sender) revert TokenNotStaked();
        if (!_stillOwnsNFT(msg.sender, tokenId)) revert OwnershipLost();

        uint256 earned = (block.timestamp - uint256(info.stakedAt)) * uint256(rewardRate);
        info.accruedRewards += uint128(earned);
        info.stakedAt = uint64(block.timestamp);
    }

    function isValidStake(uint256 tokenId) external view returns (bool) {
        StakeInfo memory info = stakes[tokenId];
        if (info.owner == address(0)) return false;
        return _stillOwnsNFT(info.owner, tokenId);
    }

    function getStakedTokens(address user) external view returns (uint256[] memory) {
        return _userStakedTokens[user];
    }

    // admin

    function setRewardRate(uint128 newRate) external onlyOwner {
        if (newRate == 0) revert ZeroRewardRate();
        emit RewardRateUpdated(rewardRate, newRate);
        rewardRate = newRate;
    }

    function _stillOwnsNFT(address user, uint256 tokenId) internal view returns (bool) {
        try nftContract.ownerOf(tokenId) returns (address currentOwner) {
            return currentOwner == user;
        } catch {
            return false;
        }
    }

    function _calculateRewards(StakeInfo memory info) internal view returns (uint256) {
        return uint256(info.accruedRewards) + (block.timestamp - uint256(info.stakedAt)) * uint256(rewardRate);
    }

    function _removeFromUserTokens(address user, uint256 tokenId) internal {
        uint256[] storage tokens = _userStakedTokens[user];
        uint256 len = tokens.length;
        for (uint256 i = 0; i < len; i++) {
            if (tokens[i] == tokenId) {
                tokens[i] = tokens[len - 1];
                tokens.pop();
                return;
            }
        }
    }
}
