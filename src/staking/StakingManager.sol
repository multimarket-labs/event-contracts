// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { StakingManagerStorage } from "./StakingManagerStorage.sol";

contract StakingManager is Initializable, OwnableUpgradeable, PausableUpgradeable, StakingManagerStorage {
    using SafeERC20 for IERC20;

    constructor(){
        _disableInitializers();
    }

    modifier onlyStakingOperatorManager() {
        require(msg.sender == address(stakingOperatorManager), "onlyRewardDistributionManager");
        _;
    }

    receive() external payable {}

    function initialize(address initialOwner, address _underlyingToken, address _stakingOperatorManager, IDaoRewardManager _daoRewardManager) public initializer  {
        __Ownable_init(initialOwner);
        underlyingToken = _underlyingToken;
        stakingOperatorManager = _stakingOperatorManager;
        daoRewardManager = _daoRewardManager;
    }

    function liquidityProviderDeposit(address myInviter, uint256 amount) external {
        if (
            amount != t1Staking &&
            amount != t2Staking &&
            amount != t3Staking &&
            amount != t4Staking &&
            amount != t5Staking &&
            amount != t6Staking
        ) {
            revert InvalidAmountError(amount);
        }

        inviteRelationShip[msg.sender] = myInviter;

        IERC20(underlyingToken).safeTransferFrom(msg.sender, address(this), amount);

        (stakingType, endStakingTime) = liquidityProviderTypeAndAmount(amount);

        differentTypeLpList[stakingType].push(msg.sender);

        uint256 endStakingTime = block.timestamp + stakingTimeInternal;

        LiquidityProviderInfo memory lpInfo = LiquidityProviderInfo({
            liquidityProvider: msg.sender,
            stakingType: stakingType,
            amount: amount,
            startTime: block.timestamp ,
            endTime: endStakingTime,
            stakingStatus: 0    // 0: staking; 1: endStaking
        });

        currentLiquidityProvider[msg.sender][lpStakingRound] = lpInfo;

        if (!totalLpStaking[msg.sender].liquidityProvider == address(0)) {
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

        emit LiquidityProviderDeposits(
            underlyingToken,
            msg.sender,
            amount,
            block.timestamp,
            endStakingTime
        );
    }

    function getLiquidityProviderInfo(address liquidityProvider) external view returns (LiquidityProviderInfo) {
        return liquidityProviders[msg.sender];
    }

    function getLiquidityProvidersByType(uint8 stakingType) external view returns (address[]) {
        return differentTypeLpList[stakingType];
    }

    function createLiquidityProviderReward(address lpAddress, uint256 amount, uint8 incomeType) external onlyStakingOperatorManager {
        require(lpAddress == address(0), "StakingManager.createLiquidityProviderReward: zero address");
        require(amount > 0, "StakingManager.createLiquidityProviderReward: amount should more than zero");

        if (incomeType == StakingRewardType.DailyNormalReward) {
            totalLpStakingReward[lpAddress].directReferralReward += amount;
        } else if(incomeType == StakingRewardType.DirectReferralReward) {
            totalLpStakingReward[lpAddress].directReferralReward += amount;
        } else if(incomeType == StakingRewardType.TeamReferralReward && !teamOutOfReward[lpAddress]) {
            uint256 teamRewardAmount = totalLpStakingReward[lpAddress].teamReferralReward;  // CMT
            uint256 totalStakingAmount = totalLpStakingReward[lpAddress].totalStaking;      // USDT

            uint256 stakingToCmt = totalStakingAmount;  // todo: 读取 Oracle 的价格，将 CMT 转换成 USDT

            if ((teamRewardAmount + amount) < stakingToCmt * 3) {
                totalLpStakingReward[lpAddress].teamReferralReward += amount;
            } else {
                uint256 lastTeamReward = (teamRewardAmount + amount) - (stakingToCmt * 3);
                totalLpStakingReward[lpAddress].teamReferralReward += lastTeamReward;
                outOfAchieveReturnsNode(lpAddress);
            }
        } else if(incomeType == StakingRewardType.FomoPoolReward) {
            totalLpStakingReward[lpAddress].fomoPoolReward += amount;
        } else {
            revert InvalidRewardTypeError(incomeType);
        }
        totalLpStakingReward[lpAddress].totalReward += amount;

        emit LiquidityProviderRewards({
            liquidityProvider: lpAddress,
            amount: amount,
            rewardBlock: block.number,
            incomeType: incomeType
        });
    }

    function liquidityProviderRoundStakingOver(address lpAddress, uint256 lpStakingRound) external onlyStakingOperatorManager {
        require(lpAddress == address(0), "StakingManager.liquidityProviderRoundStakingOver: lp address is zero");

        LiquidityProviderInfo memory lpInfo = currentLiquidityProvider[lpAddress][lpStakingRound];
        if (lpInfo.endTime > block.timestamp) {
            revert LpUnderStakingPeriodError(lpAddress, lpStakingRound);
        }

        lpInfo.stakingStatus = 1;

        emit lpRoundStakingOver({
            liquidityProvider: lpAddress,
            endBlock: block.number,
            endTime: block.timestamp
        });
    }

    function liquidityProviderClaimReward(uint256 amount) external {
        require(amount > 0, "StakingManager.liquidityProviderClaimReward: reward amount must more than zero");

        if (amount > totalLpStaking[msg.sender].totalProfit) {
            revert InvalidRewardAmount(msg.sender, amount);
        }

        totalLpStaking[msg.sender].totalProfit -= amount;

        uint256 toEventPredictionAmount = (amount * 20) / 100;

        // todo 20% 兑换成 USDT 打入事件预测市场

        uint256 canWithdrawAmount = amount - toEventPredictionAmount;

        daoRewardManager.withdraw(msg.sender, canWithdrawAmount);

        emit lpClaimReward({
            liquidityProvider: msg.sender,
            withdrawAmount: canWithdrawAmount,
            toPredictionAmount: toEventPredictionAmount
        });
    }

    function addLiquidity() external {

    }

    function swapBurn() external {

    }

    // ==============internal function================
    function liquidityProviderTypeAndAmount(uint256 amount) internal view returns (uint8, uint256)  {
        uint8 stakingType;
        uint256 stakingTimeInternal;
        if (amount == t1Staking)  {
            stakingType = StakingType.T1;
            stakingTimeInternal = t1StakingTimeInternal;
        } else if (amount == t2Staking) {
            stakingType = StakingType.T2;
            stakingTimeInternal = t2StakingTimeInternal;
        } else if (amount == t3Staking) {
            stakingType = StakingType.T3;
            stakingTimeInternal = t3StakingTimeInternal;
        }  else if (amount == t4Staking) {
            stakingType = StakingType.T4;
            stakingTimeInternal = t4StakingTimeInternal;
        } else if (amount == t5Staking) {
            stakingType = StakingType.T5;
            stakingTimeInternal = t5StakingTimeInternal;
        } else if (amount == t6Staking) {
            stakingType = StakingType.T6;
            stakingTimeInternal = t6StakingTimeInternal;
        } else  {
            revert InvalidAmount(amount);
        }

        return (stakingType, stakingTimeInternal);
    }

    function outOfAchieveReturnsNode(address lpAddress) internal {
        teamOutOfReward[lpAddress] = true;

        emit outOfAchieveReturnsNodeExit({
            liquidityProvider: lpAddress,
            teamReward: teamRewardAmount,
            blockNumber: block.number
        });
    }
}

/*
 * 二级市场收益，强制扣留（第⼀个⽉和第⼆个⽉:40%, 后期:30%),卖成 USDT 打入到 FOMO(国库) 池合约，
 * FOMO 所有池资金分给当天投 6000U 和 14000U 的人
 *
*/

/*
 * 质押收益（直推和网体的）：从合约 Claim 的时候，强制扣留 20% 的代币，
 * 兑换成 USDT 打到另一个合约，未来进入预测市场，而且这个资金只能流入事件预测市场
 *
*/

/*
 * 直推网体收益每天 0 点结算一次
 *
*/

/*
 * 节点 6000U，10000U 和 14000U 的人可以开通事件预测市场 C 端产品
 *
*/
