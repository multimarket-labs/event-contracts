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

    // 设置流动性池地址
    function setPool(address _pool) external onlyOwner {
        require(_pool != address(0), "Invalid pool address");
        pool = _pool;
    }

    // 设置 NFT position token ID
    function setPositionTokenId(uint256 _tokenId) external onlyOwner {
        require(_tokenId > 0, "Invalid token ID");
        positionTokenId = _tokenId;
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

    function getLiquidityProvidersByType(uint8 stakingType) external view returns (address[] memory) {
        return differentTypeLpList[stakingType];
    }

    function createLiquidityProviderReward(address lpAddress, uint256 amount, uint8 incomeType) external onlyStakingOperatorManager {
        require(lpAddress == address(0), "StakingManager.createLiquidityProviderReward: zero address");
        require(amount > 0, "StakingManager.createLiquidityProviderReward: amount should more than zero");

        if (incomeType == uint8(StakingRewardType.DailyNormalReward)) {
            totalLpStakingReward[lpAddress].directReferralReward += amount;
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

        if (amount > totalLpStakingReward[msg.sender].totalReward) {
            revert InvalidRewardAmount(msg.sender, amount);
        }

        totalLpStakingReward[msg.sender].totalReward -= amount;

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

    function addLiquidity(uint256 amount) external {
        // todo: amount, 将这个合约里面的一半的 USDT 买 CMO 代币，添加到流动性池里面
        // 将所有购买节点的资金用于加 LP, 将这个合约里面的一半的 USDT 买 underlyingToken 代币，添加到流动性池里面
        require(pool != address(0), "Pool not set");
        require(amount > 0, "Amount must be greater than 0");
        require(positionTokenId > 0, "Position token not initialized");

        // 步骤1: 查询交易对池子的汇率价格和代币顺序
        IPancakeV3Pool v3Pool = IPancakeV3Pool(pool);
        (uint160 sqrtPriceX96,,,,,,) = v3Pool.slot0();
        bool zeroForOne = USDT < underlyingToken;
        uint160 sqrtPriceLimitX96;
        if (zeroForOne) {
            sqrtPriceLimitX96 = uint160((uint256(sqrtPriceX96) * 95) / 100);
        } else {
            sqrtPriceLimitX96 = uint160((uint256(sqrtPriceX96) * 105) / 100);
        }

        // 步骤2: 用一半的 amount (USDT) 去买 underlyingToken 代币
        uint256 swapAmount = amount / 2;
        uint256 remainingAmount = amount - swapAmount; // 剩余的一半 USDT

        // 记录 swap 前的 underlyingToken 余额
        uint256 underlyingTokenBefore = IERC20(underlyingToken).balanceOf(address(this));

        IPancakeV3Pool(pool).swap(
            address(this),
            zeroForOne,
            int256(swapAmount),
            sqrtPriceLimitX96,
            abi.encode(pool)
        );

        // 步骤3: 计算实际获得的 underlyingToken 数量
        uint256 underlyingTokenAfter = IERC20(underlyingToken).balanceOf(address(this));
        uint256 underlyingTokenReceived = underlyingTokenAfter - underlyingTokenBefore;

        // underlyingTokenReceived: swap 实际获得的代币数量。remainingAmount: 剩余的一半 USDT
        uint256 underlyingTokenBalance = underlyingTokenReceived;
        uint256 usdtBalance = remainingAmount;

        // 批准 Position Manager 使用代币
        IERC20(underlyingToken).approve(POSITION_MANAGER, underlyingTokenBalance);
        IERC20(USDT).approve(POSITION_MANAGER, usdtBalance);

        // 根据池子中代币顺序设置 amount0 和 amount1
        uint256 amount0Desired;
        uint256 amount1Desired;
        if (zeroForOne) {
            amount0Desired = usdtBalance;
            amount1Desired = underlyingTokenBalance;
        } else {
            amount0Desired = underlyingTokenBalance;
            amount1Desired = usdtBalance;
        }

        // 构建增加流动性参数
        IV3NonfungiblePositionManager.IncreaseLiquidityParams memory params =
                            IV3NonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: positionTokenId,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: (amount0Desired * SLIPPAGE_TOLERANCE) / 100,
                amount1Min: (amount1Desired * SLIPPAGE_TOLERANCE) / 100,
                deadline: block.timestamp + 15 minutes
            });
        // 调用 increaseLiquidity 增加流动性
        (uint128 liquidityAdded, uint256 amount0Used, uint256 amount1Used) =
                                IV3NonfungiblePositionManager(POSITION_MANAGER).increaseLiquidity(params);

        emit LiquidityAdded(positionTokenId, liquidityAdded, amount0Used, amount1Used);
    }

    // PancakeSwap V3 Swap 回调函数
    function pancakeV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        require(msg.sender == pool, "Invalid callback caller");

        // 确定需要支付的代币和数量
        if (amount0Delta > 0) {
            address token0 = IPancakeV3Pool(pool).token0();
            IERC20(token0).safeTransfer(msg.sender, uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            address token1 = IPancakeV3Pool(pool).token1();
            IERC20(token1).safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }

    function swapBurn(uint256 amount) external {
        // 将 amount USDT 全部用于购买 underlyingToken 代币，然后销毁
        require(pool != address(0), "Pool not set");
        require(amount > 0, "Amount must be greater than 0");

        // 步骤1: 查询交易对池子的汇率价格和代币顺序
        IPancakeV3Pool v3Pool = IPancakeV3Pool(pool);
        (uint160 sqrtPriceX96,,,,,,) = v3Pool.slot0();
        bool zeroForOne = USDT < underlyingToken;
        uint160 sqrtPriceLimitX96;
        if (zeroForOne) {
            // USDT -> underlyingToken，价格下降
            sqrtPriceLimitX96 = uint160((uint256(sqrtPriceX96) * 95) / 100);
        } else {
            // underlyingToken -> USDT，价格上升
            sqrtPriceLimitX96 = uint160((uint256(sqrtPriceX96) * 105) / 100);
        }

        // 步骤2: 用全部的 amount USDT 去买 underlyingToken 代币
        // 记录 swap 前的 underlyingToken 余额
        uint256 underlyingTokenBefore = IERC20(underlyingToken).balanceOf(address(this));

        // 执行 swap
        IPancakeV3Pool(pool).swap(
            address(this),
            zeroForOne,
            int256(amount), // 使用全部 amount
            sqrtPriceLimitX96,
            abi.encode(pool)
        );

        // 步骤3: 计算实际获得的 underlyingToken 数量并销毁
        uint256 underlyingTokenAfter = IERC20(underlyingToken).balanceOf(address(this));
        uint256 underlyingTokenReceived = underlyingTokenAfter - underlyingTokenBefore;

        // 销毁实际获得的代币
        require(underlyingTokenReceived > 0, "No tokens received from swap");
        IChooseMeToken(underlyingToken).burn(address(this), underlyingTokenReceived);

        emit TokensBurned(amount, underlyingTokenReceived);
    }

    // ==============internal function================
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
