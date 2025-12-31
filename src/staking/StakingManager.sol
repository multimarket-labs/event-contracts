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

import { StakingManagerStorage } from "./StakingManagerStorage.sol";

contract StakingManager is Initializable, OwnableUpgradeable, PausableUpgradeable, StakingManagerStorage {
    using SafeERC20 for IERC20;
    using SwapHelper for *;

    constructor(){
        _disableInitializers();
    }

    modifier onlyStakingOperatorManager() {
        require(msg.sender == address(stakingOperatorManager), "onlyRewardDistributionManager");
        _;
    }

    /**
     * @dev 接收原生代币（BNB）
     */
    receive() external payable {}

    /**
     * @dev 初始化质押管理器合约
     * @param initialOwner 初始所有者地址
     * @param _underlyingToken 底层代币地址（CMT）
     * @param _stakingOperatorManager 质押运营管理器地址
     * @param _daoRewardManager DAO 奖励管理合约地址
     * @param _eventFundingManager 事件资金管理合约地址
     */
    function initialize(address initialOwner, address _underlyingToken,address _usdt, address _stakingOperatorManager, address _daoRewardManager, address _eventFundingManager) public initializer  {
        __Ownable_init(initialOwner);
        underlyingToken = _underlyingToken;
        USDT = _usdt;
        stakingOperatorManager = _stakingOperatorManager;
        daoRewardManager = IDaoRewardManager(_daoRewardManager);
        eventFundingManager = IEventFundingManager(_eventFundingManager);
    }

    /**
     * @dev 设置交易池地址
     * @param _pool Pancake V3 交易池地址
     */
    function setPool(address _pool) external onlyOwner {
        require(_pool != address(0), "Invalid pool address");
        pool = _pool;
    }

    /**
     * @dev 设置流动性仓位 NFT ID
     * @param _tokenId Pancake V3 流动性仓位的 NFT Token ID
     */
    function setPositionTokenId(uint256 _tokenId) external onlyOwner {
        require(_tokenId > 0, "Invalid token ID");
        positionTokenId = _tokenId;
    }

    /**
     * @dev 流动性提供者质押存款
     * @param myInviter 邀请人地址
     * @param amount 质押金额，必须匹配 T1-T6 中的一种质押类型
     */
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

        (uint8 stakingType, uint256 endStakingTime) = liquidityProviderTypeAndAmount(amount);

        differentTypeLpList[stakingType].push(msg.sender);

        uint256 endStakingTimeDuration = block.timestamp + endStakingTime;

        LiquidityProviderInfo memory lpInfo = LiquidityProviderInfo({
            liquidityProvider: msg.sender,
            stakingType: stakingType,
            amount: amount,
            startTime: block.timestamp ,
            endTime: endStakingTimeDuration,
            stakingStatus: 0    // 0: staking; 1: endStaking
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

        emit LiquidityProviderDeposits(
            underlyingToken,
            msg.sender,
            amount,
            block.timestamp,
            endStakingTime
        );
    }

    /**
     * @dev 获取指定类型的流动性提供者列表
     * @param stakingType 质押类型（0-T1, 1-T2, ... 5-T6）
     * @return 该类型所有流动性提供者的地址数组
     */
    function getLiquidityProvidersByType(uint8 stakingType) external view returns (address[] memory) {
        return differentTypeLpList[stakingType];
    }

    /**
     * @dev 创建流动性提供者奖励（仅质押运营管理器可调用）
     * @param lpAddress 流动性提供者地址
     * @param amount 奖励金额
     * @param incomeType 收益类型（0-日常普通奖励, 1-直推奖励, 2-团队奖励, 3-FOMO池奖励）
     */
    function createLiquidityProviderReward(address lpAddress, uint256 amount, uint8 incomeType) external onlyStakingOperatorManager {
        require(lpAddress != address(0), "StakingManager.createLiquidityProviderReward: zero address");
        require(amount > 0, "StakingManager.createLiquidityProviderReward: amount should more than zero");

        if (incomeType == uint8(StakingRewardType.DailyNormalReward)) {
            totalLpStakingReward[lpAddress].dailyNormalReward += amount;
        } else if(incomeType == uint8(StakingRewardType.DirectReferralReward)) {
            totalLpStakingReward[lpAddress].directReferralReward += amount;
        } else if(incomeType == uint8(StakingRewardType.TeamReferralReward) && !teamOutOfReward[lpAddress]) {
            uint256 teamRewardAmount = totalLpStakingReward[lpAddress].teamReferralReward;  // CMT
            uint256 totalStakingAmount = totalLpStakingReward[lpAddress].totalStaking;      // USDT

            uint256 stakingToCmt = totalStakingAmount;  // todo: 读取 Oracle 的价格，将 CMT 转换成 USDT

            if ((teamRewardAmount + amount) < stakingToCmt * 3) {
                totalLpStakingReward[lpAddress].teamReferralReward += amount;
            } else {
                uint256 lastTeamReward = (teamRewardAmount + amount) - (stakingToCmt * 3);
                totalLpStakingReward[lpAddress].teamReferralReward += lastTeamReward;
                outOfAchieveReturnsNode(lpAddress, totalLpStakingReward[lpAddress].teamReferralReward);
            }
        } else if(incomeType == uint8(StakingRewardType.FomoPoolReward)) {
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

    /**
     * @dev 标记流动性提供者某轮质押结束（仅质押运营管理器可调用）
     * @param lpAddress 流动性提供者地址
     * @param lpStakingRound 质押轮次
     */
    function liquidityProviderRoundStakingOver(address lpAddress, uint256 lpStakingRound) external onlyStakingOperatorManager {
        require(lpAddress != address(0), "StakingManager.liquidityProviderRoundStakingOver: lp address is zero");

        LiquidityProviderInfo storage lpInfo = currentLiquidityProvider[lpAddress][lpStakingRound];
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

    /**
     * @dev 流动性提供者领取奖励
     * @param amount 要领取的奖励金额
     * @notice 20% 的奖励将被强制扣留并转换为 USDT 存入事件预测市场
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

            uint256 usdtAmount = SwapHelper.swapTokenToUsdt(
                pool,
                underlyingToken,
                USDT,
                toEventPredictionAmount,
                address(this)
            );

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
     * @dev 添加流动性到 Pancake V3 池
     * @param amount 要添加的 USDT 总量
     * @notice 将 50% 的 USDT 兑换为底层代币，然后添加流动性
     */
    function addLiquidity(uint256 amount) external onlyStakingOperatorManager {
        require(pool != address(0), "Pool not set");
        require(amount > 0, "Amount must be greater than 0");
        require(positionTokenId > 0, "Position token not initialized");

        uint256 swapAmount = amount / 2;
        uint256 remainingAmount = amount - swapAmount;

        IERC20(USDT).approve(POSITION_MANAGER, amount);
        uint256 underlyingTokenReceived = SwapHelper.swapUsdtToToken(
            pool,
            USDT,
            underlyingToken,
            swapAmount,
            address(this)
        );

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
        (uint128 liquidityAdded, uint256 amount0Used, uint256 amount1Used) = IV3NonfungiblePositionManager(POSITION_MANAGER).increaseLiquidity(params);

        emit LiquidityAdded(positionTokenId, liquidityAdded, amount0Used, amount1Used);
    }

    /**
     * @dev Pancake V3 交换回调函数
     * @param amount0Delta token0 的变化量
     * @param amount1Delta token1 的变化量
     * @param data 回调数据
     */
    function pancakeV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        require(msg.sender == pool, "Invalid callback caller");
        SwapHelper.handleSwapCallback(pool, amount0Delta, amount1Delta, msg.sender);
    }

    /**
     * @dev 将 USDT 兑换为底层代币并销毁
     * @param amount 要兑换的 USDT 金额
     */
    function swapBurn(uint256 amount) external onlyStakingOperatorManager {
        IERC20(USDT).approve(POSITION_MANAGER, amount);
        uint256 underlyingTokenReceived = SwapHelper.swapUsdtToToken(
            pool,
            USDT,
            underlyingToken,
            amount,
            address(this)
        );

        require(underlyingTokenReceived > 0, "No tokens received from swap");
        IChooseMeToken(underlyingToken).burn(address(this), underlyingTokenReceived);

        emit TokensBurned(amount, underlyingTokenReceived);
    }

    // ==============internal function================
    /**
     * @dev 根据质押金额确定质押类型和锁定时间
     * @param amount 质押金额
     * @return stakingType 质押类型
     * @return stakingTimeInternal 锁定时间（秒）
     */
    function liquidityProviderTypeAndAmount(uint256 amount) internal view returns (uint8, uint256)  {
        uint8 stakingType;
        uint256 stakingTimeInternal;
        if (amount == t1Staking)  {
            stakingType = uint8(StakingType.T1);
            stakingTimeInternal = t1StakingTimeInternal;
        } else if (amount == t2Staking) {
            stakingType = uint8(StakingType.T2);
            stakingTimeInternal = t2StakingTimeInternal;
        } else if (amount == t3Staking) {
            stakingType = uint8(StakingType.T3);
            stakingTimeInternal = t3StakingTimeInternal;
        }  else if (amount == t4Staking) {
            stakingType = uint8(StakingType.T4);
            stakingTimeInternal = t4StakingTimeInternal;
        } else if (amount == t5Staking) {
            stakingType = uint8(StakingType.T5);
            stakingTimeInternal = t5StakingTimeInternal;
        } else if (amount == t6Staking) {
            stakingType = uint8(StakingType.T6);
            stakingTimeInternal = t6StakingTimeInternal;
        } else  {
            revert InvalidAmountError(amount);
        }

        return (stakingType, stakingTimeInternal);
    }

    /**
     * @dev 标记节点已达到团队奖励上限（3倍质押金额）
     * @param lpAddress 流动性提供者地址
     * @param teamRewardAmount 团队奖励总金额
     */
    function outOfAchieveReturnsNode(address lpAddress, uint256 teamRewardAmount) internal {
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
