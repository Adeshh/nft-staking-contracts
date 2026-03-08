// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/HardStaking.sol";
import "../src/RewardToken.sol";
import "../src/MockNFT.sol";

contract HardStakingTest is Test {
    HardStaking staking;
    RewardToken rewardToken;
    MockNFT nft;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint128 constant REWARD_RATE = 1e18; // 1 token per second

    function setUp() public {
        nft = new MockNFT();
        rewardToken = new RewardToken();
        staking = new HardStaking(address(nft), address(rewardToken), REWARD_RATE);
        rewardToken.setMinter(address(staking), true);
    }

    // -------------------------------------------------------------------------
    // stake
    // -------------------------------------------------------------------------

    function test_stake_transfersNFTToContract() public {
        uint256 tokenId = _mintAndApprove(alice);
        vm.prank(alice);
        staking.stake(tokenId);
        assertEq(nft.ownerOf(tokenId), address(staking));
    }

    function test_stake_recordsStakeInfo() public {
        uint256 tokenId = _mintAndApprove(alice);
        uint256 ts = block.timestamp;
        vm.prank(alice);
        staking.stake(tokenId);

        (address owner, uint64 stakedAt, uint128 accrued) = staking.stakes(tokenId);
        assertEq(owner, alice);
        assertEq(stakedAt, ts);
        assertEq(accrued, 0);
    }

    function test_stake_addsToUserList() public {
        uint256 tokenId = _mintAndApprove(alice);
        vm.prank(alice);
        staking.stake(tokenId);

        uint256[] memory tokens = staking.getStakedTokens(alice);
        assertEq(tokens.length, 1);
        assertEq(tokens[0], tokenId);
    }

    function test_stake_emitsStakedEvent() public {
        uint256 tokenId = _mintAndApprove(alice);
        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit IStaking.Staked(alice, tokenId);
        staking.stake(tokenId);
    }

    function test_stake_revertsIfNotOwner() public {
        uint256 tokenId = nft.mint(alice);
        vm.prank(bob);
        vm.expectRevert(HardStaking.NotTokenOwner.selector);
        staking.stake(tokenId);
    }

    // -------------------------------------------------------------------------
    // stakeBatch
    // -------------------------------------------------------------------------

    function test_stakeBatch_stakesMultiple() public {
        nft.mintBatch(alice, 3);
        uint256[] memory ids = new uint256[](3);
        ids[0] = 0;
        ids[1] = 1;
        ids[2] = 2;

        vm.startPrank(alice);
        nft.setApprovalForAll(address(staking), true);
        staking.stakeBatch(ids);
        vm.stopPrank();

        assertEq(staking.getStakedTokens(alice).length, 3);
    }

    function test_stakeBatch_revertsOnEmpty() public {
        uint256[] memory ids = new uint256[](0);
        vm.prank(alice);
        vm.expectRevert(HardStaking.EmptyBatch.selector);
        staking.stakeBatch(ids);
    }

    function test_stakeBatch_revertsIfTooLarge() public {
        nft.mintBatch(alice, 21);
        uint256[] memory ids = new uint256[](21);
        for (uint256 i = 0; i < 21; i++) ids[i] = i;

        vm.startPrank(alice);
        nft.setApprovalForAll(address(staking), true);
        vm.expectRevert(HardStaking.BatchTooLarge.selector);
        staking.stakeBatch(ids);
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // unstake
    // -------------------------------------------------------------------------

    function test_unstake_returnsNFTToOwner() public {
        uint256 tokenId = _stakeForAlice();
        vm.prank(alice);
        staking.unstake(tokenId);
        assertEq(nft.ownerOf(tokenId), alice);
    }

    function test_unstake_paysAccruedRewards() public {
        uint256 tokenId = _stakeForAlice();
        vm.warp(block.timestamp + 100);
        vm.prank(alice);
        staking.unstake(tokenId);
        assertEq(rewardToken.balanceOf(alice), 100 * uint256(REWARD_RATE));
    }

    function test_unstake_clearsStakeInfo() public {
        uint256 tokenId = _stakeForAlice();
        vm.prank(alice);
        staking.unstake(tokenId);
        (address owner,,) = staking.stakes(tokenId);
        assertEq(owner, address(0));
    }

    function test_unstake_emitsUnstakedEvent() public {
        uint256 tokenId = _stakeForAlice();
        vm.warp(block.timestamp + 10);
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit IStaking.Unstaked(alice, tokenId, 10 * uint256(REWARD_RATE));
        staking.unstake(tokenId);
    }

    function test_unstake_removesFromUserList() public {
        uint256 tokenId = _stakeForAlice();
        vm.prank(alice);
        staking.unstake(tokenId);
        assertEq(staking.getStakedTokens(alice).length, 0);
    }

    function test_unstake_revertsIfWrongCaller() public {
        uint256 tokenId = _stakeForAlice();
        vm.prank(bob);
        vm.expectRevert(HardStaking.TokenNotStaked.selector);
        staking.unstake(tokenId);
    }

    function test_unstake_revertsIfNotStaked() public {
        vm.prank(alice);
        vm.expectRevert(HardStaking.TokenNotStaked.selector);
        staking.unstake(999);
    }

    // -------------------------------------------------------------------------
    // unstakeBatch
    // -------------------------------------------------------------------------

    function test_unstakeBatch_returnsAllNFTs() public {
        nft.mintBatch(alice, 3);
        uint256[] memory ids = new uint256[](3);
        ids[0] = 0;
        ids[1] = 1;
        ids[2] = 2;

        vm.startPrank(alice);
        nft.setApprovalForAll(address(staking), true);
        staking.stakeBatch(ids);
        vm.warp(block.timestamp + 100);
        staking.unstakeBatch(ids);
        vm.stopPrank();

        for (uint256 i = 0; i < 3; i++) {
            assertEq(nft.ownerOf(i), alice);
        }
    }

    function test_unstakeBatch_revertsOnEmpty() public {
        uint256[] memory ids = new uint256[](0);
        vm.prank(alice);
        vm.expectRevert(HardStaking.EmptyBatch.selector);
        staking.unstakeBatch(ids);
    }

    // -------------------------------------------------------------------------
    // claimRewards
    // -------------------------------------------------------------------------

    function test_claimRewards_paysWithoutUnstaking() public {
        uint256 tokenId = _stakeForAlice();
        vm.warp(block.timestamp + 100);
        vm.prank(alice);
        staking.claimRewards(tokenId);

        assertEq(rewardToken.balanceOf(alice), 100 * uint256(REWARD_RATE));
        assertEq(nft.ownerOf(tokenId), address(staking));
    }

    function test_claimRewards_resetsAccrualTimer() public {
        uint256 tokenId = _stakeForAlice();
        vm.warp(block.timestamp + 100);
        vm.prank(alice);
        staking.claimRewards(tokenId);

        assertEq(staking.pendingRewards(tokenId), 0);
    }

    function test_claimRewards_emitsEvent() public {
        uint256 tokenId = _stakeForAlice();
        vm.warp(block.timestamp + 50);
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit IStaking.RewardsClaimed(alice, tokenId, 50 * uint256(REWARD_RATE));
        staking.claimRewards(tokenId);
    }

    function test_claimRewards_revertsIfNotStaker() public {
        uint256 tokenId = _stakeForAlice();
        vm.prank(bob);
        vm.expectRevert(HardStaking.TokenNotStaked.selector);
        staking.claimRewards(tokenId);
    }

    // -------------------------------------------------------------------------
    // pendingRewards
    // -------------------------------------------------------------------------

    function test_pendingRewards_correctCalculation() public {
        uint256 tokenId = _stakeForAlice();
        vm.warp(block.timestamp + 200);
        assertEq(staking.pendingRewards(tokenId), 200 * uint256(REWARD_RATE));
    }

    function test_pendingRewards_returnsZeroIfNotStaked() public {
        assertEq(staking.pendingRewards(999), 0);
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
        vm.expectRevert(HardStaking.ZeroRewardRate.selector);
        staking.setRewardRate(0);
    }

    function test_setRewardRate_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        staking.setRewardRate(2e18);
    }

    // -------------------------------------------------------------------------
    // constructor
    // -------------------------------------------------------------------------

    function test_constructor_revertsOnZeroRate() public {
        vm.expectRevert(HardStaking.ZeroRewardRate.selector);
        new HardStaking(address(nft), address(rewardToken), 0);
    }

    // -------------------------------------------------------------------------
    // onERC721Received
    // -------------------------------------------------------------------------

    function test_onERC721Received_returnsCorrectSelector() public view {
        bytes4 expected = bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
        bytes4 result = staking.onERC721Received(address(0), address(0), 0, "");
        assertEq(result, expected);
    }

    // -------------------------------------------------------------------------
    // Multi-user
    // -------------------------------------------------------------------------

    function test_multiUser_independentRewardAccrual() public {
        uint256 aliceToken = _mintAndApprove(alice);
        vm.prank(alice);
        staking.stake(aliceToken);

        vm.warp(block.timestamp + 50);

        uint256 bobToken = _mintAndApprove(bob);
        vm.prank(bob);
        staking.stake(bobToken);

        vm.warp(block.timestamp + 100);

        assertEq(staking.pendingRewards(aliceToken), 150 * uint256(REWARD_RATE));
        assertEq(staking.pendingRewards(bobToken), 100 * uint256(REWARD_RATE));
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    function _mintAndApprove(address user) internal returns (uint256 tokenId) {
        tokenId = nft.mint(user);
        vm.prank(user);
        nft.approve(address(staking), tokenId);
    }

    function _stakeForAlice() internal returns (uint256 tokenId) {
        tokenId = _mintAndApprove(alice);
        vm.prank(alice);
        staking.stake(tokenId);
    }
}
