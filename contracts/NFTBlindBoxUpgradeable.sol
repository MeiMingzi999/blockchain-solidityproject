pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import "./libraries/RarityLibrary.sol";
import "./libraries/MetaDataLibrary.sol";
import "./libraries/BlindBoxStorage.sol";
import "./modules/SaleManager.sol";
import "./handlers/VRFHandler.sol";
import "./interfaces/IVRFHandler.sol"; // 导入 IVRFHandler 以使用 IVRFCallback 接口


contract NFTBlindBoxUpgradeable is
    Initializable,
    ERC721Upgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardTransient,
    IVRFCallback
{
    using RarityLibrary for RarityLibrary.Rarity;
    using BlindBoxStorage for BlindBoxStorage.BlindBox;
    using MetaDataLibrary for string;

    uint256 public totalSupply; //总供应量
    uint256 public maxSupply; //最大供应量
    string private _baseTokenURI; // 盲盒未开时固定URI
    mapping(uint256 => BlindBoxStorage.BlindBox) tokenBlindBox; // tokenID => 盲盒
    mapping(uint256 => RarityLibrary.Rarity) tokenRarity; //tokenId => 稀有度
    mapping(uint256 => string) _tokenURIS; //盲盒的 tokenId => URI
    mapping(address => uint256[]) userTokenIds; //用户购买的盲盒

    SaleManager public saleManager;
    VRFHandler public vrfHandler;

    //购买盲盒事件
    event BoxPurchased(address indexed buyer, uint256 indexed tokenId);
    //稀有度
    event RarityAssigned(
        uint256 indexed tokenId,
        RarityLibrary.Rarity rarity
    );
    //揭示盲盒
    event BoxRevealed(uint256 indexed tokenId, RarityLibrary.Rarity rarity);




    /**
     * @dev 初始化函数，在代理部署时调用
     * @param name NFT名称
     * @param symbol NFT符号
     * @param _maxSupply 最大供应量
     * @param saleManagerAddress SaleManager模块地址
     * @param vrfHandlerAddress VRFHandler模块地址
     * @param baseURI 基础URI
     * @notice 价格参数已移除，价格由SaleManager模块管理
     */
    function initialize(
        string memory name,
        string memory symbol,
        uint256 _maxSupply,
        uint256, // 价格参数已移除，价格由SaleManager模块管理
        address saleManagerAddress,
        address vrfHandlerAddress,
        string memory baseURI
    ) public initializer {
        __ERC721_init(name, symbol);
        __Ownable_init(msg.sender);
        //OZ5.x 新版本不需要
        // __ReentrancyGuard_init();
        // __UUPSUpgradeable_init();

        maxSupply = _maxSupply;
        saleManager = SaleManager(saleManagerAddress);
        vrfHandler = VRFHandler(vrfHandlerAddress);
        _baseTokenURI = baseURI;

        // 初始化销售管理器（如果未初始化）
        if (saleManager.price() == 0) {
            // SaleManager应该已经初始化，这里只是验证
        }
    }

    /**
     * @dev 授权升级函数，只有owner可以升级
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    //购买-铸造盲盒
    function purchaseBox() external payable virtual nonReentrant{
        //检查购买力
        uint256 mintNum = balanceOf(msg.sender); //用户已经mint的盲盒数量

        //只有公售阶段或者白名单阶段 在白名单内 才可以买
        (bool canBuy,string memory reason) = saleManager.canPurchase(msg.sender,mintNum,msg.value);
        require(canBuy,reason);
        require(totalSupply < maxSupply,"sold out");

        uint256 tokenId = totalSupply;
        totalSupply++;
        //铸造NFT
        _safeMint(msg.sender, tokenId);

        //获取requestId
        vrfHandler.requestRandomness(tokenId,address(this));

        tokenBlindBox[tokenId] = BlindBoxStorage.createBlindBox();
        userTokenIds[msg.sender].push(tokenId); 
        //记录日志, 只有白名单才会记录
        saleManager.recordWhitelistPurchase(msg.sender);    
        emit BoxPurchased(msg.sender, tokenId);

    }

      /**
     * @dev VRF回调函数，由VRFHandler调用
     * @notice 实现IVRFCallback接口，由VRFHandler的fulfillRandomWords触发
     * @param tokenId token ID
     * @param randomness 随机数
     */
     function handleVRFCallback(
        uint256, // requestId - 保留用于接口兼容性，实际未使用, requestId在VRFHandler里面
        uint256 tokenId,
        uint256 randomness
    ) external virtual override {
        //检查是否VRF回调
        require(msg.sender == address(vrfHandler),"Only VRF handler can call");

         // 使用RarityLibrary分配稀有度
        RarityLibrary.Rarity rarity = RarityLibrary.assignRarity(randomness);
        tokenRarity[tokenId] = rarity;
        emit RarityAssigned(tokenId, rarity);

        // 揭示盲盒（内部函数会验证 token 存在）
        revealBox(tokenId);

    }

    /**
     * @dev 揭示盲盒（内部函数）
     * @notice 优化：不在回调中存储完整 URI，改为在 tokenURI() 函数中按需计算，以节省 gas
     */
    function revealBox(uint256 tokenId) internal {
        require(ownerOf(tokenId) != address(0), "Token does not exist");
        require(!tokenBlindBox[tokenId].revealed, "Already revealed");

        // 使用存储库的方法标记为已揭示
        tokenBlindBox[tokenId].markAsRevealed();

        // 优化：不在回调中存储完整 URI，改为在 tokenURI() 中按需计算
        // 这样可以节省大量 gas（存储字符串非常昂贵）
        // URI 会在 tokenURI() 函数中根据 baseURI + rarity + tokenId 按需构建

        RarityLibrary.Rarity rarity = tokenRarity[tokenId];
        emit BoxRevealed(tokenId, rarity);
    }

     /**
     * @dev 查询盲盒状态
     */
    function getBlindBoxStatus(uint256 tokenId)
        public
        view
        returns (
            bool purchased,
            bool revealed,
            RarityLibrary.Rarity rarity
        )
    {
        BlindBoxStorage.BlindBox storage box = tokenBlindBox[tokenId];
        return (
            box.purchased,
            box.revealed,
            box.revealed ? tokenRarity[tokenId] : RarityLibrary.Rarity.Common
        );
    }

    // ============ 元数据管理（使用库）============
    /**
     * @dev 设置基础URI
     */
    function setBaseURI(string memory baseURI) public onlyOwner {
        _baseTokenURI = baseURI;
    }

    /**
     * @dev 设置tokenURI
     */
    function _setTokenURI(uint256 tokenId, string memory uri) internal {
        _tokenURIS[tokenId] = uri;
    }


    /**
     * @dev 获取tokenURI
     * @notice 优化：已揭示的 NFT 按需计算 URI，而不是从 storage 读取，节省 gas
     */
    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(ownerOf(tokenId) != address(0), "Token does not exist");

        // 如果已揭示，按需计算 URI（而不是从 storage 读取，节省 gas）
        if (tokenBlindBox[tokenId].revealed) {
            RarityLibrary.Rarity rarity = tokenRarity[tokenId];
            // 按需构建 URI，避免在 VRF 回调中存储完整字符串
            return MetaDataLibrary.buildTokenURI(
                _baseTokenURI,
                tokenId,
                rarity
            );
        }

        // 未揭示时返回盲盒URI（使用MetadataLibrary）
        return MetaDataLibrary.buildBlindBoxURI(_baseTokenURI);
    }

    // ============ 销售管理（委托给SaleManager）============
    /**
     * @dev 设置价格
     */
    function setPrice(uint256 _price) public onlyOwner {
        saleManager.setPrice(_price);
    }

    /**
     * @dev 设置销售状态
     */
    function setSaleActive(bool _active) public onlyOwner {
        saleManager.setSaleActive(_active);
    }

    /**
     * @dev 设置销售阶段
     */
    function setSalePhase(SaleManager.SalePhase _phase) public onlyOwner {
        saleManager.setSalePhase(_phase);
    }

    /**
     * @dev 设置每个钱包最大购买数
     */
    function setMaxPerWallet(uint256 _max) public onlyOwner {
        saleManager.setMaxPerWallet(_max);
    }

    /**
     * @dev 添加白名单
     */
    function addToWhitelist(address[] memory addresses) public onlyOwner {
        saleManager.addToWhitelist(addresses);
    }

    /**
     * @dev 移除白名单
     */
    function removeFromWhitelist(address[] memory addresses) public onlyOwner {
        saleManager.removeFromWhitelist(addresses);
    }

    /**
     * @dev 获取销售信息
     */
    function getSaleInfo()
        public
        view
        returns (
            bool active,
            SaleManager.SalePhase phase,
            uint256 currentPrice,
            uint256 maxWallet
        )
    {
        return (
            saleManager.saleActive(),
            saleManager.currentPhase(),
            saleManager.price(),
            saleManager.maxPerWallet()
        );
    }

    // ============ VRF配置管理（委托给VRFHandler）============
    /**
     * @dev 更新VRF配置
     */
    function setVRFHandler(address vrfHandlerAddress) public onlyOwner {
        vrfHandler = VRFHandler(vrfHandlerAddress);
    }

    /**
     * @dev 更新销售管理器
     */
    function setSaleManager(address saleManagerAddress) public onlyOwner {
        saleManager = SaleManager(saleManagerAddress);
    }

    // ============ 辅助函数 ============
    /**
     * @dev 提取资金
     */
    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");
        payable(owner()).transfer(balance);
    }

    // ============ 存储间隙（为未来升级预留）============
    uint256[40] private __gap;




}