const limitswapMine = artifacts.require("LimitswapMine");
const limitswapToken = artifacts.require("LimitswapToken");

module.exports = function(deployer) {
    deployer.deploy(limitswapToken).then(function() {
      return deployer.deploy(limitswapMine, limitswapToken.address, '1000000000000000000', '0');
    });
};
