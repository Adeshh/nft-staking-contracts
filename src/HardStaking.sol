// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IStaking.sol";
import "./RewardToken.sol";

// NFT transfers into contract on stake and back on unstake; rewards accrue per second
contract HardStaking is IStaking, IERC721Receiver, ReentrancyGuard, Ownable {
    error NotTokenOwner();
    error TokenNotStaked();
    error ZeroRewardRate();
    error BatchTooLarge();
    error EmptyBatch();

    uint256 public constant MAX_BATCH_SIZE = 20;

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

    // staking

    function stake(uint256 tokenId) external nonReentrant {
        // checks
        if (nftContract.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();

        // effects
        stakes[tokenId] = StakeInfo({owner: msg.sender, stakedAt: uint64(block.timestamp), accruedRewards: 0});
        _userStakedTokens[msg.sender].push(tokenId);

        // interactions
        nftContract.transferFrom(msg.sender, address(this), tokenId);
        emit Staked(msg.sender, tokenId);
    }

    function stakeBatch(uint256[] calldata tokenIds) external nonReentrant {
        uint256 len = tokenIds.length;
        // checks
        if (len == 0) revert EmptyBatch();
        if (len > MAX_BATCH_SIZE) revert BatchTooLarge();

        uint256[] storage userTokens = _userStakedTokens[msg.sender];
        for (uint256 i = 0; i < len; ) {
            uint256 tokenId = tokenIds[i];
            // checks
            if (nftContract.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();

            // effects
            stakes[tokenId] = StakeInfo({owner: msg.sender, stakedAt: uint64(block.timestamp), accruedRewards: 0});
            userTokens.push(tokenId);

            // interactions
            nftContract.transferFrom(msg.sender, address(this), tokenId);
            emit Staked(msg.sender, tokenId);
            unchecked { ++i; }
        }
    }

    // unstaking

    function unstake(uint256 tokenId) external nonReentrant {
        // checks
        StakeInfo memory info = stakes[tokenId];
        if (info.owner != msg.sender) revert TokenNotStaked();
        uint256 rewards = _calculateRewards(info);

        // effects
        delete stakes[tokenId];
        _removeFromUserTokens(msg.sender, tokenId);

        // interactions
        nftContract.transferFrom(address(this), msg.sender, tokenId);
        if (rewards > 0) rewardToken.mint(msg.sender, rewards);
        emit Unstaked(msg.sender, tokenId, rewards);
    }

    function unstakeBatch(uint256[] calldata tokenIds) external nonReentrant {
        uint256 len = tokenIds.length;
        // checks
        if (len == 0) revert EmptyBatch();
        if (len > MAX_BATCH_SIZE) revert BatchTooLarge();

        for (uint256 i = 0; i < len; ) {
            uint256 tokenId = tokenIds[i];
            // checks
            StakeInfo memory info = stakes[tokenId];
            if (info.owner != msg.sender) revert TokenNotStaked();
            uint256 rewards = _calculateRewards(info);

            // effects
            delete stakes[tokenId];
            _removeFromUserTokens(msg.sender, tokenId);

            // interactions
            nftContract.transferFrom(address(this), msg.sender, tokenId);
            if (rewards > 0) rewardToken.mint(msg.sender, rewards);
            emit Unstaked(msg.sender, tokenId, rewards);
            unchecked { ++i; }
        }
    }

    // rewards

    function claimRewards(uint256 tokenId) external nonReentrant {
        // checks
        StakeInfo storage info = stakes[tokenId];
        if (info.owner != msg.sender) revert TokenNotStaked();
        uint256 rewards = _calculateRewards(info);

        // effects
        info.accruedRewards = 0;
        info.stakedAt = uint64(block.timestamp);

        // interactions
        if (rewards > 0) rewardToken.mint(msg.sender, rewards);
        emit RewardsClaimed(msg.sender, tokenId, rewards);
    }

    function pendingRewards(uint256 tokenId) external view returns (uint256) {
        StakeInfo memory info = stakes[tokenId];
        if (info.owner == address(0)) return 0;
        return _calculateRewards(info);
    }

    // views

    function getStakedTokens(address user) external view returns (uint256[] memory) {
        return _userStakedTokens[user];
    }

    // admin

    function setRewardRate(uint128 newRate) external onlyOwner {
        // checks
        if (newRate == 0) revert ZeroRewardRate();

        // effects
        emit RewardRateUpdated(rewardRate, newRate);
        rewardRate = newRate;
    }

    // erc721 receiver

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function _calculateRewards(StakeInfo memory info) internal view returns (uint256) {
        return uint256(info.accruedRewards) + (block.timestamp - uint256(info.stakedAt)) * uint256(rewardRate);
    }

    function _removeFromUserTokens(address user, uint256 tokenId) internal {
        uint256[] storage tokens = _userStakedTokens[user];
        uint256 len = tokens.length;
        for (uint256 i = 0; i < len; ) {
            if (tokens[i] == tokenId) {
                tokens[i] = tokens[len - 1];
                tokens.pop();
                return;
            }
            unchecked { ++i; }
        }
    }
}
