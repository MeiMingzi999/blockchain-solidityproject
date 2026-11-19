import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
export default buildModule("AuctionModule",(m) => {

    const priceFeedHandler = m.contract("PriceFeedHandler");
    const auctionManager = m.contract("AuctionManager", [priceFeedHandler]);
    return {priceFeedHandler,auctionManager};

})