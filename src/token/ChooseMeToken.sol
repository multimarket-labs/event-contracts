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
import {SwapHelper} from "../utils/SwapHelper.sol";
import "./ChooseMeTokenStorage.sol";

contract CurrencyDistributor {
    address owner;
    address currency;

    constructor(address _currency) {
        owner = msg.sender;
        currency = _currency;
        ensure();
    }

    function ensure() public {
        IERC20(currency).approve(owner, ~uint256(0));
    }
}

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

    modifier inSlippageLock() {
        require(!slippageLock, "ChooseMeToken inSlippageLock: Reentrant call detected");
        slippageLock = true;
        _;
        slippageLock = false;
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
        currencyDistributor = address(new CurrencyDistributor(USDT));

        EnumerableSet.add(factories, V2_FACTORY); // PancakeSwap V2 Factory address on BSC

        mainPair = IPancakeFactory(V2_FACTORY).createPair(USDT, address(this));
        emit SetStakingManager(_stakingManager);

        tradeFee = ChooseMeTradeFee({nodeFee: 50, clusterFee: 50, marketFee: 50, techFee: 100, subTokenFee: 50});
        profitFee = ChooseMeProfitFee({nodeFee: 800, clusterFee: 600, marketFee: 400, techFee: 400, subTokenFee: 400});
    }

    /**
     * @dev Override ERC20 transfer function to implement trading fees and profit fees
     * @param from Sender address
     * @param to Recipient address
     * @param value Transfer amount
     * @notice Applies 3% trading fees on buy/sell: 0.5% node, 0.5% cluster, 0.5% marketing, 1% tech, 0.5% sub-token
     * @notice Applies profit fees when selling at profit: 16% normal, 10% node, 5% cluster, 5% marketing, 5% tech, 5% sub-token
     */
    function _update(address from, address to, uint256 value) internal override {
        if (isWhitelisted(from, to) || !isAllocation || slippageLock) {
            super._update(from, to, value);
            return;
        }

        uint256 finallyValue = value;

        (bool isBuy, bool isSell,,,,) = getTradeType(from, to, value, address(this));
        uint256 swapNodeFee;
        uint256 swapClusterFee;
        uint256 swapMarketFee;
        uint256 swapTechFee;
        uint256 swapSubFee;

        // trade slippage fee only for buy/sell
        if (isBuy || isSell) {
            uint256 every = value / 10000;

            swapNodeFee = every * tradeFee.nodeFee;
            swapClusterFee = every * tradeFee.clusterFee;
            swapMarketFee = every * tradeFee.marketFee;
            swapTechFee = every * tradeFee.techFee;
            swapSubFee = every * tradeFee.subTokenFee;

            finallyValue = finallyValue - (swapNodeFee + swapClusterFee + swapMarketFee + swapTechFee + swapSubFee);
            emit TradeSlipage(value, swapNodeFee, swapClusterFee, swapMarketFee, swapTechFee, swapSubFee);
        }

        uint256 profitNodeFee;
        uint256 profitClusterFee;
        uint256 profitMarketFee;
        uint256 profitTechFee;
        uint256 profitSubFee;
        // profit fee only for sell
        // Profit USDT is greater than 0, a profit handling fee will be charged
        (uint256 curUValue, uint256 profit) = getProfit(from, to, finallyValue, isBuy, isSell);
        if (isSell && profit > 0 && curUValue > 0) {
            uint256 everyProfit = (finallyValue * profit) / (curUValue * 10000);

            profitNodeFee = everyProfit * profitFee.nodeFee;
            profitClusterFee = everyProfit * profitFee.clusterFee;
            profitMarketFee = everyProfit * profitFee.marketFee;
            profitTechFee = everyProfit * profitFee.techFee;
            profitSubFee = everyProfit * profitFee.subTokenFee;

            finallyValue =
                finallyValue - (profitNodeFee + profitClusterFee + profitMarketFee + profitTechFee + profitSubFee);
            emit ProfitSlipage(value, profitNodeFee, profitClusterFee, profitMarketFee, profitTechFee, profitSubFee);
        }

        if (profitNodeFee + swapNodeFee + swapClusterFee + profitClusterFee > 0) {
            super._update(from, cmPool.daoRewardPool, profitNodeFee + swapNodeFee + swapClusterFee + profitClusterFee);
        }

        if (swapMarketFee + profitMarketFee > 0) {
            cumulativeSlipage.marketFee += swapMarketFee + profitMarketFee;
        }
        if (swapTechFee + profitTechFee > 0) {
            cumulativeSlipage.techFee += swapTechFee + profitTechFee;
        }
        if (swapSubFee + profitSubFee > 0) {
            cumulativeSlipage.subTokenFee += swapSubFee + profitSubFee;
        }

        if (swapMarketFee + profitMarketFee + swapTechFee + profitTechFee + swapSubFee + profitSubFee > 0) {
            super._update(
                from,
                address(this),
                swapMarketFee + profitMarketFee + swapTechFee + profitTechFee + swapSubFee + profitSubFee
            );
        }
        if (isSell) {
            allocateCumulativeSlipage();
        }

        super._update(from, to, finallyValue);
    }

    function allocateCumulativeSlipage() internal inSlippageLock {
        uint256 marketFee = cumulativeSlipage.marketFee;
        uint256 techFee = cumulativeSlipage.techFee;
        uint256 subFee = cumulativeSlipage.subTokenFee;

        cumulativeSlipage.marketFee = 0;
        cumulativeSlipage.techFee = 0;
        cumulativeSlipage.subTokenFee = 0;

        uint256 totalSlipage = marketFee + techFee + subFee;
        if (totalSlipage == 0 || totalSlipage > balanceOf(address(this))) {
            return;
        }

        uint256 uAmount = SwapHelper.swapV2(V2_ROUTER, address(this), USDT, totalSlipage, currencyDistributor);

        IERC20(USDT).transferFrom(currencyDistributor, cmPool.marketingPool, uAmount * marketFee / totalSlipage);
        IERC20(USDT).transferFrom(currencyDistributor, cmPool.techRewardsPool, uAmount * techFee / totalSlipage);
        IERC20(USDT).transferFrom(currencyDistributor, cmPool.subTokenPool, uAmount * subFee / totalSlipage);

        emit AllocateSlipageU(uAmount, marketFee, techFee, subFee);
    }

    function getProfit(address from, address to, uint256 value, bool isBuy, bool isSell)
        internal
        returns (uint256 curUValue, uint256 profit)
    {
        (uint256 rOther, uint256 rThis,,) = getReserves(mainPair, address(this));
        if (rOther == 0 || rThis == 0) {
            return (0, 0);
        }
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
        uint256 fromUValue = curUValue;
        if (fromUValue > userCost[from]) {
            profit = fromUValue - userCost[from];
            fromUValue = userCost[from];
        }
        userCost[from] -= fromUValue;
    }

    /**
     * @dev Check if address is a special pool address (used for cost basis calculation)
     * @param from Address to check
     * @return True if address is one of the special pool addresses
     */
    function isFromSpecial(address from) internal view returns (bool) {
        return from == cmPool.nodePool || from == cmPool.daoRewardPool || from == cmPool.techRewardsPool
            || from == cmPool.foundingStrategyPool || from == cmPool.marketingPool || from == cmPool.subTokenPool
            || EnumerableSet.contains(marketingPools, from) || EnumerableSet.contains(ecosystemPools, from);
    }

    /**
     * @dev Check if from or to address is whitelisted (exempt from fees)
     * @param from Sender address
     * @param to Recipient address
     * @return True if either address is whitelisted
     */
    function isWhitelisted(address from, address to) public view returns (bool) {
        return EnumerableSet.contains(whiteList, from) || EnumerableSet.contains(whiteList, to);
    }

    /**
     * @dev Add addresses to whitelist (exempt from trading fees)
     * @param _address Array of addresses to add to whitelist
     */
    function addWhitelist(address[] memory _address) external onlyOwner {
        for (uint256 i = 0; i < _address.length; i++) {
            EnumerableSet.add(whiteList, _address[i]);
        }
    }

    /**
     * @dev Remove addresses from whitelist
     * @param _address Array of addresses to remove from whitelist
     */
    function removeWhitelist(address[] memory _address) external onlyOwner {
        for (uint256 i = 0; i < _address.length; i++) {
            EnumerableSet.remove(whiteList, _address[i]);
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

    /**
     * @dev Set trading fee percentages (in basis points, 100 = 1%)
     * @param _tradeFee Struct containing all trading fee percentages
     */
    function setTradeFee(ChooseMeTradeFee memory _tradeFee) external onlyOwner {
        tradeFee = _tradeFee;
    }

    /**
     * @dev Set profit fee percentages (in basis points, 100 = 1%)
     * @param _profitFee Struct containing all profit fee percentages
     */
    function setProfitFee(ChooseMeProfitFee memory _profitFee) external onlyOwner {
        profitFee = _profitFee;
    }

    /**
     * @dev Set all pool addresses
     * @param _pool Struct containing all pool addresses
     */
    function setPoolAddress(
        ChooseMePool memory _pool,
        address[] memory _marketingDevelopmentPools,
        address[] memory _ecosystemPools
    ) external onlyOwner {
        _beforeAllocation();
        _beforePoolAddress(_pool);
        cmPool = _pool;
        for (uint256 i = 0; i < _marketingDevelopmentPools.length; i++) {
            EnumerableSet.add(marketingPools, _marketingDevelopmentPools[i]);
        }
        for (uint256 i = 0; i < _ecosystemPools.length; i++) {
            EnumerableSet.add(ecosystemPools, _ecosystemPools[i]);
        }
        emit SetPoolAddress(_pool);
    }

    /**
     * @dev Execute token pool allocation, minting tokens to each pool according to predefined ratios
     * @notice Can only be executed once. Allocation ratios: Node Pool 20%, DAO Reward 60%, Airdrop 6%, Tech Rewards 5%, Ecosystem 4%, Founding Strategy 2%, Marketing Development 3%
     */
    function poolAllocate() external onlyOwner {
        _beforeAllocation();
        _mint(cmPool.nodePool, (MaxTotalSupply * 20) / 100); // 20% of total supply
        _mint(cmPool.daoRewardPool, (MaxTotalSupply * 60) / 100); // 60% of total supply
        _mint(cmPool.airdropPool, (MaxTotalSupply * 6) / 100); // 6% of total supply
        _mint(cmPool.techRewardsPool, (MaxTotalSupply * 5) / 100); // 5% of total supply
        _mint(cmPool.foundingStrategyPool, (MaxTotalSupply * 2) / 100); // 2% of total supply
        // 4% of total supply
        address[] memory ecosystemPoolsArray = EnumerableSet.values(ecosystemPools);
        uint256 ecosystemPoolEvery = (MaxTotalSupply * 4) / 100 / ecosystemPoolsArray.length;
        for (uint256 index = 0; index < ecosystemPoolsArray.length; index++) {
            _mint(ecosystemPoolsArray[index], ecosystemPoolEvery);
        }
        // 3% of total supply
        address[] memory marketingPoolsArray = EnumerableSet.values(marketingPools);
        uint256 marketingDevelopmentPoolEvery = (MaxTotalSupply * 3) / 100 / marketingPoolsArray.length;
        for (uint256 index = 0; index < marketingPoolsArray.length; index++) {
            _mint(marketingPoolsArray[index], marketingDevelopmentPoolEvery);
        }
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
            _pool.foundingStrategyPool != address(0),
            "ChooseMeToken _beforeAllocation:Missing allocate foundingStrategyPool address"
        );
        require(
            _pool.marketingPool != address(0), "ChooseMeToken _beforeAllocation:Missing allocate marketingPool address"
        );
    }

    function quote(uint256 amount) public view returns (uint256) {
        (uint256 rOther, uint256 rThis,,) = getReserves(mainPair, address(this));
        return IPancakeRouter01(V2_ROUTER).getAmountOut(amount, rThis, rOther);
    }
}

