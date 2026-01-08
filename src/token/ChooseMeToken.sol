// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin-upgrades/contracts/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-upgrades/contracts/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

import "../interfaces/staking/pancake/IPancakeV3Pool.sol";
import "./ChooseMeTokenStorage.sol";

contract ChooseMeToken is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    OwnableUpgradeable,
    ChooseMeTokenStorage
{
    event SetStakingManager(address indexed stakingManager);
    event SetPoolAddress(chooseMePool indexed pool);

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
    function initialize(address _owner, address _stakingManager) public initializer {
        require(_owner != address(0), "ChooseMeToken initialize: _owner can't be zero address");
        __ERC20_init(NAME, SYMBOL);
        __ERC20Burnable_init();
        __Ownable_init(_owner);
        _transferOwnership(_owner);
        stakingManager = _stakingManager;
        emit SetStakingManager(_stakingManager);
    }

    function _update(address from, address to, uint256 value) internal override {
        // Check if this is a liquidity operation (add/remove liquidity)
        // When adding/removing liquidity, msg.sender is the Position Manager, not the pool
        // We should NOT charge fees for liquidity operations
        bool isLiquidityOperation = (msg.sender == POSITION_MANAGER);

        // Only charge fees if:
        // 1. It's NOT a liquidity operation, AND
        // 2. Either sender or recipient is a pool
        if (!isLiquidityOperation) {
            if ((checkIsPool(from) || checkIsPool(to))) {
                uint256 every = value / 10000;

                uint256 nodeFee = every * 50; // 0.5 %
                super._update(from, cmPool.daoRewardPool, nodeFee);

                uint256 clusterFee = every * 50; // 0.5 %
                super._update(from, cmPool.daoRewardPool, clusterFee);

                uint256 marketFee = every * 50; // 0.5 %
                super._update(from, cmPool.marketingDevelopmentPool, marketFee);

                uint256 techFee = every * 100; // 1 %
                super._update(from, cmPool.techRewardsPool, techFee);

                uint256 subFee = every * 50; // 0.5 %
                super._update(from, cmPool.subTokenPool, subFee);

                value -= nodeFee + clusterFee + marketFee + techFee + subFee;
            }
        }

        super._update(from, to, value);
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
            return factoryAddress == factory;
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
     * @param _stakingManager
     */
    function setStakingManager(address _stakingManager) external onlyOwner {
        stakingManager = _stakingManager;
        emit SetStakingManager(_stakingManager);
    }

    /**
     * @dev Set factory address for pool verification
     * @param _factory PancakeSwap V3 factory address
     */
    function setFactory(address _factory) external onlyOwner {
        require(_factory != address(0), "ChooseMeToken setFactory: factory can't be zero address");
        factory = _factory;
    }

    /**
     * @dev Set all pool addresses
     * @param _pool Struct containing all pool addresses
     */
    function setPoolAddress(chooseMePool memory _pool) external onlyOwner {
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
    function _beforePoolAddress(chooseMePool memory _pool) internal virtual {
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

