pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title SaleManager 
 * @notice 销售管理模块, 处理白名单, 销售状态,价格
 */
contract SaleManager is Initializable, OwnableUpgradeable{

    enum SalePhase{
        NotStarted,    // 未开始
        Whitelist,     // 白名单阶段
        Public         // 公售阶段
    }

    uint256 public maxPerWallet; //公售阶段钱包最大购买次数
    uint256 public constant whitelistMaxMint = 3; // 白名单阶段钱包的最大购买次数

    bool public saleActive; //是否开始
    uint256 public price;
    SalePhase public currentPhase;
    mapping(address => bool) public whitelist;
    mapping(address => uint256) public whitelistMinted; //每个钱包购买nft的数量


    event SalePhaseChanged(SalePhase salePhase);
    event PriceUpdated(uint256 indexed price);
    event MaxPerWalletUpdated(uint256 indexed max);
    event WhitelistAdded(address[] addresses);
    event WhitelistRemoved(address[] addresses);
    event WhitelistMinted(address indexed user, uint256 count);


    function initialize(uint256 _price, uint256 _maxPerWallet) public initializer{
        __Ownable_init(msg.sender);
        saleActive = false;
        price = _price;
        maxPerWallet = _maxPerWallet;
        currentPhase = SalePhase.NotStarted;
    }

    //设置销售状态
    function setSaleActive(bool _active) external onlyOwner{
        saleActive = _active;
    }

    //设置销售阶段
    function setSalePhase(SalePhase _salePhase) external onlyOwner{
        currentPhase = _salePhase;
        saleActive = (_salePhase != SalePhase.NotStarted);
        emit SalePhaseChanged(currentPhase);
    }

        /**
     * @dev 设置价格
     */
    function setPrice(uint256 _price) external onlyOwner {
        price = _price;
        emit PriceUpdated(_price);
    }


     /**
     * @dev 设置每个钱包最大购买数
     */
    function setMaxPerWallet(uint256 _max) external onlyOwner {
        maxPerWallet = _max;
        emit MaxPerWalletUpdated(_max);
    }

     /**
     * @dev 添加白名单
     */
    function addToWhitelist(address[] memory addresses) external onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            whitelist[addresses[i]] = true;
        }
        emit WhitelistAdded(addresses);
    }

    /**
     * @dev 移除白名单
     */
    function removeFromWhitelist(address[] memory addresses)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < addresses.length; i++) {
            whitelist[addresses[i]] = false;
        }
        emit WhitelistRemoved(addresses);
    }

      /**
     * @dev 检查是否可以购买
     */
    function canPurchase(
        address user,
        uint256 userBalance,
        uint256 payment
    ) external view returns (bool, string memory) {
        if (!saleActive) {
            return (false, "Sale not active");
        }
        if (payment < price) {
            return (false, "Insufficient payment");
        }
        if (userBalance >= maxPerWallet) {
            return (false, "Max per wallet reached");
        }
        if (currentPhase == SalePhase.Whitelist) {
            if (!whitelist[user]) {
                return (false, "Not whitelisted");
            }
            if (whitelistMinted[user] >= whitelistMaxMint) {
                return (false, "Whitelist mint limit reached");
            }
        }
        return (true, "");
    }

    /**
     * @dev 记录白名单购买
     */
    function recordWhitelistPurchase(address user) external {
        if (currentPhase == SalePhase.Whitelist) {
            whitelistMinted[user]++;
            emit WhitelistMinted(user, whitelistMinted[user]);
        }
    }


}