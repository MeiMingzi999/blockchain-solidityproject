pragma solidity ^0.8.0;

//盲盒存储结构
library BlindBoxStorage{
    struct BlindBox{
        bool purchased; //是否已经购买
        bool revealed; //是否揭示
        uint256 purchaseTime; //购买时间
        uint256 revealTime; //揭示时间
    }

    //创建盲盒
    function createBlindBox() internal view returns (BlindBox memory){
        return BlindBox({
            purchased: true,
            revealed: false,
            purchaseTime: block.timestamp,
            revealTime: 0
        });
    }

    //标记为以揭示
    function markAsRevealed(BlindBox storage box) internal {
        box.revealed = true;
        box.revealTime = block.timestamp;
    }

     /**
     * @dev 获取盲盒状态
     */
    function getStatus(BlindBox storage box)
        internal
        view
        returns (
            bool purchased,
            bool revealed,
            uint256 purchaseTime,
            uint256 revealTime
        )
    {
        return (
            box.purchased,
            box.revealed,
            box.purchaseTime,
            box.revealTime
        );
    }

}