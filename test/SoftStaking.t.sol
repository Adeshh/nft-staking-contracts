// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/SoftStaking.sol";
import "../src/RewardToken.sol";
import "../src/MockNFT.sol";

contract SoftStakingTest is Test {
    SoftStaking staking;
    RewardToken rewardToken;
    MockNFT nft;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint128 constant REWARD_RATE = 1e18;

    function setUp() public {
        nft = new MockNFT();
        rewardToken = new RewardToken();
        staking = new SoftStaking(address(nft), address(rewardToken), REWARD_RATE);
        rewardToken.setMinter(address(staking), true);
    }

    // -------------------------------------------------------------------------
    // stake
    // -------------------------------------------------------------------------

    function test_stake_nftRemainsInWallet() public {
        uint256 tokenId = nft.mint(alice);
        vm.prank(alice);
        staking.stake(tokenId);
        // NFT must stay with alice, NOT transferred to contract
        assertEq(nft.ownerOf(tokenId), alice);
    }

    function test_stake_recordsStakeInfo() public {
        uint256 tokenId = nft.mint(alice);
        uint256 ts = block.timestamp;
        vm.prank(alice);
        staking.stake(tokenId);

        (address owner, uint64 stakedAt, uint128 accrued) = staking.stakes(tokenId);
        assertEq(owner, alice);
        assertEq(stakedAt, ts);
        assertEq(accrued, 0);
    }

    function test_stake_addsToUserList() public {
        uint256 tokenId = nft.mint(alice);
        vm.prank(alice);
        staking.stake(tokenId);

        uint256[] memory tokens = staking.getStakedTokens(alice);
        assertEq(tokens.length, 1);
        assertEq(tokens[0], tokenId);
    }

    function test_stake_emitsStakedEvent() public {
        uint256 tokenId = nft.mint(alice);
        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit IStaking.Staked(alice, tokenId);
        staking.stake(tokenId);
    }

    function test_stake_revertsIfNotOwner() public {
        uint256 tokenId = nft.mint(alice);
        vm.prank(bob);
        vm.expectRevert(SoftStaking.NotTokenOwner.selector);
        staking.stake(tokenId);
    }

    function test_stake_revertsIfAlreadyStaked() public {
        uint256 tokenId = nft.mint(alice);
        vm.startPrank(alice);
        staking.stake(tokenId);
        vm.expectRevert(SoftStaking.AlreadyStaked.selector);
        staking.stake(tokenId);
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // unstake
    // -------------------------------------------------------------------------

    function test_unstake_paysFullRewardsIfStillOwned() public {
        uint256 tokenId = _stakeForAlice();
        vm.warp(block.timestamp + 100);
        vm.prank(alice);
        staking.unstake(tokenId);
        assertEq(rewardToken.balanceOf(alice), 100 * uint256(REWARD_RATE));
    }

    function test_unstake_paysZeroIfOwnershipLost() public {
        uint256 tokenId = _stakeForAlice();
        vm.warp(block.timestamp + 100);
        // Alice sells NFT to Bob
        vm.prank(alice);
        nft.transferFrom(alice, bob, tokenId);

        vm.prank(alice);
        staking.unstake(tokenId);
        assertEq(rewardToken.balanceOf(alice), 0);
    }

    function test_unstake_paysCheckpointedRewardsIfOwnershipLost() public {
        uint256 tokenId = _stakeForAlice();
        vm.warp(block.timestamp + 100);

        // Checkpoint before transferring
        vm.prank(alice);
        staking.checkpoint(tokenId);

        vm.prank(alice);
        nft.transferFrom(alice, bob, tokenId);

        vm.prank(alice);
        staking.unstake(tokenId);
        assertEq(rewardToken.balanceOf(alice), 100 * uint256(REWARD_RATE));
    }

    function test_unstake_emitsEvent() public {
        uint256 tokenId = _stakeForAlice();
        vm.warp(block.timestamp + 10);
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit IStaking.Unstaked(alice, tokenId, 10 * uint256(REWARD_RATE));
        staking.unstake(tokenId);
    }

    function test_unstake_clearsStakeInfo() public {
        uint256 tokenId = _stakeForAlice();
        vm.prank(alice);
        staking.unstake(tokenId);
        (address owner,,) = staking.stakes(tokenId);
        assertEq(owner, address(0));
    }

    function test_unstake_removesFromUserList() public {
        uint256 tokenId = _stakeForAlice();
        vm.prank(alice);
        staking.unstake(tokenId);
        assertEq(staking.getStakedTokens(alice).length, 0);
    }

    function test_unstake_revertsIfNotStaker() public {
        uint256 tokenId = _stakeForAlice();
        vm.prank(bob);
        vm.expectRevert(SoftStaking.TokenNotStaked.selector);
        staking.unstake(tokenId);
    }

    // -------------------------------------------------------------------------
    // claimRewards
    // -------------------------------------------------------------------------

    function test_claimRewards_paysIfOwner() public {
        uint256 tokenId = _stakeForAlice();
        vm.warp(block.timestamp + 100);
        vm.prank(alice);
        staking.claimRewards(tokenId);
        assertEq(rewardToken.balanceOf(alice), 100 * uint256(REWARD_RATE));
    }

    function test_claimRewards_revertsIfOwnershipLost() public {
        uint256 tokenId = _stakeForAlice();
        vm.prank(alice);
        nft.transferFrom(alice, bob, tokenId);
        vm.prank(alice);
        vm.expectRevert(SoftStaking.OwnershipLost.selector);
        staking.claimRewards(tokenId);
    }

    function test_claimRewards_resetsTimer() public {
        uint256 tokenId = _stakeForAlice();
        vm.warp(block.timestamp + 100);
        vm.prank(alice);
        staking.claimRewards(tokenId);
        assertEq(staking.pendingRewards(tokenId), 0);
    }

    // -------------------------------------------------------------------------
    // pendingRewards
    // -------------------------------------------------------------------------

    function test_pendingRewards_correctCalculation() public {
        uint256 tokenId = _stakeForAlice();
        vm.warp(block.timestamp + 200);
        assertEq(staking.pendingRewards(tokenId), 200 * uint256(REWARD_RATE));
    }

    function test_pendingRewards_returnsOnlyCheckpointedIfOwnershipLost() public {
        uint256 tokenId = _stakeForAlice();
        vm.warp(block.timestamp + 100);
        vm.prank(alice);
        staking.checkpoint(tokenId);

        vm.prank(alice);
        nft.transferFrom(alice, bob, tokenId);

        assertEq(staking.pendingRewards(tokenId), 100 * uint256(REWARD_RATE));
    }

    function test_pendingRewards_returnsZeroIfNotStaked() public {
        assertEq(staking.pendingRewards(999), 0);
    }

    // -------------------------------------------------------------------------
    // checkpoint
    // -------------------------------------------------------------------------

    function test_checkpoint_locksInAccruedRewards() public {
        uint256 tokenId = _stakeForAlice();
        vm.warp(block.timestamp + 100);
        vm.prank(alice);
        staking.checkpoint(tokenId);

        (, , uint128 accrued) = staking.stakes(tokenId);
        assertEq(accrued, 100 * uint256(REWARD_RATE));
    }

    function test_checkpoint_resetsTimer() public {
        uint256 tokenId = _stakeForAlice();
        vm.warp(block.timestamp + 100);
        vm.prank(alice);
        staking.checkpoint(tokenId);

        // Right after checkpoint, pending == checkpointed amount (no new time elapsed)
        assertEq(staking.pendingRewards(tokenId), 100 * uint256(REWARD_RATE));

        // Additional time accrues on top
        vm.warp(block.timestamp + 50);
        assertEq(staking.pendingRewards(tokenId), 150 * uint256(REWARD_RATE));
    }

    function test_checkpoint_revertsIfOwnershipLost() public {
        uint256 tokenId = _stakeForAlice();
        vm.prank(alice);
        nft.transferFrom(alice, bob, tokenId);
        vm.prank(alice);
        vm.expectRevert(SoftStaking.OwnershipLost.selector);
        staking.checkpoint(tokenId);
    }

    // -------------------------------------------------------------------------
    // isValidStake
    // -------------------------------------------------------------------------

    function test_isValidStake_trueIfOwned() public {
        uint256 tokenId = _stakeForAlice();
        assertTrue(staking.isValidStake(tokenId));
    }

    function test_isValidStake_falseIfTransferred() public {
        uint256 tokenId = _stakeForAlice();
        vm.prank(alice);
        nft.transferFrom(alice, bob, tokenId);
        assertFalse(staking.isValidStake(tokenId));
    }

    function test_isValidStake_falseIfNotStaked() public {
        assertFalse(staking.isValidStake(999));
    }

    // -------------------------------------------------------------------------
    // constructor
    // -------------------------------------------------------------------------

    function test_constructor_revertsOnZeroRate() public {
        vm.expectRevert(SoftStaking.ZeroRewardRate.selector);
        new SoftStaking(address(nft), address(rewardToken), 0);
    }

    // -------------------------------------------------------------------------
    // setRewardRate
    // -------------------------------------------------------------------------

    function test_setRewardRate_updatesRate() public {
        staking.setRewardRate(2e18);
        assertEq(staking.rewardRate(), 2e18);
    }

    function test_setRewardRate_emitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit IStaking.RewardRateUpdated(REWARD_RATE, 2e18);
        staking.setRewardRate(2e18);
    }

    function test_setRewardRate_revertsOnZero() public {
        vm.expectRevert(SoftStaking.ZeroRewardRate.selector);
        staking.setRewardRate(0);
    }

    function test_setRewardRate_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        staking.setRewardRate(2e18);
    }

    // -------------------------------------------------------------------------
    // Edge cases
    // -------------------------------------------------------------------------

    function test_restakeAfterUnstake() public {
        uint256 tokenId = _stakeForAlice();
        vm.prank(alice);
        staking.unstake(tokenId);

        // Can stake the same token again
        vm.prank(alice);
        staking.stake(tokenId);
        (address owner,,) = staking.stakes(tokenId);
        assertEq(owner, alice);
    }

    function test_multipleNFTs_sameUser() public {
        uint256 token1 = nft.mint(alice);
        uint256 token2 = nft.mint(alice);

        vm.startPrank(alice);
        staking.stake(token1);
        staking.stake(token2);
        vm.stopPrank();

        vm.warp(block.timestamp + 100);

        assertEq(staking.pendingRewards(token1), 100 * uint256(REWARD_RATE));
        assertEq(staking.pendingRewards(token2), 100 * uint256(REWARD_RATE));
    }

    function test_multiUser_independentRewardAccrual() public {
        uint256 aliceToken = nft.mint(alice);
        uint256 bobToken = nft.mint(bob);

        vm.prank(alice);
        staking.stake(aliceToken);

        vm.warp(block.timestamp + 50);

        vm.prank(bob);
        staking.stake(bobToken);

        vm.warp(block.timestamp + 100);

        assertEq(staking.pendingRewards(aliceToken), 150 * uint256(REWARD_RATE));
        assertEq(staking.pendingRewards(bobToken), 100 * uint256(REWARD_RATE));
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    function _stakeForAlice() internal returns (uint256 tokenId) {
        tokenId = nft.mint(alice);
        vm.prank(alice);
        staking.stake(tokenId);
    }
}
