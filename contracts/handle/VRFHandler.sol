pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import "../interfaces/IVRFHandler.sol";

contract VRFHandler is Initializable,OwnableUpgradeable,IVRFHandler{

    IVRFCoordinatorV2Plus private vrfCoordinator;
    bytes32 private keyHash; //选择Gas Lane
    uint256 private subscriptionId;  //VRF订阅id, 扣款账户
    uint32 private callbackGasLimit;  // 言机调用 `fulfillRandomWords` 的 gas 上限
    uint16 private requestConfirmations; //预言机等待多少个区块确认之后，再生成随机数回调
    uint32 private numWords; //需要多少个随机数
    bool private nativePayment; // VRF v2.5 支持原生代币支付
     // 请求ID到tokenId的映射
    mapping(uint256 => uint256) private requestIdToTokenId;
    // 请求ID到接收回调合约地址的映射
    mapping(uint256 => address) private requestIdToCallback;

    // ============ 事件 ============
    event VRFConfigUpdated(
        address indexed coordinator,
        bytes32 keyHash,
        uint256 subscriptionId
    );

    // ============ 错误 ============
    error OnlyCoordinator();
    error InvalidRequestId();

    // ============ 修饰符 ============
    //vrfCoordinator是 Chainlink VRF 协调器合约,合约自己回调
    modifier onlyCoordinator() {
        if (msg.sender != address(vrfCoordinator)) {
            revert OnlyCoordinator();
        }
        _;
    }

    function initialize(
        address _vrfCoordinator, //VRF调度器合约地址
        bytes32 _keyHash,
        uint256 _subscriptionId, // VRF v2.5 使用 uint256
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        bool _nativePayment // VRF v2.5 支持原生代币支付
    )public initializer{
        //设置合约管理员
        __Ownable_init();
        vrfCoordinator = IVRFCoordinatorV2Plus(_vrfCoordinator);
        subscriptionId = _subscriptionId;
        callbackGasLimit = _callbackGasLimit;
        requestConfirmations = _requestConfirmations;
        numWords = 1;
        nativePayment = _nativePayment;

    }

    /**
     * VRF获取requestID
     * @param tokenId 盲盒的tokenId
     * @param callbackContract 接受回调合约的地址
     */
    function requestRandomness(uint256 tokenId, address callbackContract) 
        external override 
        returns (uint256 requestId){

            VRFV2PlusClient.RandomWordsRequest memory req = VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: nativePayment})
                )
            });
            requestId = vrfCoordinator.requestRandomWords(req);
            requestIdToTokenId[requestId] = tokenId;
            requestIdToCallback[requestId] = callbackContract;

            emit RandomnessRequested(requestId, tokenId);
            
    }

     /**
     * @dev VRF回调函数
     * @param requestId 请求ID
     * @param randomWords 随机数数组
     */
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) external override onlyCoordinator {
        uint256 tokenId = requestIdToTokenId[requestId];
        address callbackContract = requestIdToCallback[requestId];
        
        if (tokenId == 0 || callbackContract == address(0)) {
            revert InvalidRequestId();
        }

        emit RandomnessFulfilled(requestId, tokenId);

        // 调用回调合约
        IVRFCallback(callbackContract).handleVRFCallback(
            requestId,
            tokenId,
            randomWords[0]
        );

        // 清理映射
        delete requestIdToTokenId[requestId];
        delete requestIdToCallback[requestId];
    }

       /**
     * @dev 获取请求对应的tokenId
     * @param requestId 请求ID
     * @return tokenId token ID
     */
    function getTokenIdByRequestId(uint256 requestId)
        external
        view
        override
        returns (uint256)
    {
        return requestIdToTokenId[requestId];
    }

    /**
     * @dev 获取请求对应的回调合约
     * @param requestId 请求ID
     * @return callbackContract 回调合约地址
     */
    function getCallbackContractByRequestId(uint256 requestId)
        external
        view
        override
        returns (address)
    {
        return requestIdToCallback[requestId];
    }


     // ============ 配置管理 ============
    /**
     * @dev 更新VRF配置（VRF v2.5）
     */
    function updateVRFConfig(
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint256 _subscriptionId, // VRF v2.5 使用 uint256
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        bool _nativePayment // VRF v2.5 支持原生代币支付
    ) external onlyOwner {
        vrfCoordinator = IVRFCoordinatorV2Plus(_vrfCoordinator);
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
        callbackGasLimit = _callbackGasLimit;
        requestConfirmations = _requestConfirmations;
        nativePayment = _nativePayment;

        emit VRFConfigUpdated(_vrfCoordinator, _keyHash, _subscriptionId);
    }

    // ============ 查询函数 ============
    function getVRFCoordinator() external view returns (address) {
        return address(vrfCoordinator);
    }

    function getKeyHash() external view returns (bytes32) {
        return keyHash;
    }

    function getSubscriptionId() external view returns (uint256) {
        return subscriptionId;
    }

    function getNativePayment() external view returns (bool) {
        return nativePayment;
    }

    function getCallbackGasLimit() external view returns (uint32) {
        return callbackGasLimit;
    }

    function getRequestConfirmations() external view returns (uint16) {
        return requestConfirmations;
    }




}




