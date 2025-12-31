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

    /**
     * @dev 初始化 ChooseMe 代币合约
     * @param _owner 所有者地址
     * @param _daoRewardPool DAO 奖励池地址
     */
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

    /**
     * @dev 返回代币精度
     * @return 代币精度（6 位小数）
     */
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    /**
     * @dev 获取指定地址的 CMT 余额
     * @param _address 要查询的地址
     * @return 该地址的 CMT 余额
     */
    function cmtBalance(address _address) external view returns (uint256) {
        return balanceOf(_address);
    }

    /**
     * @dev 设置 DAO 奖励池地址
     * @param _daoRewardPool DAO 奖励池地址
     */
    function setDaoRewardPool(address _daoRewardPool) external onlyOwner {
        daoRewardPool = _daoRewardPool;
        emit SetDaoRewardPool(_daoRewardPool);
    }

    /**
     * @dev 设置所有池地址
     * @param _pool 包含所有池地址的结构体
     */
    function setPoolAddress(chooseMePool memory _pool) external onlyOwner {
        _beforeAllocation();
        _beforePoolAddress(_pool);
        cmPool = _pool;
        emit SetPoolAddress(_pool);
    }

    /**
     * @dev 执行代币池分配，按照预定比例向各个池铸造代币
     * @notice 只能执行一次，分配比例：节点池20%, DAO奖励60%, 空投6%, 技术奖励5%, 生态系统4%, 创始策略2%, 市场开发3%
     */
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

    /**
     * @dev 销毁指定用户的代币（仅 DAO 奖励池可调用）
     * @param user 要销毁代币的用户地址
     * @param _amount 要销毁的代币数量
     */
    function burn(address user, uint256 _amount) external onlyDaoRewardPool {
        _burn(user, _amount);
        _lpBurnedTokens += _amount;
        emit Burn(_amount, totalSupply());
    }

    /**
     * @dev 获取 CMT 代币的当前总供应量
     * @return 当前总供应量
     */
    function CmtTotalSupply() external view returns (uint256) {
        return totalSupply();
    }

    // ==================== internal function =============================
    /**
     * @dev 分配前的检查，确保只分配一次
     */
    function _beforeAllocation() internal virtual {
        require(
            !isAllocation,
            "ChooseMeToken _beforeAllocation:Fishcake is already allocate"
        );
    }

    /**
     * @dev 设置池地址前的验证，确保所有池地址已设置
     * @param _pool 要验证的池地址结构体
     */
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

