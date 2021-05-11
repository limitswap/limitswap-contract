const TestCoinA = artifacts.require("testCoinA");
const TestCoinB = artifacts.require("testCoinB");
const LimitswapPair = artifacts.require("LimitswapPair");
const LimitswapTradeCore = artifacts.require("LimitswapTradeCore");
const LimitswapFactory = artifacts.require("LimitswapFactory");
const TickMath = artifacts.require("TickMath");
const WETH = artifacts.require("WETH");
const LimitswapRouter = artifacts.require("LimitswapRouter");

module.exports = function(deployer, network) {
  if (network == "test") {
    deployer.deploy(TickMath).then(function() {
      deployer.link(TickMath, LimitswapPair);
      deployer.link(TickMath, LimitswapTradeCore);
      return deployer.deploy(TestCoinA).then(function() {
        return deployer.deploy(TestCoinB).then(function() {
            return deployer.deploy(LimitswapTradeCore).then(function() {
                return deployer.deploy(LimitswapPair, LimitswapTradeCore.address).then(function() {
                  return deployer.deploy(LimitswapFactory, LimitswapPair.address).then(function(){
                    return deployer.deploy(WETH).then(function(){
                      return deployer.deploy(LimitswapRouter, LimitswapFactory.address, WETH.address);
                    });
                  });
                });
            });
        });
      });
    });
  }
  else if (network == "ropsten") {
    deployer.deploy(LimitswapTradeCore).then(function() {
      return deployer.deploy(LimitswapFactory, LimitswapPair.address).then(function(){
        return deployer.deploy(LimitswapRouter, LimitswapFactory.address, "0x02d4418C5eeb5BeF366272018F7cD498179FE98B");
      });
    });
  }
  
};
