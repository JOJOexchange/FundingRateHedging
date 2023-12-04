// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {console} from "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/Impl/FundingRateArbitrage.sol";
import "./utils/EIP712Test.sol";
import "./mock/TestERC20.sol";
import "./mock/MockUSDCPrice.sol";
import "./mock/MockChainLinkWSTETH.sol";
import "./mock/MockChainLinkETH.sol";
import "./mock/SupportsSWAP.sol";
import "@JUSDV1/src/Impl/JUSDBank.sol";
import "@JUSDV1/src/oracle/JOJOOracleAdaptor.sol";
import "@JOJO/contracts/impl/JOJODealer.sol";
import "@JOJO/contracts/adaptor/OracleAdaptor.sol";
import "@JOJO/contracts/lib/Types.sol";
import "@JOJO/contracts/impl/Perpetual.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Utils} from "./utils/Utils.sol";

contract FundingRateInit is Test {
    FundingRateArbitrage public fundingRateArbitrage;
    Utils internal utils;
    TestERC20 public wstETH;
    JUSDBank public jusdBank;
    TestERC20 public jusd;
    TestERC20 public USDC;
    Perpetual public perpetual;
    JOJOOracleAdaptor public wstETHOracle;
    OracleAdaptor public ETHOracle;
    MockChainLinkETH public mockEth;
    MockChainLinkWSTETH public mockWstEth;
    MockUSDCPrice public usdcPrice;
    JOJODealer public jojoDealer;
    SupportsSWAP public swapContract;


     address payable[] internal users;
     address internal alice;
     address internal bob;
     address internal insurance;
     address internal operator;
     address internal Owner;
     address internal orderSender;
     address internal fastWithdraw;

     address internal sender1;
     address internal sender2;
     address internal sender3;



     uint256 internal sender1PrivateKey;
     uint256 internal sender2PrivateKey;
     uint256 internal sender3PrivateKey;

     function initUsers() public {
         // users
         utils = new Utils();
         users = utils.createUsers(10);
         alice = users[0];
         vm.label(alice, "Alice");
         bob = users[1];
         vm.label(bob, "Bob");
         insurance = users[2];
         vm.label(insurance, "Insurance");
         operator = users[3];
         vm.label(operator, "operator");
         Owner = users[4];
         vm.label(Owner, "Owner");
         orderSender = users[5];
         vm.label(orderSender, "orderSender");
         fastWithdraw = users[6];
         vm.label(fastWithdraw, "fastWithdraw");


         sender1PrivateKey = 0xA11CE;
         sender2PrivateKey = 0xB0B;
         sender3PrivateKey = 0xC0C;

         sender1 = vm.addr(sender1PrivateKey);
         sender2 = vm.addr(sender2PrivateKey);
         sender3 = vm.addr(sender3PrivateKey);

     }

     function initJUSDBank() public {

         wstETHOracle = new JOJOOracleAdaptor(
             address(mockWstEth),
             20,
             86400,
             address(usdcPrice),
             86400
         );
         //bank
         jusdBank = new JUSDBank(
             // maxReservesAmount_
             10,
             insurance,
             address(jusd),
             address(jojoDealer),
             // maxBorrowAmountPerAccount_
             100000000000,
             // maxBorrowAmount_
             100000000001,
             // borrowFeeRate_
             0,
             address(USDC)
         );

         jusdBank.initReserve(
             // token
             address(wstETH),
             // initialMortgageRate
             8e17,
             // maxDepositAmount
             4000e18,
             // maxDepositAmountPerAccount
             2030e18,
             // maxBorrowValue
             100000e6,
             // liquidateMortgageRate
             825e15,
             // liquidationPriceOff
             5e16,
             // insuranceFeeRate
             1e17,
             address(wstETHOracle)
         );

         jusd.mint(address(jusdBank), 100000e6);
     }

     function initFundingRateSetting() public {
         fundingRateArbitrage = new FundingRateArbitrage(
             //  _collateral,
             address(wstETH),
             // _jusdBank
             address(jusdBank),
             // _JOJODealer
             address(jojoDealer),
             // _perpMarket
             address(perpetual),
             // _Operator
             operator,
             //_USDC
             address(USDC),
             // jusd
             address(jusd));

         fundingRateArbitrage.transferOwnership(Owner);
         vm.startPrank(Owner);
         jusd.mint(address(fundingRateArbitrage), 10000e6);
         fundingRateArbitrage.setOperator(sender1, true);
         fundingRateArbitrage.setMaxNetValue(10000e6);
         vm.stopPrank();

     }

     function initJOJODealer() public {
         jojoDealer.setMaxPositionAmount(10);
         jojoDealer.setOrderSender(orderSender, true);
         jojoDealer.setWithdrawTimeLock(10);
         Types.RiskParams memory param = Types.RiskParams({
             initialMarginRatio: 5e16,
             liquidationThreshold: 3e16,
             liquidationPriceOff: 1e16,
             insuranceFeeRate: 2e16,
             markPriceSource: address(ETHOracle),
             name: "ETH",
             isRegistered: true});
         jojoDealer.setPerpRiskParams(address(perpetual), param);
         jojoDealer.setFastWithdrawalWhitelist(fastWithdraw, true);
         jojoDealer.setSecondaryAsset(address(jusd));

     }

     function initSupportSWAP() public {
         swapContract = new SupportsSWAP(
             address(USDC),
             address(wstETH),
             address(wstETHOracle)
         );
         USDC.mint(address(swapContract), 100000e6);
         wstETH.mint(address(swapContract), 10000e18);

     }

    function setUp() public {
        wstETH = new TestERC20("wstETH", "wstETH", 18);
        jusd = new TestERC20("jusd", "jusd", 6);
        USDC = new TestERC20("usdc", "usdc", 6);
        mockEth = new MockChainLinkETH();
        mockWstEth = new MockChainLinkWSTETH();
        usdcPrice = new MockUSDCPrice();
        ETHOracle = new OracleAdaptor(
            address(mockEth),
            20,
            86400,
            86400,
            address(usdcPrice),
            1e16
        );
         initUsers();
         jojoDealer = new JOJODealer(address(USDC));
         perpetual = new Perpetual(address(jojoDealer));
         initJOJODealer();
         initJUSDBank();
         initFundingRateSetting();
         initSupportSWAP();
    }

     function initAlice() public {
         USDC.mint(alice, 100e6);
         vm.startPrank(alice);
         USDC.approve(address(fundingRateArbitrage), 100e6);
     }

     function testDepositFromLP() public {
         initAlice();
         fundingRateArbitrage.deposit(100e6);
         vm.stopPrank();
     }


     function testDepositFromLPSetRate() public {
         vm.startPrank(Owner);
         fundingRateArbitrage.setDepositFeeRate(1e16);
         vm.stopPrank();
         initAlice();
         fundingRateArbitrage.deposit(100e6);
         vm.stopPrank();
         assertEq(IERC20(USDC).balanceOf(Owner), 1e6);
     }

     function testWithdrawFromLP1() public {
        
         initAlice();
         fundingRateArbitrage.deposit(100e6);
         jojoDealer.requestWithdraw(alice, 0, 100e6);
         vm.warp(100);
         jojoDealer.executeWithdraw(alice, alice, false, "");
         jusd.approve(address(fundingRateArbitrage), 100e6);
         uint256 index = fundingRateArbitrage.requestWithdraw(100e6);
         vm.stopPrank();

         vm.startPrank(Owner);
         uint256[] memory indexs = new uint256[](1);
         indexs[0] = index;
         fundingRateArbitrage.permitWithdrawRequests(indexs);

         assertEq(USDC.balanceOf(alice), 100e6);
     }


     function testWithdrawFromLPWithRate() public {
         vm.startPrank(Owner);
         fundingRateArbitrage.setDepositFeeRate(1e16);
         fundingRateArbitrage.setWithdrawFeeRate(1e16);
         vm.stopPrank();

         initAlice();
         fundingRateArbitrage.deposit(100e6);
         jojoDealer.requestWithdraw(alice, 0, 99e6);
         vm.warp(100);
         jojoDealer.executeWithdraw(alice, alice, false, "");
         jusd.approve(address(fundingRateArbitrage), 99e6);
         uint256 index = fundingRateArbitrage.requestWithdraw(99e6);
         vm.stopPrank();

         vm.startPrank(Owner);
         uint256[] memory indexs = new uint256[](1);
         indexs[0] = index;
         fundingRateArbitrage.permitWithdrawRequests(indexs);

         assertEq(USDC.balanceOf(alice), 9801e4);
     }



     function buildOrder(address signer, uint256 privateKey,int128 paper, int128 credit) public view returns (Types.Order memory order, bytes memory signature) {

         int64 makerFeeRate = 2e14;
         int64 takerFeeRate = 7e14;

         bytes memory infoBytes = abi.encodePacked(
             makerFeeRate,
             takerFeeRate,
             uint64(block.timestamp),
             uint64(block.timestamp)
         );

         order = Types.Order({
             perp: address(perpetual),
             signer: signer,
             paperAmount: paper,
             creditAmount: credit,
             info: bytes32(infoBytes)
         });

         bytes32 domainSeparator = EIP712Test._buildDomainSeparator(
             "JOJO",
             "1",
             address(jojoDealer));
         bytes32 structHash = EIP712Test._structHash(order);
         bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

         (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
         signature = abi.encodePacked(r, s, v);
     }

     function constructTradeData() internal view returns (bytes memory) {
         (Types.Order memory order1, bytes memory signature1) =
             buildOrder(sender1, sender1PrivateKey, -2e18, 990e6);

         (Types.Order memory order2, bytes memory signature2) =
             buildOrder(sender2, sender2PrivateKey, 1e18, -1010e6);

         (Types.Order memory order3, bytes memory signature3) =
             buildOrder(sender3, sender3PrivateKey, 1e18, -1000e6);

         Types.Order[] memory orderList = new Types.Order[](3);
         orderList[0] = order1;
         orderList[1] = order2;
         orderList[2] = order3;
         bytes[] memory signatureList = new bytes[](3);
         signatureList[0] = signature1;
         signatureList[1] = signature2;
         signatureList[2] = signature3;
         uint256[] memory matchPaperAmount = new uint256[](3);
         matchPaperAmount[0] = 2e18;
         matchPaperAmount[1] = 1e18;
         matchPaperAmount[2] = 1e18;
         return abi.encode(orderList, signatureList, matchPaperAmount);
     }

     function testOpenNormalPositionTrade() public {
         vm.startPrank(sender1);
         USDC.mint(sender1, 15000e6);
         USDC.approve(address(jojoDealer), 15000e6);
         jojoDealer.deposit(5000e6, 0, sender1);
         jojoDealer.deposit(5000e6, 0, sender2);
         jojoDealer.deposit(5000e6, 0, sender3);
         vm.stopPrank();

         vm.startPrank(orderSender);
         bytes memory tradeData = constructTradeData();
         perpetual.trade(tradeData);
     }

     function constructTradeDataForPool (int128 order1Amount, int128 order1Credit, int128 order2Amount, int128 order2Credit)
          internal view returns (bytes memory) {
         (Types.Order memory order1, bytes memory signature1) =
             buildOrder(address(fundingRateArbitrage), sender1PrivateKey, order1Amount, order1Credit);

         (Types.Order memory order2, bytes memory signature2) =
             buildOrder(sender2, sender2PrivateKey, order2Amount, order2Credit);

         Types.Order[] memory orderList = new Types.Order[](2);
         orderList[0] = order1;
         orderList[1] = order2;
         bytes[] memory signatureList = new bytes[](2);
         signatureList[0] = signature1;
         signatureList[1] = signature2;
         uint256[] memory matchPaperAmount = new uint256[](2);
         matchPaperAmount[0] = 1e18;
         matchPaperAmount[1] = 1e18;
         return abi.encode(orderList, signatureList, matchPaperAmount);
     }


     function testPoolOpenPosition() public {
         USDC.mint(alice, 2400e6);
         vm.startPrank(alice);
         USDC.approve(address(fundingRateArbitrage), 2400e6);
         fundingRateArbitrage.deposit(2400e6);
         vm.stopPrank();

         vm.startPrank(sender2);
         USDC.mint(sender2, 5000e6);
         USDC.approve(address(jojoDealer), 5000e6);
         jojoDealer.deposit(5000e6, 0, sender2);
         vm.stopPrank();

        // open position
         vm.startPrank(Owner);

         uint256 minReceivedCollateral = 2e18;
         uint256 JUSDRebalanceAmount = 1500e6;

         bytes memory swapData = swapContract.getSwapBuyWstethData(2400e6, address(wstETH));
         bytes memory spotTradeParam = abi.encode(
             address(swapContract),
             address(swapContract),
             2400e6,
             swapData
         );

         bytes memory tradeData = constructTradeDataForPool(-1e18, 990e6, 1e18, -1010e6);

        fundingRateArbitrage.openPosition(minReceivedCollateral, JUSDRebalanceAmount, spotTradeParam);
        vm.stopPrank();

        vm.startPrank(orderSender);
        perpetual.trade(tradeData);

         (int256 paper, int256 credit) = perpetual.balanceOf(address(fundingRateArbitrage));
         console.logInt(paper);
         console.logInt(credit);
     }


     function testPoolClosePosition() public {
         USDC.mint(alice, 2400e6);
         vm.startPrank(alice);
         USDC.approve(address(fundingRateArbitrage), 2400e6);
         fundingRateArbitrage.deposit(2400e6);
         vm.stopPrank();

         vm.startPrank(sender2);
         USDC.mint(sender2, 5000e6);
         USDC.approve(address(jojoDealer), 5000e6);
         jojoDealer.deposit(5000e6, 0, sender2);
         vm.stopPrank();

         vm.startPrank(Owner);
         uint256 minReceivedCollateral = 2e18;
         uint256 JUSDRebalanceAmount = 1500e6;
         bytes memory swapData = swapContract.getSwapBuyWstethData(2400e6, address(wstETH));
         bytes memory spotTradeParam = abi.encode(
             address(swapContract),
             address(swapContract),
             2400e6,
             swapData
         );

         bytes memory tradeData = constructTradeDataForPool(-1e18, 990e6, 1e18, -1010e6);

        fundingRateArbitrage.openPosition(minReceivedCollateral, JUSDRebalanceAmount, spotTradeParam);
        vm.stopPrank();

        vm.startPrank(orderSender);
        perpetual.trade(tradeData);

         (int256 paper, int256 credit) = perpetual.balanceOf(address(fundingRateArbitrage));
         console.logInt(paper);
         console.logInt(credit);

         // close position
         uint256 minReceivedUSDC = 2400e6;
         uint256 JUSDRebalanceAmount2 = 1500e6;
         uint256 collateralAmount = 2e18;
         bytes memory swapData2 = swapContract.getSwapBuyUSDChData(2e18, address(wstETH));
         bytes memory spotTradeParam2 = abi.encode(
             address(swapContract),
             address(swapContract),
             2e18,
             swapData2
         );

         bytes memory tradeData2 = constructTradeDataForPool(1e18, -1000e6, -1e18, 990e6);


        perpetual.trade(tradeData2);
        vm.stopPrank();

        vm.startPrank(Owner);
        fundingRateArbitrage.closePosition(minReceivedUSDC, JUSDRebalanceAmount2, collateralAmount, spotTradeParam2);
        vm.stopPrank();
     }

    function burnJUSD() public {
        fundingRateArbitrage.burnJUSD(10000e6);
        assertEq(IERC20(jusd).balanceOf(Owner), 10000e6);
    }

}
