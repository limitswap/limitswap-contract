const LimitswapPair = artifacts.require("LimitswapPair");
const LimitswapFactory = artifacts.require("LimitswapFactory");
const LimitswapTradeCore = artifacts.require("LimitswapTradeCore");
const TestCoinA = artifacts.require("testCoinA");
const TestCoinB = artifacts.require("testCoinB");
const LimitswapRouter = artifacts.require("LimitswapRouter");
const WETH = artifacts.require("WETH");
const FlashBorrower = artifacts.require("flashBorrower");
const LimitswapMine = artifacts.require("LimitswapMine");
const LimitswapToken = artifacts.require("LimitswapToken");
const TestCoinU = artifacts.require("testCoinU");


contract('LimitswapPair', (accounts) => {
    let testCoinA;
    let testCoinB;
    let limitSwap;
    before(async() => {
        testCoinA = await TestCoinA.deployed();
        testCoinB = await TestCoinB.deployed();
        const limitFactory = await LimitswapFactory.deployed();
        while (testCoinA.address > testCoinB.address) {
            testCoinA = await TestCoinA.new();
        }
        await limitFactory.createPair(testCoinA.address, testCoinB.address, { from: accounts[0] });
        const a = await limitFactory.allPairs.call(0);
        console.log(a);
        limitSwap = await LimitswapPair.at(a);
      });

    //const limitSwap = await LimitswapPair.deployed();
    it('should act as normal CFMM without limit order', async () =>{
        const core = await LimitswapTradeCore.deployed();
        //await limitSwap.initTokenAddress(testCoinA.address, testCoinB.address, { from: accounts[0] });
        console.log(await limitSwap.name.call());
        await testCoinA.mint(accounts[0], web3.utils.toBN(web3.utils.toWei('100')), { from: accounts[0] });
        await testCoinB.mint(accounts[0], web3.utils.toBN(web3.utils.toWei('200000')), { from: accounts[0] });
        console.log(web3.utils.fromWei(await testCoinB.balanceOf.call(accounts[0])));
        console.log('accounts[0]: add liquidity with 100 A and 200000 B');
        console.log(limitSwap.address);
        await testCoinA.transfer(limitSwap.address, web3.utils.toBN(web3.utils.toWei('100')), { from: accounts[0] });
        await testCoinB.transfer(limitSwap.address, web3.utils.toBN(web3.utils.toWei('200000')), { from: accounts[0] });
        await limitSwap.mint(accounts[0], { from: accounts[0] });
        //console.log(' expect output for 1 A',web3.utils.fromWei((await limitSwap.estOutput.call(web3.utils.toWei('1'), false))[0]));
        console.log(' liquidity', web3.utils.fromWei(await limitSwap.liquidity.call()));
        console.log(' accounts[0] share', web3.utils.fromWei(await limitSwap.balanceOf.call(accounts[0])));
        console.log(' reserve0', web3.utils.fromWei(await limitSwap.reserve0.call()));
        console.log(' currentSqrtPriceX96', web3.utils.fromWei(await limitSwap.currentSqrtPriceX96.call()));
        console.log('accounts[1]: add liquidity with 50 A and 100000 B');
        await testCoinA.mint(accounts[1], web3.utils.toBN(web3.utils.toWei('50')), { from: accounts[1] });
        await testCoinB.mint(accounts[1], web3.utils.toBN(web3.utils.toWei('100000')), { from: accounts[1] });
        await testCoinA.transfer(limitSwap.address, web3.utils.toBN(web3.utils.toWei('50')), { from: accounts[1] });
        await testCoinB.transfer(limitSwap.address, web3.utils.toBN(web3.utils.toWei('100000')), { from: accounts[1] });
        await limitSwap.mint(accounts[1], { from: accounts[1] });
        console.log(' liquidity', web3.utils.fromWei(await limitSwap.liquidity.call()));
        console.log(' accounts[1] share', web3.utils.fromWei(await limitSwap.balanceOf.call(accounts[1])));
        console.log(' reserve0', web3.utils.fromWei(await limitSwap.reserve0.call()));
        console.log(' currentSqrtPriceX96', web3.utils.fromWei(await limitSwap.currentSqrtPriceX96.call()));
        var balance0B0 = await testCoinB.balanceOf.call(accounts[0]);
        console.log('accounts[0]: swap 10 A');
        await testCoinA.mint(limitSwap.address, web3.utils.toBN(web3.utils.toWei('10')), { from: accounts[0] });
        await limitSwap.swap(web3.utils.toBN(web3.utils.toWei('10')),false, accounts[0], { from: accounts[0] });
        var balance0B1 = await testCoinB.balanceOf.call(accounts[0]);
        //await limitSwap.trade(web3.utils.toBN(web3.utils.toWei('9')),false, -1234611, { from: accounts[0] });
        console.log(' accounts[0] receive B', web3.utils.fromWei(balance0B1.sub(balance0B0)));
        console.log(' liquidity', web3.utils.fromWei(await limitSwap.liquidity.call()));
        console.log(' reserve0', web3.utils.fromWei(await limitSwap.reserve0.call()));
        //price tick exploited on buyside = 1 from ^74721 -> ^76012
        assert.equal(await limitSwap.isExploited.call(76000, 1), true, "Exploited error");
        assert.equal(await limitSwap.isExploited.call(74000, 1), false, "Exploited error");
        console.log('accounts[0]: swap 10000 B');
        var balance0A0 = await testCoinA.balanceOf.call(accounts[0]);
        //console.log(' output for 10000 B',web3.utils.fromWei((await limitSwap.estOutput.call(web3.utils.toWei('10000'), true))[0]));
        await testCoinB.mint(limitSwap.address, web3.utils.toBN(web3.utils.toWei('10000')), { from: accounts[0] });
        await limitSwap.swap(web3.utils.toBN(web3.utils.toWei('10000')),true, accounts[0], { from: accounts[0] });
        var balance0A1 = await testCoinA.balanceOf.call(accounts[0]);
        console.log(' accounts[0] receive A', web3.utils.fromWei(balance0A1.sub(balance0A0)));
        console.log(' liquidity', web3.utils.fromWei(await limitSwap.liquidity.call()));
        console.log(' reserve0', web3.utils.fromWei(await limitSwap.reserve0.call()));// 154.506437768240343344
        console.log('accounts[0]: remove half liquidity');
        await limitSwap.transfer(limitSwap.address, web3.utils.toBN(web3.utils.toWei('2236')), { from: accounts[0] });
        await limitSwap.burn(accounts[0], { from: accounts[0] });
        balance0B0 = await testCoinB.balanceOf.call(accounts[0]);
        balance0A0 = await testCoinA.balanceOf.call(accounts[0]);
        console.log(' accounts[0] receive A', web3.utils.fromWei(balance0A0.sub(balance0A1)));
        console.log(' accounts[0] receive B', web3.utils.fromWei(balance0B0.sub(balance0B1)));
        console.log(' liquidity', web3.utils.fromWei(await limitSwap.liquidity.call()));
        console.log(' reserve0', web3.utils.fromWei(await limitSwap.reserve0.call()));// 96.568285005314461994
    });
    it('should take limit orders', async () =>{
        //console.log(' expect output for 1 A',web3.utils.fromWei((await limitSwap.estOutput.call(web3.utils.toWei('1'), false))[0]));
        console.log(' tick', (await limitSwap.currentTick.call()).toString());//75420
        console.log(' totalLimit0', web3.utils.fromWei((await limitSwap.getTotalLimit.call())[0]).toString());
        console.log(' totalLimit1', web3.utils.fromWei((await limitSwap.getTotalLimit.call())[1]).toString());
        //console.log(' expect output for 50000 B',web3.utils.fromWei((await limitSwap.estOutput.call(web3.utils.toWei('50000'), true))[0]));
        console.log('accounts[2]: add sell limit 5 A at tick 76000'); //buyside = 1 same wordhigh different wordlow
        await testCoinA.mint(limitSwap.address, web3.utils.toBN(web3.utils.toWei('5')), { from: accounts[2] });
        await limitSwap.putLimitOrder('76000', web3.utils.toBN(web3.utils.toWei('5')), true , { from: accounts[2]});
        var sellShare = await limitSwap.sellShare.call(accounts[2],'76000');
        console.log(' accounts[2] 76000 sell share', web3.utils.fromWei(sellShare).toString());
        res = await limitSwap.getLimitTokens.call( web3.utils.toBN('76000'), accounts[2], sellShare, true);
        console.log(' accounts[2] 76000 ', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        console.log(' totalLimit0', web3.utils.fromWei((await limitSwap.getTotalLimit.call())[0]).toString());
        console.log(' totalLimit1', web3.utils.fromWei((await limitSwap.getTotalLimit.call())[1]).toString());
        res = await limitSwap.getDeep.call( web3.utils.toBN('76000'));
        console.log(' deep:', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        //console.log(' expect output for 50000 B',web3.utils.fromWei((await limitSwap.estOutput.call(web3.utils.toWei('50000'), true))[0]));
        console.log('accounts[0]: swap 50000 B');
        var balance0A0 = await testCoinA.balanceOf.call(accounts[0]);
        await testCoinB.mint(limitSwap.address, web3.utils.toBN(web3.utils.toWei('50000')), { from: accounts[0] });
        await limitSwap.swap(web3.utils.toBN(web3.utils.toWei('50000')),true, accounts[0], { from: accounts[0] });
        var balance0A1 = await testCoinA.balanceOf.call(accounts[0]);
        console.log(' accounts[0] receive A', web3.utils.fromWei(balance0A1.sub(balance0A0)));//22.334346849531246935
        console.log(' tick', (await limitSwap.currentTick.call()).toString());//79394
        console.log(' totalLimit0', web3.utils.fromWei((await limitSwap.getTotalLimit.call())[0]).toString());
        console.log(' totalLimit1', web3.utils.fromWei((await limitSwap.getTotalLimit.call())[1]).toString());
        res = await limitSwap.getDeep.call( web3.utils.toBN('76000'));
        console.log(' deep:', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        res = await limitSwap.getLimitTokens.call( web3.utils.toBN('76000'), accounts[2], sellShare, true);
        console.log(' accounts[2] 76000 ', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        assert.equal(await limitSwap.isExploited.call(76000, 0), true, "Exploited error");
        assert.equal(await limitSwap.isExploited.call(76000, 1), false, "Exploited error");
        console.log('accounts[0]: swap 23 A');
        await testCoinA.mint(limitSwap.address, web3.utils.toBN(web3.utils.toWei('23')), { from: accounts[0] });
        await limitSwap.swap(web3.utils.toBN(web3.utils.toWei('23')),false, accounts[0], { from: accounts[0] });
        console.log(' tick', (await limitSwap.currentTick.call()).toString());
        res = await limitSwap.getLimitTokens.call( web3.utils.toBN('76000'), accounts[2], sellShare, true);
        console.log(' accounts[2] 76000 ', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        console.log('accounts[3]: add sell limit 5 A at tick 76000');
        await testCoinA.mint(limitSwap.address, web3.utils.toBN(web3.utils.toWei('5')), { from: accounts[3] });
        await limitSwap.putLimitOrder('76000', web3.utils.toBN(web3.utils.toWei('5')), true , { from: accounts[3]});
        var sellShare3 = await limitSwap.sellShare.call(accounts[3],'76000');
        console.log(' accounts[3] 76000 sell share', web3.utils.fromWei(sellShare3).toString());
        res = await limitSwap.getLimitTokens.call( web3.utils.toBN('76000'), accounts[3], sellShare3, true);
        console.log(' accounts[3] 76000 ', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        res = await limitSwap.getLimitTokens.call( web3.utils.toBN('76000'), accounts[2], sellShare, true);
        console.log(' accounts[2] 76000 ', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');

        res = await limitSwap.getDeep.call( web3.utils.toBN('76000'));
        console.log(' deep:', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');

        console.log('accounts[2]: add sell limit 2 A at tick 76000'); //buyside = 1 same wordhigh different wordlow
        var balance0B00 = await testCoinB.balanceOf.call(accounts[2]);
        await testCoinA.mint(limitSwap.address, web3.utils.toBN(web3.utils.toWei('2')), { from: accounts[2] });
        await limitSwap.putLimitOrder('76000', web3.utils.toBN(web3.utils.toWei('2')), true , { from: accounts[2]});
        var sellShare = await limitSwap.sellShare.call(accounts[2],'76000');
        console.log(' accounts[2] 76000 sell share', web3.utils.fromWei(sellShare).toString());
        res = await limitSwap.getLimitTokens.call( web3.utils.toBN('76000'), accounts[2], sellShare, true);
        console.log(' accounts[2] 76000 ', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        res = await limitSwap.getDeep.call( web3.utils.toBN('76000'));
        console.log(' deep:', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');

        var balance0B0 = await testCoinB.balanceOf.call(accounts[2]);
        console.log(' accounts[2] receive ', web3.utils.fromWei(balance0B0.sub(balance0B00)) ,' B');
        console.log('accounts[2]: add sell limit 1 A at tick 76001'); //buyside = 1 same wordhigh different wordlow
        //console.log(' expect output for 1 A',web3.utils.fromWei((await limitSwap.estOutput.call(web3.utils.toWei('1'), false))[0]));
        await testCoinA.mint(limitSwap.address, web3.utils.toBN(web3.utils.toWei('1')), { from: accounts[2] });
        await limitSwap.putLimitOrder('76001', web3.utils.toBN(web3.utils.toWei('1')), true , { from: accounts[2]});
        await limitSwap.cancelLimitOrder( web3.utils.toBN('76000'), sellShare3, true , { from: accounts[3]});
        var balance0B1 = await testCoinB.balanceOf.call(accounts[2]);
        console.log(' accounts[2] receive B', web3.utils.fromWei(balance0B1.sub(balance0B0)));
        console.log(' accounts[2] 76001 sell share', web3.utils.fromWei(await limitSwap.sellShare.call(accounts[2],'76001' )).toString());
        console.log(' tick', (await limitSwap.currentTick.call()).toString());//79143
        console.log('accounts[2]: add sell limit 30 A at tick 76001');
        await testCoinA.mint(limitSwap.address, web3.utils.toBN(web3.utils.toWei('30')), { from: accounts[2] });
        //console.log(' expect output for 1 A',web3.utils.fromWei((await limitSwap.estOutput.call(web3.utils.toWei('1'), false))[0]));
        await limitSwap.putLimitOrder('76001', web3.utils.toBN(web3.utils.toWei('30')), true , { from: accounts[2]});
        console.log(' accounts[2] 76001 sell share', web3.utils.fromWei(await limitSwap.sellShare.call(accounts[2],'76001' )).toString());
        //32680.492924524207349228
        console.log(' tick', (await limitSwap.currentTick.call()).toString());//76001
        await testCoinA.mint(limitSwap.address, web3.utils.toBN(web3.utils.toWei('1')), { from: accounts[0] });
        //await limitSwap.swap(web3.utils.toBN(web3.utils.toWei('1')),false, accounts[0], { from: accounts[0] });
        //console.log(' expect output for 1 A',web3.utils.fromWei((await limitSwap.estOutput.call(web3.utils.toWei('1'), false))[0]));
        assert.equal(await limitSwap.isExploited.call(76001, 0), false, "Exploited error");
        assert.equal(await limitSwap.isExploited.call(76001, 1), false, "Exploited error");
        console.log(' tick', (await limitSwap.currentTick.call()).toString());//76001
        console.log('accounts[2]: add and remove buy limit 100 B at tick -12301');
        balance0B0 = await testCoinB.balanceOf.call(accounts[2]);
        await testCoinB.mint(limitSwap.address, web3.utils.toBN(web3.utils.toWei('100')), { from: accounts[2] });
        await limitSwap.putLimitOrder( web3.utils.toBN('-12301'), web3.utils.toBN(web3.utils.toWei('100')), false , { from: accounts[2]});
        var buyshare = await limitSwap.buyShare.call(accounts[2], web3.utils.toBN('-12301') );
        console.log(' buy share after put', (await limitSwap.buyShare.call(accounts[2], web3.utils.toBN('-12301'))).toString());
        await limitSwap.cancelLimitOrder( web3.utils.toBN('-12301'), buyshare, false , { from: accounts[2]});
        balance0B1 = await testCoinB.balanceOf.call(accounts[2]);
        console.log(' buy share after cancel', (await limitSwap.buyShare.call(accounts[2], web3.utils.toBN('-12301'))).toString());
        console.log(' should be 100:', (web3.utils.fromWei(balance0B1.sub(balance0B0))).toString());
        assert.equal((web3.utils.fromWei(balance0B1.sub(balance0B0))).toString(), '100');
        console.log('accounts[2]: claim limit order output at tick 76000');
        await limitSwap.cancelLimitOrder( web3.utils.toBN('76000'), await limitSwap.sellShare.call(accounts[2], web3.utils.toBN('76000') ), true , { from: accounts[2]});
        balance0B0 = await testCoinB.balanceOf.call(accounts[2]);
        console.log(' accounts[2] receive B:', (web3.utils.fromWei(balance0B0.sub(balance0B1))).toString());//9987.183877566928842588
    });
    it('should endure wild input test', async () =>{
        console.log(' reserve0', web3.utils.fromWei(await limitSwap.reserve0.call()));// 93.807154263222245149
        console.log(' reserve1', web3.utils.fromWei(await limitSwap.reserve1.call()));//187392.597117590562181517
        //console.log(' expect output for 10000 B',web3.utils.fromWei((await limitSwap.estOutput.call(web3.utils.toWei('10000'), true))[0]));
        //console.log(' expect output for 140 A',web3.utils.fromWei((await limitSwap.estOutput.call(web3.utils.toWei('140'), false))[0]));
        //console.log(' expect price for 140 A',web3.utils.fromWei((await limitSwap.estOutput.call(web3.utils.toWei('140'), false))[2]));
        console.log('accounts[2]: add buy limit 5000000 B at tick 69715');
        await testCoinB.mint(limitSwap.address, web3.utils.toBN(web3.utils.toWei('50000')), { from: accounts[2] });
        await limitSwap.putLimitOrder( web3.utils.toBN('69715'), web3.utils.toBN(web3.utils.toWei('50000')), false , { from: accounts[2]});
        buyShare = await limitSwap.buyShare.call(accounts[2], web3.utils.toBN('69715'))
        console.log(' buy share after put', buyShare.toString());
        res = await limitSwap.getLimitTokens.call( web3.utils.toBN('69715'), accounts[2], buyShare, false);
        console.log(' 69712', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        //console.log(' expect output for 140 A',web3.utils.fromWei((await limitSwap.estOutput.call(web3.utils.toWei('140'), false))[0]));
        //console.log(' expect price for 140 A',web3.utils.fromWei((await limitSwap.estOutput.call(web3.utils.toWei('140'), false))[2]));
        console.log('accounts[2]: add sell limit 100 A at tick 97451');
        await testCoinA.mint(limitSwap.address, web3.utils.toBN(web3.utils.toWei('100')), { from: accounts[2] });
        await limitSwap.putLimitOrder( web3.utils.toBN('97451'), web3.utils.toBN(web3.utils.toWei('100')), true , { from: accounts[2]});
        console.log(' totalLimit0', web3.utils.fromWei((await limitSwap.getTotalLimit.call())[0]).toString());
        console.log(' totalLimit1', web3.utils.fromWei((await limitSwap.getTotalLimit.call())[1]).toString());
        //console.log(' expect output for 140 A',web3.utils.fromWei((await limitSwap.estOutput.call(web3.utils.toWei('140'), false))[0]));
        assert.equal(await limitSwap.isExploited.call(69715, 1), false, "Exploited error");
        console.log('accounts[0]: swap 140 A');
        var balance0B0 = await testCoinB.balanceOf.call(accounts[0]);
        await testCoinA.mint(limitSwap.address, web3.utils.toBN(web3.utils.toWei('140')), { from: accounts[0] });
        await limitSwap.swap(web3.utils.toBN(web3.utils.toWei('140')),false, accounts[0], { from: accounts[0] });
        console.log(' totalLimit0', web3.utils.fromWei((await limitSwap.getTotalLimit.call())[0]).toString());
        console.log(' totalLimit1', web3.utils.fromWei((await limitSwap.getTotalLimit.call())[1]).toString());
        var balance0B1 = await testCoinB.balanceOf.call(accounts[0]);
        console.log(' accounts[0] receive B:', (web3.utils.fromWei(balance0B1.sub(balance0B0))).toString());
        //assert.equal(await limitSwap.isExploited.call(69715, 1), true, "Exploited error");
        res = await limitSwap.getLimitTokens.call( web3.utils.toBN('69715'), accounts[2], buyShare, false);
        console.log(' reserve0', web3.utils.fromWei(await limitSwap.reserve0.call()));
        console.log(' reserve1', web3.utils.fromWei(await limitSwap.reserve1.call()));
        console.log(' tick', (await limitSwap.currentTick.call()).toString());
        console.log(' 69715', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');//69712 0  A  50000  B
        //console.log(' expect output for 1000 B',web3.utils.fromWei((await limitSwap.estOutput.call(web3.utils.toWei('1000'), true))[0]));
        console.log(' expect output for 10000 B',web3.utils.fromWei((await limitSwap.estOutput.call(web3.utils.toWei('10000'), true))[0]));
        console.log(' expect output for 1 A',web3.utils.fromWei((await limitSwap.estOutput.call(web3.utils.toWei('1'), false))[0]));
        //console.log(' expect output for 10 A',web3.utils.fromWei((await limitSwap.estOutput.call(web3.utils.toWei('10'), false))[0]));//4629

        await testCoinA.mint(limitSwap.address, web3.utils.toBN(web3.utils.toWei('300')), { from: accounts[0] });
        //console.log(' est gas for swap 200 A', await limitSwap.swap.estimateGas(web3.utils.toBN(web3.utils.toWei('200')),false, accounts[0], { from: accounts[0] }));
        //console.log(' est gas for swap 300 A', await limitSwap.swap.estimateGas(web3.utils.toBN(web3.utils.toWei('300')),false, accounts[0], { from: accounts[0] }));
        // console.log('accounts[0]: swap 200 A');
        // var balance0B0 = await testCoinB.balanceOf.call(accounts[0]);
        // await testCoinA.mint(limitSwap.address, web3.utils.toBN(web3.utils.toWei('200')), { from: accounts[0] });
        // await limitSwap.swap(web3.utils.toBN(web3.utils.toWei('200')),false, accounts[0], { from: accounts[0] });
        // var balance0B1 = await testCoinB.balanceOf.call(accounts[0]);
        // console.log(' reserve0', web3.utils.fromWei(await limitSwap.reserve0.call()));
        // console.log(' reserve1', web3.utils.fromWei(await limitSwap.reserve1.call()));
        // console.log(' tick', (await limitSwap.currentTick.call()).toString());
        // console.log(' accounts[0] receive B:', (web3.utils.fromWei(balance0B1.sub(balance0B0))).toString());

        //console.log(' expect output for 100 A',web3.utils.fromWei((await limitSwap.estOutput.call(web3.utils.toWei('100'), false))[0]));
        //console.log(' expect output for 600 A',web3.utils.fromWei((await limitSwap.estOutput.call(web3.utils.toWei('600'), false))[0]));
        console.log(' expect output for 1000 A',web3.utils.fromWei((await limitSwap.estOutput.call(web3.utils.toWei('1000'), false))[0]));
        //console.log(' expect price for 300 A',web3.utils.fromWei((await limitSwap.estOutput.call(web3.utils.toWei('300'), false))[2]));
        //2098478828474.011932436660412518
        console.log(' totalLimit0', web3.utils.fromWei((await limitSwap.getTotalLimit.call())[0]).toString());
        console.log(' totalLimit1', web3.utils.fromWei((await limitSwap.getTotalLimit.call())[1]).toString());
        //console.log(' test', web3.utils.fromWei(await limitSwap.test.call({from: accounts[2]})).toString());
    });
});


contract('LimitswapRouter', (accounts) => {
    it('should create pair by adding liquidity', async () =>{
        //(5 ETH, 100A), (100A, 20000B)
        const router = await LimitswapRouter.deployed();
        const testCoinA = await TestCoinA.deployed();
        const testCoinB = await TestCoinB.deployed();
        await testCoinA.mint(accounts[3], web3.utils.toBN(web3.utils.toWei('400')), {from: accounts[3]});
        await testCoinB.mint(accounts[3], web3.utils.toBN(web3.utils.toWei('40000')), {from: accounts[3]});
        await testCoinA.approve(router.address, web3.utils.toBN(web3.utils.toWei('654474745')), {from: accounts[3]});
        await testCoinB.approve(router.address, web3.utils.toBN(web3.utils.toWei('654474745')), {from: accounts[3]});
        await router.addLiquidityETH(testCoinA.address, web3.utils.toBN(web3.utils.toWei('100')),'0','0',
            (Date.now()+50000).toString().substr(0,10), {from: accounts[3], value: web3.utils.toWei('5')});
        await router.addLiquidity(testCoinA.address, testCoinB.address, web3.utils.toWei('100'), web3.utils.toWei('20000'),
            '0','0',(Date.now()+50000).toString().substr(0,10), {from: accounts[3]});
        const info0 = await router.getPairInfo.call(testCoinA.address, testCoinB.address);
        var pairAB = await LimitswapPair.at(info0[2]);
        var LP0 = web3.utils.toBN(await pairAB.balanceOf(accounts[3]));
        console.log(' LP0: ', web3.utils.fromWei(LP0));
        console.log(' totalSupply: ', web3.utils.fromWei(await pairAB.totalSupply.call()));
        console.log(' reserve0: ', web3.utils.fromWei(await pairAB.reserve0.call()));
        console.log(' currentSqrtPriceX96: ', web3.utils.fromWei(await pairAB.currentSqrtPriceX96.call()));
        var res = await pairAB.LP2Tokens.call(LP0);
        var res0 = res;
        [res[0], res[1]] = testCoinA.address < testCoinB.address ? [res[0], res[1]] : [res[1], res[0]];
        console.log( 'accounts[3] LP 0: ', web3.utils.fromWei(res[0]).toString(),' A ',web3.utils.fromWei(res[1]).toString(),' B ');
        await router.addLiquidity(testCoinB.address, testCoinA.address, web3.utils.toWei('20000'), web3.utils.toWei('100'),
            '0','0',(Date.now()+50000).toString().substr(0,10), {from: accounts[3]});
        var LP1 = web3.utils.toBN(await pairAB.balanceOf(accounts[3]));
        console.log(' LP1-LP0: ', web3.utils.fromWei(LP1.sub(LP0)));
        console.log(' totalSupply: ', web3.utils.fromWei(await pairAB.totalSupply.call()));
        console.log(' reserve0: ', web3.utils.fromWei(await pairAB.reserve0.call()));
        console.log(' currentSqrtPriceX96: ', web3.utils.fromWei(await pairAB.currentSqrtPriceX96.call()));
        console.log(' amount0toamount1: ', web3.utils.fromWei(await pairAB.amount0ToAmount1.call('99999999999999999998','5602277097478613991870465505')));
        var res = await pairAB.LP2Tokens.call(LP1.sub(LP0));
        [res[0], res[1]] = testCoinA.address < testCoinB.address ? [res[0], res[1]] : [res[1], res[0]];
        console.log( 'accounts[3] LP +: ', web3.utils.fromWei(res[0]).toString(),' A ',web3.utils.fromWei(res[1]).toString(),' B ');
        var res = await pairAB.LP2Tokens.call(LP1);
        [res[0], res[1]] = testCoinA.address < testCoinB.address ? [res[0], res[1]] : [res[1], res[0]];
        console.log( 'accounts[3] LP 1: ', web3.utils.fromWei(res[0]).toString(),' A ',web3.utils.fromWei(res[1]).toString(),' B ');
        var res = await pairAB.LP2Tokens.call(LP0);
        //res should equal to res0
        [res[0], res[1]] = testCoinA.address < testCoinB.address ? [res[0], res[1]] : [res[1], res[0]];
        console.log( 'accounts[3] LP 0: ', web3.utils.fromWei(res[0]).toString(),' A ',web3.utils.fromWei(res[1]).toString(),' B ');
        var A0 = web3.utils.toBN(await testCoinA.balanceOf(accounts[3]));
        var B0 = web3.utils.toBN(await testCoinB.balanceOf(accounts[3]));
        console.log( 'accounts[3] AB: ', web3.utils.fromWei(A0).toString(),' A ',web3.utils.fromWei(B0).toString(),' B ');
        await pairAB.approve(router.address, web3.utils.toBN(web3.utils.toWei('654474745')), {from: accounts[3]});
        await router.removeLiquidity(testCoinA.address, testCoinB.address, LP0,
            (Date.now()+50000).toString().substr(0,10), {from: accounts[3]});
        var A1 = web3.utils.toBN(await testCoinA.balanceOf(accounts[3]));
        var B1 = web3.utils.toBN(await testCoinB.balanceOf(accounts[3]));
        console.log( 'accounts[3] delta AB: ', web3.utils.fromWei(A1.sub(A0)).toString(),' A ',web3.utils.fromWei(B1.sub(B0)).toString(),' B ');
    });
    it('should swap for users', async () =>{
        const router = await LimitswapRouter.deployed();
        const testCoinA = await TestCoinA.deployed();
        const testCoinB = await TestCoinB.deployed();
        const weth = await WETH.deployed();
        var balance3B0 = await testCoinB.balanceOf.call(accounts[3]);
        var estOutput = await router.getAmountOut.call(web3.utils.toWei('1'), [weth.address, testCoinA.address, testCoinB.address]);
        console.log(' expect B with price impact:', (web3.utils.fromWei(estOutput[0])).toString());
        console.log(' expect B w/o  price impact:', (web3.utils.fromWei(estOutput[1])).toString());
        await router.swapExactETHForTokens(0, [weth.address, testCoinA.address, testCoinB.address], accounts[3],
            (Date.now()+50000).toString().substr(0,10), {from: accounts[3], value: web3.utils.toWei('1')});
        var balance3B1 = await testCoinB.balanceOf.call(accounts[3]);
        console.log(' accounts[2] receive B:', (web3.utils.fromWei(balance3B1.sub(balance3B0))).toString());
        var balance3ETH0 = web3.utils.toBN((await web3.eth.getBalance(accounts[3])));
        await router.swapExactTokensForETH(balance3B1.sub(balance3B0), 0, [testCoinB.address, testCoinA.address, weth.address], accounts[3],
            (Date.now()+50000).toString().substr(0,10), {from: accounts[3]});
        var balance3ETH1 = web3.utils.toBN((await web3.eth.getBalance(accounts[3])));
        console.log(' accounts[2] receive ETH:', (web3.utils.fromWei(balance3ETH1.sub(balance3ETH0))).toString());
    });
    it('should put limit for users', async () =>{
        const router = await LimitswapRouter.deployed();
        const testCoinA = await TestCoinA.deployed();
        const testCoinB = await TestCoinB.deployed();
        const weth = await WETH.deployed();
        const info0 = await router.getPairInfo.call(testCoinA.address, testCoinB.address);
        const info1 = await router.getPairInfo.call(testCoinA.address, weth.address);
        console.log(' A/B tick:', info0[0].toString());//-52978
        console.log(' A/ETH tick:', info1[0].toString());//29930
        await testCoinA.mint(accounts[3], web3.utils.toBN(web3.utils.toWei('200')), {from: accounts[3]});
        await testCoinA.mint(accounts[3], web3.utils.toBN(web3.utils.toWei('200')), {from: accounts[3]});
        await testCoinA.approve(router.address, web3.utils.toBN(web3.utils.toWei('2000000000000')), {from: accounts[3]});
        await router.putLimitOrder(info0[2], testCoinA.address, web3.utils.toBN(web3.utils.toWei('10')), -61485, {from: accounts[3]});
        var balance3A0 = await testCoinA.balanceOf.call(accounts[3]);
        console.log(' balance3A0:', balance3A0.toString());
        await router.putLimitOrder(info1[2], testCoinA.address, web3.utils.toBN(web3.utils.toWei('10')), 18741, {from: accounts[3]});
        const pair = await LimitswapPair.at(info1[2]);
        console.log(' balance3A0:', (await testCoinA.balanceOf.call(accounts[3])).toString());
        console.log(' accounts[3] sellShare 18741: ', web3.utils.fromWei(await pair.sellShare(accounts[3], 18741)));
        await router.cancelLimitOrder(info1[2], 18741, await pair.sellShare(accounts[3], 18741), true, {from: accounts[3]});
        await router.cancelLimitOrder(info1[2], 18741, await pair.buyShare(accounts[3], 18741), false, {from: accounts[3]});
        var balance3A1 = await testCoinA.balanceOf.call(accounts[3]);
        console.log(' balance3A1:', balance3A1.toString());
        assert.equal(balance3A0.toString(), balance3A1.toString());
        //const positions = await router.getLimitOrders(accounts[3], '10', '0');
        //console.log(positions);
        //const lps = await router.getLPBalance(accounts[3], '10', '0', '10');
        //console.log(lps);
    });
    it('should handle with flashLoan and reward to fee collector', async () => {
        const router = await LimitswapRouter.deployed();
        const testCoinA = await TestCoinA.deployed();
        const testCoinB = await TestCoinB.deployed();
        const flashBorrower = await FlashBorrower.new(testCoinA.address, testCoinB.address);
        const limitFactory = await LimitswapFactory.deployed();
        const pair = (await router.getPairInfo.call(testCoinA.address, testCoinB.address))[2];
        assert.equal(await limitFactory.owner(), accounts[0]);
        await limitFactory.setFeeCollector(accounts[0], {from: accounts[0]});
        await flashBorrower.testFlashLoan(pair, web3.utils.toWei('1'), web3.utils.toWei('1'), {from: accounts[4]});
        var balance0A = await testCoinA.balanceOf.call(accounts[0]);
        var balance0B = await testCoinB.balanceOf.call(accounts[0]);
        assert.isAbove(parseFloat(web3.utils.fromWei(balance0A)), 0);
        assert.isAbove(parseFloat(web3.utils.fromWei(balance0B)), 0);
    });
});

contract('Test for changes on limit orders', (accounts) => {
    it('should endure test', async () =>{
        //(5 ETH, 100A), (100A, 20000B)
        const router = await LimitswapRouter.deployed();
        var testCoinA = await TestCoinA.deployed();
        const testCoinB = await TestCoinB.deployed();
        const weth = await WETH.deployed();
        while (testCoinA.address > weth.address) {
            testCoinA = await TestCoinA.new();
        }
        await testCoinA.mint(accounts[3], web3.utils.toBN(web3.utils.toWei('2000')), {from: accounts[3]});
        await testCoinA.approve(router.address, web3.utils.toBN(web3.utils.toWei('654474745')), {from: accounts[3]});
        await router.addLiquidityETH(testCoinA.address, web3.utils.toBN(web3.utils.toWei('30')),
            '0','0',(Date.now()+50000).toString().substr(0,10), {from: accounts[3], value: web3.utils.toWei('0.01')});
        const info1 = await router.getPairInfo.call(testCoinA.address, weth.address);
        const pair = await LimitswapPair.at(info1[2]);
        console.log(' LP: ', web3.utils.fromWei(await pair.balanceOf.call(accounts[3])));
        await pair.approve(router.address, web3.utils.toBN(web3.utils.toWei('654474745')), {from: accounts[3]});
        console.log(' tick', (await pair.currentTick.call()).toString());
        await router.putLimitOrderETH(info1[2],web3.utils.toBN('-80168'),{from: accounts[3], value: web3.utils.toWei('0.001')});
        res = await pair.getDeep.call( web3.utils.toBN('-80168'));
        console.log(' deep:', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        console.log(' tick', (await pair.currentTick.call()).toString());
        var sellShare = await pair.sellShare.call(accounts[3],web3.utils.toBN('-80168'));
        res = await pair.getLimitTokens.call( web3.utils.toBN('-80168'), accounts[3], sellShare, true);
        console.log(' accounts[3] -80168 ', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        var buyShare = await pair.buyShare.call(accounts[3],web3.utils.toBN('-80168'));
        res = await pair.getLimitTokens.call( web3.utils.toBN('-80168'), accounts[3], buyShare, false);
        console.log(' accounts[3] -80168 ', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        res = await router.cancelLimitOrder.call(info1[2], web3.utils.toBN('-80168'), buyShare, false, {from:accounts[3]});
        console.log(' call cancel:', web3.utils.fromWei(res[0]), web3.utils.fromWei(res[1]));

        console.log('swap');
        console.log(web3.utils.fromWei((await router.getAmountOut.call(web3.utils.toBN(web3.utils.toWei('1')),[testCoinA.address, weth.address]))[0]));
        await router.swapExactTokensForETH(web3.utils.toBN(web3.utils.toWei('1')),
                '0', [testCoinA.address, weth.address],accounts[3],
                (Date.now()+50000).toString().substr(0,10),{from: accounts[3]});
        res = await pair.getDeep.call( web3.utils.toBN('-80168'));
        //console.log(await pair.isExploited.call(web3.utils.toBN('-80168'), 0));
        console.log(await pair.isExploited.call(web3.utils.toBN('-80168'), 1));
        console.log(' deep:', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        console.log(' tick', (await pair.currentTick.call()).toString());
        //await pair.getLimitTokens(web3.utils.toBN('-80168'), accounts[3], buyShare, false);
        res = await pair.getLimitTokens.call( web3.utils.toBN('-80168'), accounts[3], buyShare, false);
        console.log(' accounts[3] -80168 ', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');

        console.log('swap');
        console.log(web3.utils.fromWei((await router.getAmountOut.call(web3.utils.toBN(web3.utils.toWei('2')),[testCoinA.address, weth.address]))[0]));
        await router.swapExactTokensForETH(web3.utils.toBN(web3.utils.toWei('3')),
                '0', [testCoinA.address, weth.address],accounts[3],
                (Date.now()+50000).toString().substr(0,10),{from: accounts[3]});
                res = await pair.getDeep.call( web3.utils.toBN('-80168'));
                console.log(' deep:', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        console.log(' tick', (await pair.currentTick.call()).toString());
        res = await pair.getLimitTokens.call( web3.utils.toBN('-80168'), accounts[3], buyShare, false);
        console.log(' accounts[3] -80168 ', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        console.log(' buyShare: ', web3.utils.fromWei(buyShare));
        res = await router.cancelLimitOrder.call(info1[2], web3.utils.toBN('-80168'), buyShare, false, {from:accounts[3]});
        console.log(' call cancel:', web3.utils.fromWei(res[0]), web3.utils.fromWei(res[1]));

        await router.cancelLimitOrder(info1[2], web3.utils.toBN('-80168'), buyShare.div(web3.utils.toBN(100)), false, {from:accounts[3]});
        var buyShare = await pair.buyShare.call(accounts[3],web3.utils.toBN('-80168'));
        console.log(' buyShare: ', web3.utils.fromWei(buyShare));
        res = await pair.getLimitTokens.call( web3.utils.toBN('-80168'), accounts[3], buyShare, false);
        console.log(' accounts[3] -80168 ', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');

        // await router.getAmountOut.call(web3.utils.toBN(web3.utils.toWei('115')),[testCoinA.address, weth.address]);
        // await router.swapExactTokensForETH(web3.utils.toBN(web3.utils.toWei('300')),
        //         '0', [testCoinA.address, weth.address],accounts[3],
        //         (Date.now()+50000).toString().substr(0,10),{from: accounts[3]});
        //         res = await pair.getDeep.call( web3.utils.toBN('-80168'));
        //         console.log(' deep:', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        // console.log(' tick', (await pair.currentTick.call()).toString());
        // res = await pair.getLimitTokens.call( web3.utils.toBN('-80168'), accounts[3], buyShare, false);
        // console.log(' accounts[3] -80168 ', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        // //console.log(await pair.isExploited.call(web3.utils.toBN('-80168'), 0));
        // console.log(await pair.isExploited.call(web3.utils.toBN('-80168'), 1));
        });
});

contract('LimitswapMine', (accounts) => {
    it('should be set by owner', async () =>{
        const miner = await LimitswapMine.deployed();
        const token = await LimitswapToken.deployed();
        await token.transferOwnership(miner.address, {from: accounts[0]});
        const testCoinA = await TestCoinA.deployed();
        await miner.add('100', testCoinA.address, {from: accounts[0]});
    });
    it('should generate tokens by mining', async () =>{
        const miner = await LimitswapMine.deployed();
        const token = await LimitswapToken.deployed();
        const testCoinA = await TestCoinA.deployed();
        await testCoinA.mint(accounts[1], web3.utils.toWei('100'), {from: accounts[1]});
        await testCoinA.approve(miner.address, web3.utils.toWei('99999999999'), {from: accounts[1]});
        console.log('max supply: ', web3.utils.fromWei(await miner.maxSupply.call()));
        console.log('accounts[1] mine:');
        await miner.deposit('0', web3.utils.toWei('1'), {from: accounts[1]});
        console.log(' pending: ', web3.utils.fromWei(await miner.pendingAmount.call('0', accounts[1])), ' @ ', await web3.eth.getBlockNumber());
        await testCoinA.mint(accounts[1], web3.utils.toWei('0'), {from: accounts[1]});
        console.log(' pending: ', web3.utils.fromWei(await miner.pendingAmount.call('0', accounts[1])), ' @ ', await web3.eth.getBlockNumber());
        console.log( 'accounts[1] LSP balance: ', web3.utils.fromWei(await token.balanceOf.call(accounts[1])));
        await miner.claim('0', {from: accounts[1]});
        console.log( 'accounts[1] LSP balance: ', web3.utils.fromWei(await token.balanceOf.call(accounts[1])));
        await testCoinA.mint(accounts[1], web3.utils.toWei('0'), {from: accounts[1]});
        await testCoinA.mint(accounts[1], web3.utils.toWei('0'), {from: accounts[1]});
        console.log(' pending: ', web3.utils.fromWei(await miner.pendingAmount.call('0', accounts[1])), ' @ ', await web3.eth.getBlockNumber());
        var balance0 = await testCoinA.balanceOf.call(accounts[1]);
        await miner.withdraw('0', await miner.depositedAmount.call('0', accounts[1]), {from: accounts[1]});
        var balance1 = await testCoinA.balanceOf.call(accounts[1]);
        console.log(' withdrawTestCoinA: ', web3.utils.fromWei(balance1.sub(balance0)));
        console.log(' should be 0: ',web3.utils.fromWei(await miner.depositedAmount.call('0', accounts[1])));
    });
    it('should stop mining when reaching maxSupply', async () =>{
        const token = await LimitswapToken.new({from: accounts[0]});
        const miner = await LimitswapMine.new(token.address, '1000000000000000000', '0', '1000000000000000000');
        const testCoinA = await TestCoinA.deployed();
        await testCoinA.mint(accounts[1], web3.utils.toWei('100'), {from: accounts[1]});
        await testCoinA.approve(miner.address, web3.utils.toWei('99999999999'), {from: accounts[1]});
        await token.transferOwnership(miner.address, {from: accounts[0]});
        await miner.add('100', testCoinA.address, {from: accounts[0]});
        console.log('max supply: ', web3.utils.fromWei(await miner.maxSupply.call()));
        console.log('accounts[1] mine:');
        await miner.deposit('0', web3.utils.toWei('1'), {from: accounts[1]});
        console.log(' pending: ', web3.utils.fromWei(await miner.pendingAmount.call('0', accounts[1])), ' @ ', await web3.eth.getBlockNumber());
        await testCoinA.mint(accounts[1], web3.utils.toWei('0'), {from: accounts[1]});
        console.log(' pending: ', web3.utils.fromWei(await miner.pendingAmount.call('0', accounts[1])), ' @ ', await web3.eth.getBlockNumber());
        console.log( 'accounts[1] LSP balance: ', web3.utils.fromWei(await token.balanceOf.call(accounts[1])));
        await miner.claim('0', {from: accounts[1]});
        console.log( 'accounts[1] LSP balance: ', web3.utils.fromWei(await token.balanceOf.call(accounts[1])));
        await testCoinA.mint(accounts[1], web3.utils.toWei('0'), {from: accounts[1]});
        console.log(' pending: ', web3.utils.fromWei(await miner.pendingAmount.call('0', accounts[1])), ' @ ', await web3.eth.getBlockNumber());
        var balance0 = await testCoinA.balanceOf.call(accounts[1]);
        await miner.withdraw('0', await miner.depositedAmount.call('0', accounts[1]), {from: accounts[1]});
        var balance1 = await testCoinA.balanceOf.call(accounts[1]);
        console.log(' withdrawTestCoinA: ', web3.utils.fromWei(balance1.sub(balance0)));
        console.log(' should be 0: ',web3.utils.fromWei(await miner.depositedAmount.call('0', accounts[1])));
    });
});

contract('Test for USDT', (accounts) => {
    it('should endure test', async () =>{
        //(5 ETH, 100A), (100A, 20000B)
        const router = await LimitswapRouter.deployed();
        var testCoinU = await TestCoinU.new();
        const weth = await WETH.deployed();
        while (testCoinU.address > weth.address) {
            testCoinU = await TestCoinU.new();
        }
        await testCoinU.mint(accounts[3], web3.utils.toBN(web3.utils.toWei('2000')), {from: accounts[3]});
        await testCoinU.approve(router.address, web3.utils.toBN(web3.utils.toWei('654474745')), {from: accounts[3]});
        await router.addLiquidityETH(testCoinU.address, '1000000',
            '0','0',(Date.now()+50000).toString().substr(0,10), {from: accounts[3], value: web3.utils.toWei('0.01')});
        const info1 = await router.getPairInfo.call(testCoinU.address, weth.address);
        const pair = await LimitswapPair.at(info1[2]);
        console.log(' LP: ', web3.utils.fromWei(await pair.balanceOf.call(accounts[3])));
        await pair.approve(router.address, web3.utils.toBN(web3.utils.toWei('654474745')), {from: accounts[3]});
        console.log(' tick', (await pair.currentTick.call()).toString());
        await router.putLimitOrderETH(info1[2],web3.utils.toBN('230170'),{from: accounts[3], value: web3.utils.toWei('0.001')});
        res = await pair.getDeep.call( web3.utils.toBN('230170'));
        console.log(' deep:', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        console.log(' tick', (await pair.currentTick.call()).toString());
        var sellShare = await pair.sellShare.call(accounts[3],web3.utils.toBN('230170'));
        res = await pair.getLimitTokens.call( web3.utils.toBN('230170'), accounts[3], sellShare, true);
        console.log(' accounts[3] 230170 ', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        var buyShare = await pair.buyShare.call(accounts[3],web3.utils.toBN('230170'));
        res = await pair.getLimitTokens.call( web3.utils.toBN('230170'), accounts[3], buyShare, false);
        console.log(' accounts[3] 230170 ', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        res = await router.cancelLimitOrder.call(info1[2], web3.utils.toBN('230170'), buyShare, false, {from:accounts[3]});
        console.log(' call cancel:', web3.utils.fromWei(res[0]), web3.utils.fromWei(res[1]));

        console.log('swap');
        console.log(web3.utils.fromWei((await router.getAmountOut.call('50000',[testCoinU.address, weth.address]))[0]));
        await router.swapExactTokensForETH('50000',
                '0', [testCoinU.address, weth.address],accounts[3],
                (Date.now()+50000).toString().substr(0,10),{from: accounts[3]});
        res = await pair.getDeep.call( web3.utils.toBN('230170'));
        console.log(await pair.isExploited.call(web3.utils.toBN('230170'), 1));
        console.log(' deep:', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        console.log(' tick', (await pair.currentTick.call()).toString());
        res = await pair.getLimitTokens.call( web3.utils.toBN('230170'), accounts[3], buyShare, false);
        console.log(' accounts[3] 230170 ', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');

        console.log('cancel');
        await router.cancelLimitOrder(info1[2], '230170', '100000000', false, {from:accounts[3]});

        console.log('put');
        await router.putLimitOrder(info1[2], testCoinU.address, '80000', '230161', {from:accounts[3]});

        console.log('cancel');
        await router.cancelLimitOrder(info1[2], '230170', '180000000', false, {from:accounts[3]});

        await weth.deposit({from:accounts[3], value:web3.utils.toWei('1')});
        console.log(web3.utils.fromWei(await weth.balanceOf.call(accounts[3])).toString());
        await weth.approve(router.address, web3.utils.toWei('1'),{from:accounts[3]});

        console.log('swap');
        //console.log(web3.utils.fromWei((await router.getAmountOut.call(web3.utils.toBN(web3.utils.toWei('2')),[testCoinA.address, weth.address]))[0]));
        await router.swapExactTokensForTokens(web3.utils.toBN(web3.utils.toWei('0.001')),
                '0', [weth.address, testCoinU.address],accounts[3],
                (Date.now()+50000).toString().substr(0,10),{from: accounts[3]});
                res = await pair.getDeep.call( web3.utils.toBN('-80168'));
                console.log(' deep:', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        console.log(' tick', (await pair.currentTick.call()).toString());

        console.log('remove');
        await router.removeLiquidity(weth.address, testCoinU.address,
            '10000000000', (Date.now()+50000).toString().substr(0,10),{from: accounts[3]});
        console.log(' tick', (await pair.currentTick.call()).toString());

        res = await pair.getDeep.call( web3.utils.toBN('230161'));
        console.log(await pair.isExploited.call(web3.utils.toBN('230161'), 1));
        console.log(' deep:', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        console.log(' tick', (await pair.currentTick.call()).toString());
        var sellShare = await pair.sellShare.call(accounts[3],web3.utils.toBN('230161'));
        console.log(sellShare.toString());
        res = await pair.getLimitTokens.call( web3.utils.toBN('230161'), accounts[3], sellShare, true);
        console.log(' accounts[3] 230161 ', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        console.log(await pair.isExploited.call(web3.utils.toBN('230161'), 0));
        console.log(await pair.isExploited.call(web3.utils.toBN('230161'), 1));
        var sellShare = await pair.sellShare.call(accounts[3],web3.utils.toBN('230161'));
        console.log(sellShare.toString());
        await router.cancelLimitOrder(info1[2], web3.utils.toBN('230161'), sellShare, true, {from:accounts[3]});
        console.log(' a: ',(await pair.sellShare.call(accounts[3],web3.utils.toBN('230161'))).toString());
        res = await router.cancelLimitOrder.call(info1[2], web3.utils.toBN('230161'), sellShare, true, {from:accounts[3]});
        await pair.cancelLimitOrder(web3.utils.toBN('230161'), sellShare, true, {from:accounts[3]});
        //console.log(' accounts[3] 230161 ', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        console.log(' accounts[3] 230161 ', web3.utils.toBN(res[0]).toString(), ' A ', web3.utils.toBN(res[1]).toString(), ' B ');

        // await router.getAmountOut.call(web3.utils.toBN(web3.utils.toWei('115')),[testCoinA.address, weth.address]);
        // await router.swapExactTokensForETH(web3.utils.toBN(web3.utils.toWei('300')),
        //         '0', [testCoinA.address, weth.address],accounts[3],
        //         (Date.now()+50000).toString().substr(0,10),{from: accounts[3]});
        //         res = await pair.getDeep.call( web3.utils.toBN('-80168'));
        //         console.log(' deep:', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        // console.log(' tick', (await pair.currentTick.call()).toString());
        // res = await pair.getLimitTokens.call( web3.utils.toBN('-80168'), accounts[3], buyShare, false);
        // console.log(' accounts[3] -80168 ', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        // //console.log(await pair.isExploited.call(web3.utils.toBN('-80168'), 0));
        // console.log(await pair.isExploited.call(web3.utils.toBN('-80168'), 1));
        });
});

contract('Test for USDT 2', (accounts) => {
    it('should endure test', async () =>{
        //(5 ETH, 100A), (100A, 20000B)
        const router = await LimitswapRouter.deployed();
        var testCoinU = await TestCoinU.new();
        const weth = await WETH.deployed();
        while (testCoinU.address > weth.address) {
            testCoinU = await TestCoinU.new();
        }
        await testCoinU.mint(accounts[3], web3.utils.toBN(web3.utils.toWei('2000')), {from: accounts[3]});
        await testCoinU.approve(router.address, web3.utils.toBN(web3.utils.toWei('654474745')), {from: accounts[3]});
        await router.addLiquidityETH(testCoinU.address, '2000000', '0','0',
            (Date.now()+50000).toString().substr(0,10), {from: accounts[3], value: web3.utils.toWei('0.01')});
        const info1 = await router.getPairInfo.call(testCoinU.address, weth.address);
        const pair = await LimitswapPair.at(info1[2]);
        console.log(' LP: ', web3.utils.fromWei(await pair.balanceOf.call(accounts[3])));
        await pair.approve(router.address, web3.utils.toBN(web3.utils.toWei('654474745')), {from: accounts[3]});
        console.log(' tick', (await pair.currentTick.call()).toString());

        await router.putLimitOrderETH(info1[2],web3.utils.toBN('223288'),{from: accounts[3], value: web3.utils.toWei('0.003')});
        res = await pair.getDeep.call( web3.utils.toBN('223288'));
        console.log(' deep:', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        console.log(' tick', (await pair.currentTick.call()).toString());
        var sellShare = await pair.sellShare.call(accounts[3],web3.utils.toBN('223288'));
        res = await pair.getLimitTokens.call( web3.utils.toBN('223288'), accounts[3], sellShare, true);
        console.log(' accounts[3] 223288 ', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        var buyShare = await pair.buyShare.call(accounts[3],web3.utils.toBN('223288'));
        res = await pair.getLimitTokens.call( web3.utils.toBN('223288'), accounts[3], buyShare, false);
        console.log(' accounts[3] 223288 ', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        res = await router.cancelLimitOrder.call(info1[2], web3.utils.toBN('223288'), buyShare, false, {from:accounts[3]});
        console.log(' call cancel:', web3.utils.fromWei(res[0]), web3.utils.fromWei(res[1]));

        console.log('swap');
        console.log(web3.utils.fromWei((await router.getAmountOut.call('500000',[testCoinU.address, weth.address]))[0]));
        await router.swapExactTokensForETH('500000',
                '0', [testCoinU.address, weth.address],accounts[3],
                (Date.now()+50000).toString().substr(0,10),{from: accounts[3]});
        res = await pair.getDeep.call( web3.utils.toBN('223288'));
        console.log(await pair.isExploited.call(web3.utils.toBN('223288'), 1));
        console.log(' deep:', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        console.log(' tick', (await pair.currentTick.call()).toString());
        res = await pair.getLimitTokens.call( web3.utils.toBN('223288'), accounts[3], buyShare, false);
        console.log(' accounts[3] 223288 ', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');

        console.log('put');
        await router.putLimitOrder(info1[2], testCoinU.address, '500000', '223239', {from:accounts[3]});
        console.log(' tick', (await pair.currentTick.call()).toString());

        console.log('swap');
        //console.log(web3.utils.fromWei((await router.getAmountOut.call(web3.utils.toBN(web3.utils.toWei('2')),[testCoinA.address, weth.address]))[0]));
        await router.swapExactETHForTokens(
                '0', [weth.address, testCoinU.address],accounts[3],
                (Date.now()+50000).toString().substr(0,10),
                {from: accounts[3], value:web3.utils.toWei('0.003')});
                res = await pair.getDeep.call( web3.utils.toBN('-80168'));
                console.log(' deep:', web3.utils.fromWei(res[0]).toString(), ' A ', web3.utils.fromWei(res[1]).toString(), ' B ');
        console.log(' tick', (await pair.currentTick.call()).toString());

        console.log('remove');
        await router.removeLiquidity(weth.address, testCoinU.address,
            await pair.balanceOf.call(accounts[3]), (Date.now()+50000).toString().substr(0,10),{from: accounts[3]});
        console.log(' tick', (await pair.currentTick.call()).toString());

        console.log('cancel');
        console.log(' liquidity', (await pair.liquidity.call()).toString());
        console.log(' currentSqrtPriceX96', (await pair.currentSqrtPriceX96.call()).toString());
        res = await router.cancelLimitOrder.call(info1[2], web3.utils.toBN('223288'), buyShare, false, {from:accounts[3]});
        console.log(' call cancel:', web3.utils.fromWei(res[0]), web3.utils.fromWei(res[1]));

        });
});
