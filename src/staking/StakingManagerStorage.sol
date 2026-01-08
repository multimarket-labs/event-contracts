// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../interfaces/staking/IStakingManager.sol";
import "../interfaces/token/IDaoRewardManager.sol";
import "../interfaces/staking/IEventFundingManager.sol";

abstract contract StakingManagerStorage is IStakingManager {
    uint256 public constant t1Staking = 200 * 10 ** 18;
    uint256 public constant t1StakingTimeInternal = 172800;

    uint256 public constant t2Staking = 600 * 10 ** 18;
    uint256 public constant t2StakingTimeInternal = 259200;

    uint256 public constant t3Staking = 1200 * 10 ** 18;
    uint256 public constant t3StakingTimeInternal = 345600;

    uint256 public constant t4Staking = 2500 * 10 ** 18;
    uint256 public constant t4StakingTimeInternal = 432000;

    uint256 public constant t5Staking = 6000 * 10 ** 18;
    uint256 public constant t5StakingTimeInternal = 518400;

    uint256 public constant t6Staking = 14000 * 10 ** 18;
    uint256 public constant t6StakingTimeInternal = 604800;

    address public constant POSITION_MANAGER = 0x46A15B0b27311cedF172AB29E4f4766fbE7F4364;
    uint256 public constant SLIPPAGE_TOLERANCE = 95;

    IDaoRewardManager public daoRewardManager;
    IEventFundingManager public eventFundingManager;

    address public USDT;
    address public underlyingToken;
    address public stakingOperatorManager;
    address public pool;
    uint256 public positionTokenId;

    mapping(address => uint256) public lpStakingRound;
    mapping(address => mapping(uint256 => LiquidityProviderInfo)) public currentLiquidityProvider;

    mapping(address => LiquidityProviderInfo[]) public liquidityProviderStakeHistory;
    mapping(address => LiquidityProviderStakingReward) public totalLpStakingReward;

    mapping(uint8 => address[]) public differentTypeLpList;
    mapping(address => address) public inviteRelationShip;
    mapping(address => bool) public teamOutOfReward;

    mapping(address => uint) public userCurrentLiquidityProvider;

    uint256[100] private __gap;
}
