pragma solidity ^0.8.0;
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract PriceFeedHandler{
    //token代表 feed合约地址, address(0)代表ETH,  key是代币地址, value是喂价合约接口实例
    mapping(address => AggregatorV3Interface) public tokenPriceFeed;
    // 事件：管理员绑定代币和预言机喂价地址
    event FeedSet(address indexed token, address indexed feed);

    /**
     * 设置代币对应预言机feed
     * @param token 代币地址
     * @param feed 喂价合约接口实例,不同网络地址不一样
     */
    function setFeed(address token,address feed) external {
        tokenPriceFeed[token] = AggregatorV3Interface(feed);
        emit FeedSet(token, feed);

    }

    /**
     * 获取单位代币对应的美元价格,返回 1e18精度的USD
     * @param token 代币类型
     */
    function getTokenUnitPriceUSD(address token) public view returns (uint256 pricePerTokenUSD){
        AggregatorV3Interface feed = tokenPriceFeed[token];
        require(address(feed) != address(0), "PriceFeedHandler: feed not exists");

        // 调用Chainlink标准方法拿价格数据
        (
            uint80 roundId,        // 价格轮次ID
            int256 answer,         // 核心：价格（8位小数）
            uint256 startedAt,     // 本轮开始时间
            uint256 updatedAt,    // 价格最后更新时间
            uint80 answeredInRound // 本轮生效轮次
        ) = feed.latestRoundData();
        
        // 安全校验：价格不能<=0
        require(answer > 0, "PriceFeedHandler: invalid price <= 0");
        // 安全校验：价格轮次有效，防止过期脏数据
        require(answeredInRound >= roundId, "PriceFeedHandler: stale price");
        // 安全校验：价格更新时间不为0
        require(updatedAt != 0, "PriceFeedHandler: round incomplete");

        // answer是8位小数， *1e10 转换成18位小数
        pricePerTokenUSD = uint256(answer) * 1e10;

    }

    /**
     * @dev 核心函数：输入代币数量，算出这笔钱等价多少美元
     * @param token 0=ETH，其他ERC20
     * @param amount 代币原生数量（wei / erc20 amount）
     * @param decimals 代币本身小数：ETH=18，USDC=6
     * @return usdValue 等价美元，1e18精度
     */
    function calcTokenAmountToUSD(
        address token,
        uint256 amount,
        uint8 decimals
    ) external view returns (uint256 usdValue) {
        // 1单位代币多少美元
        uint256 unitPrice = getTokenUnitPriceUSD(token);
        // 公式：总美元 = 数量 * 单价 / 代币小数基数
        usdValue = (amount * unitPrice) / (10 ** decimals);
    }
    

}
