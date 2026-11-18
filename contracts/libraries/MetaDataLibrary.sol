pragma solidity ^0.8.0;
import "./RarityLibrary.sol";

/**
 * @title MetaDataLibrary
 * @author 构建tokenIdURI
 * @notice 供前端展示使用
 */
library MetaDataLibrary{

    /**
     *  为已揭晓的盲盒构建URI
     * @param baseURI 基础URI
     * @param tokenId tokenId
     * @param rarity 稀有度
     */
    function buildTokenURI(string memory baseURI, uint256 tokenId,RarityLibrary.Rarity rarity ) internal pure returns (string memory tokenURI){
        return string(abi.encodePacked(baseURI ,"/",RarityLibrary.rarityToString(rarity),"/",tostring(tokenId),".json"));
    }

    /**
     * 为未揭晓的盲盒提供统一URI
     * @param baseURI baseURI
     */
    function buildBlindBoxURI(string memory baseURI) internal pure returns (string memory){
        return string(abi.encodePacked(baseURI,"/bindbox.json"));
    }

     /**
     * @dev 将uint256转换为字符串, 先把每个数字查分
     * @param value 数值
     * @return 字符串表示
     */
    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

      /**
     * @dev 拼接URI路径
     * @param parts URI部分数组
     * @return 拼接后的完整URI
     */
    function concatenateURI(string[] memory parts)
        internal
        pure
        returns (string memory)
    {
        bytes memory result;
        for (uint256 i = 0; i < parts.length; i++) {
            result = abi.encodePacked(result, parts[i]);
        }
        return string(result);
    }


}