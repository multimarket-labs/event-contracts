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
        uint8   stakingType;
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
        uint8   stakingStatus;
    }

    struct LiquidityProviderStakingReward {
        address liquidityProvider;
        uint256 totalStaking;
        uint256 totalReward;
        uint256 dailyNormalReward;
        uint256 directReferralReward;
        uint256 teamReferralReward;
        uint256 fomoPoolReward;
    }

    event LiquidityProviderDeposits(
        address indexed tokenAddress,
        uint8   indexed stakingType,
        address indexed liquidityProvider,
        uint256 amount,
        uint256 startTime,
        uint256 endTime
    );

    event LiquidityProviderRewards (
        address indexed liquidityProvider,
        uint256 amount,
        uint256 rewardBlock,
        uint8   incomeType
    );

    event lpRoundStakingOver(
        address indexed liquidityProvider,
        uint256 endBlock,
        uint256 endTime
    );

    event lpClaimReward (
        address indexed liquidityProvider,
        uint256 withdrawAmount,
        uint256 toPredictionAmount
    );

    event outOfAchieveReturnsNodeExit (
        address indexed liquidityProvider,
        uint256 teamReward,
        uint256  blockNumber
    );

    // 1 pancake v2 liquidity; 2 pancake v3 liquidity ; 
    event LiquidityAdded (
        uint8 indexed poolType,
        uint256 indexed tokenId,
        uint256 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    event TokensBurned (
        uint256 usdtAmount,
        uint256 tokensBurned
    );

    error InvalidAmountError(uint256 amount);
    error InvalidRewardTypeError(uint8 incomeType);
    error StakeHolderUnderStakingError(address tokenAddress);
    error LpUnderStakingPeriodError(address lpAddress, uint256 lpRound);
    error InvalidRewardAmount(address lpAddress, uint256 lpRound);

    function liquidityProviderDeposit(address inviter, uint256 amount) external;

    function getLiquidityProvidersByType(uint8 stakingType) external view returns (address[] memory);

    function createLiquidityProviderReward(address lpAddress, uint256 amount, uint8 incomeType) external;

    function liquidityProviderRoundStakingOver(address lpAddress, uint256 lpStakingRound) external;

    function liquidityProviderClaimReward(uint256 amount) external;

    function addLiquidity(uint256 amount) external;

    function swapBurn(uint256 amount) external;
}
