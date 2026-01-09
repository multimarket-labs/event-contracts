// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-upgrades/contracts/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../interfaces/staking/pancake/IPancakeV3Pool.sol";
import "@pancake-v2-core/interfaces/IPancakePair.sol";
import "@pancake-v2-core/interfaces/IPancakeFactory.sol";
import "@pancake-v2-periphery/interfaces/IPancakeRouter02.sol";
import {TradeSlippage} from "../utils/TradeSlippage.sol";
import "./ChooseMeTokenStorage.sol";

contract ChooseMeToken is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    OwnableUpgradeable,
    TradeSlippage,
    ChooseMeTokenStorage
{
    string private constant NAME = "ChooseMe Coin";
    string private constant SYMBOL = "CMT";

    constructor() {
        _disableInitializers();
    }

    modifier onlyStakingManager() {
        require(
            msg.sender == stakingManager, "ChooseMeToken onlyStakingManager: Only StakingManager can call this function"
        );
        _;
    }

    /**
     * @dev Initialize the ChooseMe token contract
     * @param _owner Owner address
     * @param _stakingManager Staking manager address
     */
    function initialize(address _owner, address _stakingManager, address _usdt) public initializer {
        require(_owner != address(0), "ChooseMeToken initialize: _owner can't be zero address");
        __ERC20_init(NAME, SYMBOL);
        __ERC20Burnable_init();
        __Ownable_init(_owner);
        _transferOwnership(_owner);
        stakingManager = _stakingManager;

        USDT = _usdt;

        EnumerableSet.add(factories, V2_FACTORY); // PancakeSwap V2 Factory address on BSC

        marketOpenTime = block.timestamp;

        mainPair = IPancakeFactory(V2_FACTORY).createPair(USDT, address(this));
        emit SetStakingManager(_stakingManager);

        tradeFee = ChooseMeTradeFee({
            nodeFee: 50, // 0.5 %
            clusterFee: 50, // 0.5 %
            marketFee: 50, // 0.5 %
            techFee: 100, // 1 %
            subTokenFee: 50 // 0.5 %
        });

        profitFee = ChooseMeProfitFee({
            normalFee: 1600, // 16 %
            nodeFee: 1000, // 10 %
            clusterFee: 500, // 5 %
            marketFee: 500, // 5 %
            techFee: 500, // 5 %
            subTokenFee: 500 // 5 %
        });
        
    }

    function _update(address from, address to, uint256 value) internal override {
        if (isWhitelisted(from, to) || !isAllocation) {
            super._update(from, to, value);
            return;
        }

        (bool isBuy, bool isSell,,,,) = getTradeType(from, to, value, address(this));
        // (bool isV3Buy, bool isV3Sell) = getV3TradeType(from, to, value);

        // trade slippage fee only for buy/sell
        uint256 finallyValue = value;
        if (isBuy || isSell) {
            uint256 every = value / 10000;

            uint256 nodeFee = every * tradeFee.nodeFee; // 0.5 %
            super._update(from, cmPool.daoRewardPool, nodeFee);

            uint256 clusterFee = every * tradeFee.clusterFee; // 0.5 %
            super._update(from, cmPool.daoRewardPool, clusterFee);

            uint256 marketFee = every * tradeFee.marketFee; // 0.5 %
            super._update(from, cmPool.marketingDevelopmentPool, marketFee);

            uint256 techFee = every * tradeFee.techFee; // 1 %
            super._update(from, cmPool.techRewardsPool, techFee);

            uint256 subFee = every * tradeFee.subTokenFee; // 0.5 %
            super._update(from, cmPool.subTokenPool, subFee);

            finallyValue = value - (nodeFee + clusterFee + marketFee + techFee + subFee);

            emit TradeSlipage(value, nodeFee, clusterFee, marketFee, techFee, subFee);
        }

        // profit fee only for sell
        (uint rOther, uint rThis,,) = getReserves(mainPair, address(this));
        uint256 curUValue;
        if (isBuy) {
            curUValue = IPancakeRouter01(V2_ROUTER).getAmountIn(value, rOther, rThis);
        } else if (isSell) {
            curUValue = IPancakeRouter01(V2_ROUTER).getAmountOut(value, rThis, rOther);
        } else {
            // Used for calculating the cost price for special address transactions,
            // such as transfers to airdrop addresses of staking contracts, node reward addresses, etc
            if (isFromSpecial(from)) {
                curUValue = IPancakeRouter01(V2_ROUTER).getAmountOut(value, rThis, rOther);
            } else {
                curUValue = userCost[from] * value / balanceOf(from);
            }
        }

        userCost[to] += curUValue;
        uint256 profit;
        uint256 fromUValue = curUValue;
        if (fromUValue > userCost[from]) {
            profit = fromUValue - userCost[from];
            fromUValue = userCost[from];
        }
        userCost[from] -= fromUValue;

        // Profit USDT is greater than 0, a profit handling fee will be charged
        if (profit > 0) {
            uint256 everyProfit = value * profit / curUValue / 10000;

            uint256 normalFee;

            if (block.timestamp >= marketOpenTime + 60 days) {
                normalFee = everyProfit * profitFee.normalFee;
                super._update(from, cmPool.normalPool, normalFee);
            }

            uint256 nodeFee = everyProfit * profitFee.nodeFee;
            super._update(from, cmPool.daoRewardPool, nodeFee);

            uint256 clusterFee = everyProfit * profitFee.clusterFee;
            super._update(from, cmPool.daoRewardPool, clusterFee);

            uint256 marketFee = everyProfit * profitFee.marketFee;
            super._update(from, cmPool.marketingDevelopmentPool, marketFee);

            uint256 techFee = everyProfit * profitFee.techFee;
            super._update(from, cmPool.techRewardsPool, techFee);

            uint256 subFee = everyProfit * profitFee.subTokenFee;
            super._update(from, cmPool.subTokenPool, subFee);

            emit ProfitSlipage(value, normalFee, nodeFee, clusterFee, marketFee, techFee, subFee);
            finallyValue = finallyValue - (normalFee + nodeFee + clusterFee + marketFee + techFee + subFee);
        }

        super._update(from, to, finallyValue);
    }

    function isFromSpecial(address from) internal view returns (bool) {
        return from == cmPool.nodePool || from == cmPool.daoRewardPool || from == cmPool.techRewardsPool
            || from == cmPool.ecosystemPool || from == cmPool.foundingStrategyPool
            || from == cmPool.marketingDevelopmentPool || from == cmPool.subTokenPool;
    }

    function isWhitelisted(address from, address to) public view returns (bool) {
        return EnumerableSet.contains(whiteList, from) || EnumerableSet.contains(whiteList, to);
    }

    function addWhitelist(address[] memory _address) external onlyOwner {
        for (uint256 i = 0; i < _address.length; i++) {
            EnumerableSet.add(whiteList, _address[i]);
        }
    }

    function removeWhitelist(address[] memory _address) external onlyOwner {
        for (uint256 i = 0; i < _address.length; i++) {
            EnumerableSet.remove(whiteList, _address[i]);
        }
    }

    function getV3TradeType(address from, address to, uint256 amount) public view returns (bool isBuy, bool isSell) {
        bool isLiquidityOperation = (msg.sender == V3_POSITION_MANAGER);
        if (isLiquidityOperation) {
            return (false, false);
        }

        if (checkIsPool(from)) {
            isBuy = true;
        } else if (checkIsPool(to)) {
            isSell = true;
        }
    }

    function checkIsPool(address _maybePool) public view returns (bool) {
        try this._checkIsPool(_maybePool) returns (bool isPool) {
            return isPool;
        } catch {
            return false;
        }
    }

    function _checkIsPool(address _maybePool) public view returns (bool) {
        if (_maybePool.code.length == 0) {
            return false;
        }
        // Attempt to call the factory() method to determine whether it is a PancakeSwap V3 pool
        // Although smart wallets have code.length > 0, they do not have the factory() method, so this will return false
        try IPancakeV3Pool(_maybePool).factory() returns (address factoryAddress) {
            return factoryAddress == V3_FACTORY;
        } catch {
            return false;
        }
    }

    /**
     * @dev Returns token decimals
     * @return Token decimals (6 decimal places)
     */
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    /**
     * @dev Get CMT balance of specified address
     * @param _address Address to query
     * @return CMT balance of the address
     */
    function cmtBalance(address _address) external view returns (uint256) {
        return balanceOf(_address);
    }

    /**
     * @dev Set DAO reward pool address
     * @param _stakingManager Staking manager address
     */
    function setStakingManager(address _stakingManager) external onlyOwner {
        stakingManager = _stakingManager;
        emit SetStakingManager(_stakingManager);
    }

    function setTradeFee(ChooseMeTradeFee memory _tradeFee) external onlyOwner {
        tradeFee = _tradeFee;
    }

    function setProfitFee(ChooseMeProfitFee memory _profitFee) external onlyOwner {
        profitFee = _profitFee;
    }

    /**
     * @dev Set all pool addresses
     * @param _pool Struct containing all pool addresses
     */
    function setPoolAddress(ChooseMePool memory _pool) external onlyOwner {
        _beforeAllocation();
        _beforePoolAddress(_pool);
        cmPool = _pool;
        emit SetPoolAddress(_pool);
    }

    /**
     * @dev Execute token pool allocation, minting tokens to each pool according to predefined ratios
     * @notice Can only be executed once. Allocation ratios: Node Pool 20%, DAO Reward 60%, Airdrop 6%, Tech Rewards 5%, Ecosystem 4%, Founding Strategy 2%, Marketing Development 3%
     */
    function poolAllocate() external onlyOwner {
        _beforeAllocation();
        _mint(cmPool.nodePool, (MaxTotalSupply * 2) / 10); // 20% of total supply
        _mint(cmPool.daoRewardPool, (MaxTotalSupply * 6) / 10); // 60% of total supply
        _mint(cmPool.airdropPool, (MaxTotalSupply * 6) / 100); // 6% of total supply
        _mint(cmPool.techRewardsPool, (MaxTotalSupply * 5) / 100); // 5% of total supply
        _mint(cmPool.ecosystemPool, (MaxTotalSupply * 4) / 100); // 4% of total supply
        _mint(cmPool.foundingStrategyPool, (MaxTotalSupply * 2) / 100); // 2% of total supply
        _mint(cmPool.marketingDevelopmentPool, (MaxTotalSupply * 3) / 100); // 3% of total supply
        isAllocation = true;
    }

    /**
     * @dev Burn tokens of specified user (only callable by DAO reward pool)
     * @param user User address whose tokens to burn
     * @param _amount Amount of tokens to burn
     */
    function burn(address user, uint256 _amount) external onlyStakingManager {
        _burn(user, _amount);
        _lpBurnedTokens += _amount;
        emit Burn(_amount, totalSupply());
    }

    /**
     * @dev Get current total supply of CMT tokens
     * @return Current total supply
     */
    function CmtTotalSupply() external view returns (uint256) {
        return totalSupply();
    }

    // ==================== internal function =============================
    /**
     * @dev Pre-allocation check, ensures allocation happens only once
     */
    function _beforeAllocation() internal virtual {
        require(!isAllocation, "ChooseMeToken _beforeAllocation:Fishcake is already allocate");
    }

    /**
     * @dev Validation before setting pool addresses, ensures all pool addresses are set
     * @param _pool Pool address struct to validate
     */
    function _beforePoolAddress(ChooseMePool memory _pool) internal virtual {
        require(_pool.nodePool != address(0), "ChooseMeToken _beforeAllocation:Missing allocate bottomPool address");
        require(
            _pool.daoRewardPool != address(0), "ChooseMeToken _beforeAllocation:Missing allocate daoRewardPool address"
        );
        require(_pool.airdropPool != address(0), "ChooseMeToken _beforeAllocation:Missing allocate airdropPool address");
        require(
            _pool.techRewardsPool != address(0),
            "ChooseMeToken _beforeAllocation:Missing allocate techRewardsPool address"
        );
        require(
            _pool.ecosystemPool != address(0), "ChooseMeToken _beforeAllocation:Missing allocate EcosystemPool address"
        );
        require(
            _pool.foundingStrategyPool != address(0),
            "ChooseMeToken _beforeAllocation:Missing allocate foundingStrategyPool address"
        );
        require(
            _pool.marketingDevelopmentPool != address(0),
            "ChooseMeToken _beforeAllocation:Missing allocate marketingDevelopmentPool address"
        );
    }
}

