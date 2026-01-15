// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IStakingManager {
    enum StakingType {
        T1,
        T2,
        T3,
        T4,
        T5,
        T6
    }

    enum StakingLevel {
        S0,
        S1,
        S2,
        S3,
        S4,
        S5,
        S6,
        S7,
        S8,
        S9
    }

    enum StakingRewardType {
        DailyNormalReward,
        DirectReferralReward,
        TeamReferralReward,
        FomoPoolReward
    }

    struct LiquidityProviderInfo {
        address liquidityProvider;
        uint8 stakingType;
        uint256 amount;
        uint256 rewardUAmount;
        uint256 rewardAmount;
        uint256 startTime;
        uint256 endTime;
    }

    struct LiquidityProviderStakingReward {
        address liquidityProvider;
        uint256 totalStaking;
        uint256 totalReward;
        uint256 totalUReward;
        uint256 claimedReward;
        uint256 dailyNormalReward;
        uint256 directReferralReward;
        uint256 teamReferralReward;
        uint256 fomoPoolReward;
    }

    struct BatchReward {
        address lpAddress;
        uint256 round;
        uint256 tokenAmount;
        uint256 usdtAmount;
        uint8 incomeType;
    }

    event LiquidityProviderDeposits(
        uint256 round,
        address indexed tokenAddress,
        uint8 indexed stakingType,
        address indexed liquidityProvider,
        uint256 amount,
        uint256 startTime,
        uint256 endTime
    );

    event LiquidityProviderRewards(
        uint256 indexed round,
        address indexed liquidityProvider,
        uint256 tokenAmount,
        uint256 usdtAmount,
        uint256 rewardBlock,
        uint8 incomeType
    );

    event lpClaimReward(address indexed liquidityProvider, uint256 withdrawAmount, uint256 toPredictionAmount);

    event outOfAchieveReturnsNodeExit(
        address indexed liquidityProvider, uint256 round, uint256 totalReward, uint256 blockNumber
    );

    event LiquidityAdded(uint256 liquidity, uint256 amount0, uint256 amount1);

    event TokensBurned(uint256 usdtAmount, uint256 tokensBurned);

    error InvalidAmountError(uint256 amount);
    error InvalidRewardTypeError(uint8 incomeType);
    error StakeHolderUnderStakingError(address tokenAddress);
    error InvalidRewardAmount(address lpAddress, uint256 lpRound);

    function liquidityProviderDeposit(uint256 amount) external;

    function getLiquidityProvidersByType(uint8 stakingType) external view returns (address[] memory);

    function createLiquidityProviderReward(
        address lpAddress,
        uint256 round,
        uint256 tokenAmount,
        uint256 usdtAmount,
        uint8 incomeType
    ) external;
    function createLiquidityProviderRewardBatch(BatchReward[] memory batchRewards) external;

    function liquidityProviderClaimReward(uint256 amount) external;

    function addLiquidity(uint256 amount) external;

    function swapBurn(uint256 amount, uint256 subTokenUAmount) external;
}
