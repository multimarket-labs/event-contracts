// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/token/IDaoRewardManager.sol";
import "../interfaces/token/IChooseMeToken.sol";
import "../interfaces/staking/pancake/IPancakeV3Pool.sol";
import "../interfaces/staking/pancake/IV3NonfungiblePositionManager.sol";
import "../interfaces/staking/pancake/IPancakeV3SwapCallback.sol";
import "../interfaces/staking/IEventFundingManager.sol";
import "../utils/SwapHelper.sol";

import {StakingManagerStorage} from "./StakingManagerStorage.sol";

contract StakingManager is Initializable, OwnableUpgradeable, PausableUpgradeable, StakingManagerStorage {
    using SafeERC20 for IERC20;
    using SwapHelper for *;

    constructor() {
        _disableInitializers();
    }

    modifier onlyStakingOperatorManager() {
        require(msg.sender == address(stakingOperatorManager), "onlyRewardDistributionManager");
        _;
    }

    /**
     * @dev Receive native tokens (BNB)
     */
    receive() external payable {}

    /**
     * @dev Initialize the Staking Manager contract
     * @param initialOwner Initial owner address
     * @param _underlyingToken Underlying token address (CMT)
     * @param _stakingOperatorManager Staking operator manager address
     * @param _daoRewardManager DAO reward manager contract address
     * @param _eventFundingManager Event funding manager contract address
     */
    function initialize(
        address initialOwner,
        address _underlyingToken,
        address _usdt,
        address _stakingOperatorManager,
        address _daoRewardManager,
        address _eventFundingManager
    ) public initializer {
        __Ownable_init(initialOwner);
        underlyingToken = _underlyingToken;
        USDT = _usdt;
        stakingOperatorManager = _stakingOperatorManager;
        daoRewardManager = IDaoRewardManager(_daoRewardManager);
        eventFundingManager = IEventFundingManager(_eventFundingManager);
    }

    /**
     * @dev Set trading pool address
     * @param _pool Pancake V3 trading pool address
     */
    function setPool(address _pool) external onlyOwner {
        require(_pool != address(0), "Invalid pool address");
        pool = _pool;
    }

    /**
     * @dev Set liquidity position NFT ID
     * @param _tokenId NFT Token ID of Pancake V3 liquidity position
     */
    function setPositionTokenId(uint256 _tokenId) external onlyOwner {
        require(_tokenId > 0, "Invalid token ID");
        positionTokenId = _tokenId;
    }

    /**
     * @dev Liquidity provider staking deposit - User side
     * @param myInviter Inviter address
     * @param amount Staking amount, must match one of the staking types from T1-T6
     */
    function liquidityProviderDeposit(address myInviter, uint256 amount) external {
        if (
            amount != t1Staking && amount != t2Staking && amount != t3Staking && amount != t4Staking
                && amount != t5Staking && amount != t6Staking
        ) {
            revert InvalidAmountError(amount);
        }

        inviteRelationShip[msg.sender] = myInviter;

        IERC20(underlyingToken).safeTransferFrom(msg.sender, address(this), amount);

        (uint8 stakingType, uint256 endStakingTime) = liquidityProviderTypeAndAmount(amount);

        differentTypeLpList[stakingType].push(msg.sender);

        uint256 endStakingTimeDuration = block.timestamp + endStakingTime;

        LiquidityProviderInfo memory lpInfo = LiquidityProviderInfo({
            liquidityProvider: msg.sender,
            stakingType: stakingType,
            amount: amount,
            startTime: block.timestamp,
            endTime: endStakingTimeDuration,
            stakingStatus: 0 // 0: staking; 1: endStaking
        });

        currentLiquidityProvider[msg.sender][lpStakingRound[msg.sender]] = lpInfo;

        if (totalLpStakingReward[msg.sender].liquidityProvider != address(0)) {
            totalLpStakingReward[msg.sender] = LiquidityProviderStakingReward({
                liquidityProvider: msg.sender,
                totalStaking: amount,
                totalReward: 0,
                dailyNormalReward: 0,
                directReferralReward: 0,
                teamReferralReward: 0,
                fomoPoolReward: 0
            });
        } else {
            totalLpStakingReward[msg.sender].totalStaking += amount;
        }

        lpStakingRound[msg.sender] += 1;

        emit LiquidityProviderDeposits(underlyingToken, msg.sender, amount, block.timestamp, endStakingTime);
    }

    /**
     * @dev Get liquidity providers list by type
     * @param stakingType Staking type (0-T1, 1-T2, ... 5-T6)
     * @return Address array of all liquidity providers of this type
     */
    function getLiquidityProvidersByType(uint8 stakingType) external view returns (address[] memory) {
        return differentTypeLpList[stakingType];
    }

    /**
     * @dev Create liquidity provider reward (only staking operator manager can call)
     * @param lpAddress Liquidity provider address
     * @param amount Reward amount
     * @param incomeType Income type (0 - daily normal reward, 1 - direct referral reward, 2 - team reward, 3 - FOMO pool reward)
     */
    function createLiquidityProviderReward(address lpAddress, uint256 amount, uint8 incomeType)
        external
        onlyStakingOperatorManager
    {
        require(lpAddress != address(0), "StakingManager.createLiquidityProviderReward: zero address");
        require(amount > 0, "StakingManager.createLiquidityProviderReward: amount should more than zero");

        if (incomeType == uint8(StakingRewardType.DailyNormalReward)) {
            totalLpStakingReward[lpAddress].dailyNormalReward += amount;
        } else if (incomeType == uint8(StakingRewardType.DirectReferralReward)) {
            totalLpStakingReward[lpAddress].directReferralReward += amount;
        } else if (incomeType == uint8(StakingRewardType.TeamReferralReward) && !teamOutOfReward[lpAddress]) {
            uint256 teamRewardAmount = totalLpStakingReward[lpAddress].teamReferralReward; // CMT
            uint256 totalStakingAmount = totalLpStakingReward[lpAddress].totalStaking; // USDT

            uint256 stakingToCmt = totalStakingAmount; // TODO: Read Oracle price, convert CMT to USDT

            if ((teamRewardAmount + amount) < stakingToCmt * 3) {
                totalLpStakingReward[lpAddress].teamReferralReward += amount;
            } else {
                uint256 lastTeamReward = (teamRewardAmount + amount) - (stakingToCmt * 3);
                totalLpStakingReward[lpAddress].teamReferralReward += lastTeamReward;
                outOfAchieveReturnsNode(lpAddress, totalLpStakingReward[lpAddress].teamReferralReward);
            }
        } else if (incomeType == uint8(StakingRewardType.FomoPoolReward)) {
            totalLpStakingReward[lpAddress].fomoPoolReward += amount;
        } else {
            revert InvalidRewardTypeError(incomeType);
        }
        totalLpStakingReward[lpAddress].totalReward += amount;

        emit LiquidityProviderRewards({
            liquidityProvider: lpAddress, amount: amount, rewardBlock: block.number, incomeType: incomeType
        });
    }

    /**
     * @dev Mark liquidity provider round staking as ended (only staking operator manager can call)
     * @param lpAddress Liquidity provider address
     * @param lpStakingRound Staking round
     */
    function liquidityProviderRoundStakingOver(address lpAddress, uint256 lpStakingRound)
        external
        onlyStakingOperatorManager
    {
        require(lpAddress != address(0), "StakingManager.liquidityProviderRoundStakingOver: lp address is zero");

        LiquidityProviderInfo storage lpInfo = currentLiquidityProvider[lpAddress][lpStakingRound];
        if (lpInfo.endTime > block.timestamp) {
            revert LpUnderStakingPeriodError(lpAddress, lpStakingRound);
        }

        lpInfo.stakingStatus = 1;

        emit lpRoundStakingOver({liquidityProvider: lpAddress, endBlock: block.number, endTime: block.timestamp});
    }

    /**
     * @dev Liquidity provider claim reward - User side
     * @param amount Reward amount to claim
     * @notice 20% of rewards will be forcibly withheld and converted to USDT for deposit into event prediction market
     */
    function liquidityProviderClaimReward(uint256 amount) external {
        require(amount > 0, "StakingManager.liquidityProviderClaimReward: reward amount must more than zero");

        if (amount > totalLpStakingReward[msg.sender].totalReward) {
            revert InvalidRewardAmount(msg.sender, amount);
        }

        totalLpStakingReward[msg.sender].totalReward -= amount;

        uint256 toEventPredictionAmount = (amount * 20) / 100;

        if (toEventPredictionAmount > 0) {
            daoRewardManager.withdraw(address(this), toEventPredictionAmount);

            uint256 usdtAmount =
                SwapHelper.swapTokenToUsdt(pool, underlyingToken, USDT, toEventPredictionAmount, address(this));

            IERC20(USDT).approve(address(eventFundingManager), usdtAmount);
            eventFundingManager.depositUsdt(usdtAmount);
        }

        uint256 canWithdrawAmount = amount - toEventPredictionAmount;

        daoRewardManager.withdraw(msg.sender, canWithdrawAmount);

        emit lpClaimReward({
            liquidityProvider: msg.sender,
            withdrawAmount: canWithdrawAmount,
            toPredictionAmount: toEventPredictionAmount
        });
    }

    /**
     * @dev Add liquidity to Pancake V3 pool
     * @param amount Total amount of USDT to add
     * @notice Convert 50% of USDT to underlying token, then add liquidity
     */
    function addLiquidity(uint256 amount) external onlyStakingOperatorManager {
        require(pool != address(0), "Pool not set");
        require(amount > 0, "Amount must be greater than 0");
        require(positionTokenId > 0, "Position token not initialized");

        uint256 swapAmount = amount / 2;
        uint256 remainingAmount = amount - swapAmount;

        IERC20(USDT).approve(POSITION_MANAGER, amount);
        uint256 underlyingTokenReceived =
            SwapHelper.swapUsdtToToken(pool, USDT, underlyingToken, swapAmount, address(this));

        uint256 underlyingTokenBalance = underlyingTokenReceived;
        uint256 usdtBalance = remainingAmount;

        IERC20(underlyingToken).approve(POSITION_MANAGER, underlyingTokenBalance);

        bool zeroForOne = USDT < underlyingToken;
        uint256 amount0Desired;
        uint256 amount1Desired;
        if (zeroForOne) {
            amount0Desired = usdtBalance;
            amount1Desired = underlyingTokenBalance;
        } else {
            amount0Desired = underlyingTokenBalance;
            amount1Desired = usdtBalance;
        }

        IV3NonfungiblePositionManager.IncreaseLiquidityParams memory params =
            IV3NonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: positionTokenId,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: (amount0Desired * SLIPPAGE_TOLERANCE) / 100,
                amount1Min: (amount1Desired * SLIPPAGE_TOLERANCE) / 100,
                deadline: block.timestamp + 15 minutes
            });
        (uint128 liquidityAdded, uint256 amount0Used, uint256 amount1Used) =
            IV3NonfungiblePositionManager(POSITION_MANAGER).increaseLiquidity(params);

        emit LiquidityAdded(positionTokenId, liquidityAdded, amount0Used, amount1Used);
    }

    /**
     * @dev Pancake V3 swap callback function
     * @param amount0Delta Change amount of token0
     * @param amount1Delta Change amount of token1
     * @param data Callback data
     */
    function pancakeV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        require(msg.sender == pool, "Invalid callback caller");
        SwapHelper.handleSwapCallback(pool, amount0Delta, amount1Delta, msg.sender);
    }

    /**
     * @dev Swap USDT for underlying token and burn
     * @param amount USDT amount to swap
     */
    function swapBurn(uint256 amount) external onlyStakingOperatorManager {
        IERC20(USDT).approve(POSITION_MANAGER, amount);
        uint256 underlyingTokenReceived = SwapHelper.swapUsdtToToken(pool, USDT, underlyingToken, amount, address(this));

        require(underlyingTokenReceived > 0, "No tokens received from swap");
        IChooseMeToken(underlyingToken).burn(address(this), underlyingTokenReceived);

        emit TokensBurned(amount, underlyingTokenReceived);
    }

    // ==============internal function================
    /**
     * @dev Determine staking type and lock time based on staking amount
     * @param amount Staking amount
     * @return stakingType Staking type
     * @return stakingTimeInternal Lock time (seconds)
     */
    function liquidityProviderTypeAndAmount(uint256 amount) internal view returns (uint8, uint256) {
        uint8 stakingType;
        uint256 stakingTimeInternal;
        if (amount == t1Staking) {
            stakingType = uint8(StakingType.T1);
            stakingTimeInternal = t1StakingTimeInternal;
        } else if (amount == t2Staking) {
            stakingType = uint8(StakingType.T2);
            stakingTimeInternal = t2StakingTimeInternal;
        } else if (amount == t3Staking) {
            stakingType = uint8(StakingType.T3);
            stakingTimeInternal = t3StakingTimeInternal;
        } else if (amount == t4Staking) {
            stakingType = uint8(StakingType.T4);
            stakingTimeInternal = t4StakingTimeInternal;
        } else if (amount == t5Staking) {
            stakingType = uint8(StakingType.T5);
            stakingTimeInternal = t5StakingTimeInternal;
        } else if (amount == t6Staking) {
            stakingType = uint8(StakingType.T6);
            stakingTimeInternal = t6StakingTimeInternal;
        } else {
            revert InvalidAmountError(amount);
        }

        return (stakingType, stakingTimeInternal);
    }

    /**
     * @dev Mark node as having reached team reward limit (3x staking amount)
     * @param lpAddress Liquidity provider address
     * @param teamRewardAmount Total team reward amount
     */
    function outOfAchieveReturnsNode(address lpAddress, uint256 teamRewardAmount) internal {
        teamOutOfReward[lpAddress] = true;

        emit outOfAchieveReturnsNodeExit({
            liquidityProvider: lpAddress, teamReward: teamRewardAmount, blockNumber: block.number
        });
    }
}
