// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin-upgrades/contracts/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-upgrades/contracts/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";

import "./ChooseMeTokenStorage.sol";


contract ChooseMeToken is Initializable, ERC20Upgradeable, ERC20BurnableUpgradeable, OwnableUpgradeable, ChooseMeTokenStorage {
    event SetDaoRewardPool(address indexed daoRewardPool);
    event SetPoolAddress(chooseMePool indexed pool);

    string private constant NAME = "ChooseMe Coin";
    string private constant SYMBOL = "CMT";

    constructor() {
        _disableInitializers();
    }

    modifier onlyDaoRewardPool() {
        require(
            msg.sender == daoRewardPool,
            "ChooseMeToken onlyDaoRewardPool: Only DaoRewardPool can call this function"
        );
        _;
    }

    function initialize(
        address _owner,
        address _daoRewardPool
    ) public initializer {
        require(
            _owner != address(0),
            "ChooseMeToken initialize: _owner can't be zero address"
        );
        __ERC20_init(NAME, SYMBOL);
        __ERC20Burnable_init();
        __Ownable_init(_owner);
        _transferOwnership(_owner);
        daoRewardPool = _daoRewardPool;
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function cmtBalance(address _address) external view returns (uint256) {
        return balanceOf(_address);
    }

    function setDaoRewardPool(address _daoRewardPool) external onlyOwner {
        daoRewardPool = _daoRewardPool;
        emit SetDaoRewardPool(_daoRewardPool);
    }

    function setPoolAddress(chooseMePool memory _pool) external onlyOwner {
        _beforeAllocation();
        _beforePoolAddress(_pool);
        cmPool = _pool;
        emit SetPoolAddress(_pool);
    }

    function poolAllocate() external onlyOwner {
        _beforeAllocation();
        _mint(cmPool.nodePool, (MaxTotalSupply * 2) / 10); // 20% of total supply
        _mint(cmPool.daoRewardPool, (MaxTotalSupply * 6) / 10); // 60% of total supply
        _mint(cmPool.airdropPool, (MaxTotalSupply * 6 )/ 100); // 6% of total supply
        _mint(cmPool.techRewardsPool, (MaxTotalSupply * 5) / 100); // 5% of total supply
        _mint(cmPool.ecosystemPool, (MaxTotalSupply * 4) / 100); // 4% of total supply
        _mint(cmPool.foundingStrategyPool, (MaxTotalSupply * 2) / 100); // 2% of total supply
        _mint(cmPool.marketingDevelopmentPool, (MaxTotalSupply * 3) / 100); // 3% of total supply
        isAllocation = true;
    }

    function burn(address user, uint256 _amount) external onlyDaoRewardPool {
        _burn(user, _amount);
        _lpBurnedTokens += _amount;
        emit Burn(_amount, totalSupply());
    }

    function CmtTotalSupply() external view returns (uint256) {
        return totalSupply();
    }

    // ==================== internal function =============================
    function _beforeAllocation() internal virtual {
        require(
            !isAllocation,
            "ChooseMeToken _beforeAllocation:Fishcake is already allocate"
        );
    }

    function _beforePoolAddress(chooseMePool memory _pool) internal virtual {
        require(
            _pool.nodePool != address(0),
            "ChooseMeToken _beforeAllocation:Missing allocate bottomPool address"
        );
        require(
            _pool.daoRewardPool != address(0),
            "ChooseMeToken _beforeAllocation:Missing allocate daoRewardPool address"
        );
        require(
            _pool.airdropPool != address(0),
            "ChooseMeToken _beforeAllocation:Missing allocate airdropPool address"
        );
        require(
            _pool.techRewardsPool != address(0),
            "ChooseMeToken _beforeAllocation:Missing allocate techRewardsPool address"
        );
        require(
            _pool.ecosystemPool != address(0),
            "ChooseMeToken _beforeAllocation:Missing allocate EcosystemPool address"
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

