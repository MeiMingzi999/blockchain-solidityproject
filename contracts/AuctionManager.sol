pragma solidity ^0.8.0;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {PriceFeedHandler} from "./handlers/PriceFeedHandler.sol";

/**
 * @title 拍卖合约
 * @author 
 * @notice 
 */
contract AuctionManager is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardTransient {

    enum AuctionStatus {
        NotExist,   // 拍卖不存在
        Ongoing,    // 拍卖进行中，可以出价
        Ended       // 拍卖结束，可以结算
    }

    struct Auction {
        uint256 tokenId;          // 拍卖的NFT的tokenId
        address nftContract;       // NFT合约地址（兼容你的盲盒NFT）
        address seller;            // 卖家（上架人）
        uint256 reservePriceUSD;   // 底价，单位：1e18 USD
        uint256 startTime;        // 拍卖开始时间戳
        uint256 endTime;          // 拍卖结束时间戳
        address highestBidder;     // 当前最高出价人
        uint256 highestBidUSD;     // 当前最高出价（美元，1e18）
        address bidToken;      // 出价使用的代币：address(0)代表ETH，其他是ERC20
        uint256 bidTokenAmount;// 原始出价数量（wei / erc20单位）
        AuctionStatus status;      // 拍卖状态
    }

    mapping(uint256 => Auction) public auctions; // key是actionId
    uint256 public auctionIdCounter;
    PriceFeedHandler public priceFeedHandler;

    event AuctionCreated(uint256 indexed auctionId, address indexed seller, uint256 tokenId, uint256 reservePriceUSD, uint256 endTime);
    event BidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 bidUSD);
    event AuctionSettled(uint256 indexed auctionId, address winner, address seller, uint256 finalUSD);

    function initialize(address _priceFeedHandler) external initializer {
        __Ownable_init(msg.sender);
        // 绑定预言机合约
        priceFeedHandler = PriceFeedHandler(_priceFeedHandler);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev 动态手续费：成交额越高，手续费比例越低
     * 返回 手续费基数，分母10000；比如 500 = 5%
     * 规则示例：
     *  <1000USD → 5%
     *  1000~10000USD →3%
     *  >10000USD →1%
     */
    function getFeeRate(uint256 amountUSD) public pure returns (uint256 feeBasis) {
        if (amountUSD < 1000 * 1e18) {
            feeBasis = 500; // 5%
        } else if (amountUSD < 10000 * 1e18) {
            feeBasis = 300; // 3%
        } else {
            feeBasis = 100; //1%
        }
    }


    /**
     * 创建拍卖
     * @param nftContract nft合约地址
     * @param tokenId nft的tokenId
     * @param reservePriceUSD 底价
     * @param duration 持续时间
     */
    function createAuction(address nftContract, uint256 tokenId, uint256 reservePriceUSD, uint256 duration) external nonReentrant {
        IERC721 nft = IERC721(nftContract);
        //检查调用者是否是本人
        require(nft.ownerOf(tokenId) == msg.sender,"Auction: not nft owner");
        //检查是否授权(全部授权或者单个nft授权)
        require(nft.isApprovedForAll(msg.sender, address(this)) || nft.getApproved(tokenId) == address(this),"Auction: not approved");
        // 底价不能为0
        require(reservePriceUSD > 0, "Auction: reserve price zero");
        // 时长不能为0
        require(duration > 0, "Auction: duration zero");

        uint256 auctionId = auctionIdCounter;
        auctionIdCounter++;

        auctions[auctionId] = Auction({
            tokenId: tokenId,
            nftContract: nftContract,
            seller: msg.sender,
            reservePriceUSD: reservePriceUSD,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            highestBidder: address(0),
            highestBidUSD: 0,
            bidToken:address(0),
            bidTokenAmount:0,
            status: AuctionStatus.Ongoing
        });

        // 把NFT转移到拍卖合约托管
        nft.safeTransferFrom(msg.sender, address(this), tokenId);

        emit AuctionCreated(auctionId, msg.sender, tokenId, reservePriceUSD, block.timestamp + duration);

    }


    /**
     * 使用ETH出价
     * @param auctionId 拍卖id
     */
    function bidETH(uint256 auctionId) external payable nonReentrant{

        Auction storage auc = auctions[auctionId];
        // 校验拍卖状态：必须进行中
        require(auc.status == AuctionStatus.Ongoing, "Auction: auction not ongoing");
        // 校验时间：没到结束时间
        require(block.timestamp < auc.endTime, "Auction: auction ended");
        // 不能自己出价拍自己的NFT
        require(msg.sender != auc.seller, "Auction: seller cannot bid");

        //换算成USD
        uint256 bidUSD = priceFeedHandler.calcTokenAmountToUSD(address(0), msg.value, 18);

        // 出价 >= 底价
        require(bidUSD >= auc.reservePriceUSD, "Auction: lower than reserve");
        // 出价 > 当前最高出价
        require(bidUSD > auc.highestBidUSD, "Auction: bid not higher");
        //把上一个最高者退款
        if(auc.highestBidder != address(0)){
            uint256 refundWei = (auc.highestBidUSD * 10 ** 18) / priceFeedHandler.getTokenUnitPriceUSD(address(0));
            payable(auc.highestBidder).transfer(refundWei);
        }

        // 更新最高出价信息
        auc.highestBidder = msg.sender;
        auc.highestBidUSD = bidUSD;
        auc.bidToken = address(0);
        auc.bidTokenAmount = msg.value;

        emit BidPlaced(auctionId, msg.sender, bidUSD);
    }


    /**
     * @dev 使用ERC20代币出价（如USDC）
     * @param auctionId 拍卖ID
     * @param token ERC20代币地址
     * @param amount ERC20代币数量
     */
    function bidERC20(uint256 auctionId, address token, uint256 amount) external nonReentrant {
        Auction storage auc = auctions[auctionId];
        require(auc.status == AuctionStatus.Ongoing, "Auction: auction not ongoing");
        require(block.timestamp < auc.endTime, "Auction: auction ended");
        require(msg.sender != auc.seller, "Auction: seller cannot bid");
        require(amount > 0, "Auction: bid amount zero");

        IERC20Metadata erc20 = IERC20Metadata(token);
        // 读取代币小数位数
        uint8 decimals = erc20.decimals();
        // 预言机换算成USD
        uint256 bidUSD = priceFeedHandler.calcTokenAmountToUSD(token, amount, decimals);
        require(bidUSD >= auc.reservePriceUSD, "Auction: lower than reserve");
        require(bidUSD > auc.highestBidUSD, "Auction: bid not higher");

        // 退回上一个出价人的ERC20
        if (auc.highestBidder != address(0)) {
            uint256 refundAmount = (auc.highestBidUSD * (10 ** decimals)) / priceFeedHandler.getTokenUnitPriceUSD(token);
            erc20.transfer(auc.highestBidder, refundAmount);
        }

        // 把当前出价人的代币转入拍卖合约托管
        erc20.transferFrom(msg.sender, address(this), amount);

        auc.highestBidder = msg.sender;
        auc.highestBidUSD = bidUSD;
        auc.bidToken = token;
        auc.bidTokenAmount = amount;

        emit BidPlaced(auctionId, msg.sender, bidUSD);
    }

    /**
     * @dev 拍卖结束后结算
     * 流拍：NFT还给卖家；成交：NFT给赢家，扣手续费，资金给卖家
     */
    function settleAuction(uint256 auctionId) external nonReentrant {
        Auction storage auc = auctions[auctionId];
        require(auc.status == AuctionStatus.Ongoing, "Auction: wrong status");
        require(block.timestamp >= auc.endTime, "Auction: auction not end yet");
        // 修改状态为已结束
        auc.status = AuctionStatus.Ended;

        IERC721 nft = IERC721(auc.nftContract);

        // 流拍，没有人出价
        if (auc.highestBidder == address(0)) {
            // NFT还给卖家
            nft.safeTransferFrom(address(this), auc.seller, auc.tokenId);
            return;
        }

        // 成交，计算手续费
        uint256 feeBasis = getFeeRate(auc.highestBidUSD);
        uint256 feeTokenAmount = (auc.bidTokenAmount * feeBasis) / 10000;
        uint256 sellerReceiveTokenAmount = auc.bidTokenAmount - feeTokenAmount;

        // NFT转给最高出价者
        nft.safeTransferFrom(address(this), auc.highestBidder, auc.tokenId);

        //给卖家结算
        if(auc.bidToken == address(0)){
            payable(auc.seller).call{value: sellerReceiveTokenAmount}("");
        }else{
            IERC20 erc20 = IERC20(auc.bidToken);
            erc20.transfer(auc.seller, sellerReceiveTokenAmount);
        }

        emit AuctionSettled(auctionId, auc.highestBidder, auc.seller, auc.highestBidUSD);
    }
}