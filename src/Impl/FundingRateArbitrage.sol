/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1*/

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@JOJO/contracts/intf/IDealer.sol";
import "@JOJO/contracts/intf/IPerpetual.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@JUSDV1/src/Interface/IJUSDBank.sol";
import "@JUSDV1/src/lib/DecimalMath.sol";

pragma solidity 0.8.9;

struct WithdrawalRequest {
    uint256 amount; // EarnUSDC
    address user;
    bool executed;
}

contract FundingRateArbitrage is Ownable {
    address public immutable Collateral;
    address public immutable JusdBank;
    address public immutable JOJODealer;
    address public immutable PerpMarket;
    address public immutable USDC;
    address public immutable JUSD;
    uint256 public maxNetValue;

    WithdrawalRequest[] public WithdrawalRequests;
    mapping(address => uint256) public EarnUSDCBalance;
    mapping(address => uint256) public JUSDOutside;
    uint256 public totalEarnUSDCBalance;

    uint256 public depositFeeRate;
    uint256 public withdrawFeeRate;
    uint256 public withdrawSettleFee; // USDC

    using SafeERC20 for IERC20;
    using DecimalMath for uint256;

    event Swap(
        address fromToken,
        address toToken,
        uint256 payAmount,
        uint256 receivedAmount
    );


    // =========================Event===================

    event DepositToHedging(address from, uint256 USDCAmount, uint256 feeAmount, uint256 earnUSDCAmount);

    event RequestWithdrawFromHedging(address from, uint256 JUSDAmount, uint256 withdrawEarnUSDCAmount, uint256 index);
    event PermitWithdraw(address from, uint256 USDCAmount, uint256 feeAmount, uint256 earnUSDCAmount);


    // =========================Consturct===================

    constructor(
        address _collateral,
        address _jusdBank,
        address _JOJODealer,
        address _perpMarket,
        address _Operator,
        address _USDC,
        address _JUSD
    ) Ownable() {
        // set params
        Collateral = _collateral;
        JusdBank = _jusdBank;
        JOJODealer = _JOJODealer;
        PerpMarket = _perpMarket;
        USDC = _USDC;
        JUSD = _JUSD;

        // set operator
        IDealer(JOJODealer).setOperator(_Operator, true);

        // approve to JUSDBank & JOJODealer
        IERC20(Collateral).approve(JusdBank, type(uint256).max);
        IERC20(JUSD).approve(JusdBank, type(uint256).max);
        IERC20(JUSD).approve(JOJODealer, type(uint256).max);
        IERC20(USDC).approve(JOJODealer, type(uint256).max);
    }

    // =========================View========================

    function getNetValue() public view returns (uint256) {
        uint256 JUSDBorrowed =  IJUSDBank(JusdBank).getBorrowBalance(address(this));

        uint256 collateralAmount = IJUSDBank(JusdBank).getDepositBalance(
            Collateral,
            address(this)
        );
        uint256 USDCBuffer = IERC20(USDC).balanceOf(address(this));
        uint256 collateralPrice = IJUSDBank(JusdBank).getCollateralPrice(
            Collateral
        );
        (int256 perpNetValue, ,, ) = IDealer(JOJODealer).getTraderRisk(
            address(this)
        );
        return SafeCast.toUint256(perpNetValue) +
                          collateralAmount.decimalMul(collateralPrice) +
                          USDCBuffer - JUSDBorrowed;
    }

    function getIndex() public view returns (uint256) {
        if(totalEarnUSDCBalance == 0){
            return 1e18;
        } else {
            return DecimalMath.decimalDiv(getNetValue(), totalEarnUSDCBalance);
        }
    }

    function getCollateral() public view returns(address) {
        return Collateral;
    }

    function getTotalEarnUSDCBalance() public view returns(uint256) {
        return totalEarnUSDCBalance;
    }

    // =========================Only Owner Parameter set==================

    function setOperator(address operator, bool isValid) public onlyOwner {
        IDealer(JOJODealer).setOperator(operator, isValid);
    }

    function setMaxNetValue(uint256 newMaxNetValue) public onlyOwner {
        maxNetValue = newMaxNetValue;
    }

    function setDepositFeeRate(uint256 newDepositFeeRate)public onlyOwner {
        depositFeeRate = newDepositFeeRate;
    }

    function setWithdrawFeeRate(uint256 newWithdrawFeeRate)public onlyOwner {
        withdrawFeeRate = newWithdrawFeeRate;
    }

    function setWithdrawSettleFee(uint256 newWithdrawSettleFee)public onlyOwner {
        withdrawSettleFee = newWithdrawSettleFee;
    }

    // ==================== Position changes =============

    // collateral add
    function openPosition(
        uint256 minReceivedCollateral,
        uint256 JUSDRebalanceAmount,
        bytes memory spotTradeParam
    ) public onlyOwner {
        uint256 receivedCollateral = _swap(spotTradeParam, true);
        require(receivedCollateral >= minReceivedCollateral, "SWAP SLIPPAGE");
        _depositToJUSDBank(IERC20(Collateral).balanceOf(address(this)));
        rebalanceToPerp(JUSDRebalanceAmount);
    }

    // collateral remove
    function closePosition(
        uint256 minReceivedUSDC,
        uint256 JUSDRebalanceAmount,
        uint256 collateralAmount,
        bytes memory spotTradeParam
    ) public onlyOwner {
        rebalanceToJUSDBank(JUSDRebalanceAmount);
        _withdrawFromJUSDBank(collateralAmount);
        uint256 receivedUSDC = _swap(spotTradeParam, false);
        require(receivedUSDC >= minReceivedUSDC, "SWAP SLIPPAGE");
    }

    // Swap without check received
    function _swap(
        bytes memory param,
        bool buyCollteral
    ) private returns (uint256 receivedAmount) {
        address fromToken;
        address toToken;
        if (buyCollteral) {
            fromToken = USDC;
            toToken = Collateral;
        } else {
            fromToken = Collateral;
            toToken = USDC;
        }
        uint256 toTokenReserve = IERC20(toToken).balanceOf(address(this));

        (
            address approveTarget,
            address swapTarget,
            uint256 payAmount,
            bytes memory callData
        ) = abi.decode(param, (address, address, uint256, bytes));

        IERC20(fromToken).safeApprove(approveTarget, payAmount);
        (bool success, ) = swapTarget.call(callData);
        if (!success) {
            assembly {
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                revert(ptr, size)
            }
        }

        receivedAmount =
            IERC20(toToken).balanceOf(address(this)) -
            toTokenReserve;
        emit Swap(fromToken, toToken, payAmount, receivedAmount);
    }

    // JUSD

    function rebalanceToPerp(uint256 JUSDAmount) public onlyOwner {
        IJUSDBank(JusdBank).borrow(JUSDAmount, address(this), true);
    }

    function rebalanceToJUSDBank(uint256 JUSDRebalanceAmount) public onlyOwner {
        IDealer(JOJODealer).fastWithdraw(address(this), address(this), 0, JUSDRebalanceAmount, false, "");
        _repayJUSD(JUSDRebalanceAmount);
    }

    // =============== JUSDBank Operations =================
    // borrow repay withdraw deposit

    function _borrowJUSD(uint256 JUSDAmount) internal {
        IJUSDBank(JusdBank).borrow(JUSDAmount, address(this), true);
    }

    function _repayJUSD(uint256 amount) internal {
        IJUSDBank(JusdBank).repay(amount, address(this));
    }

    function _withdrawFromJUSDBank(uint256 amount) internal {
        IJUSDBank(JusdBank).withdraw(Collateral, amount, address(this), false);
    }

    function _depositToJUSDBank(uint256 amount) internal {
        // deposit to JUSDBank
        IJUSDBank(JusdBank).deposit(
            address(this),
            Collateral,
            amount,
            address(this)
        );
    }

    // =============== JOJODealer Operations ================
    // deposit withdraw USDC

    function depositUSDCToPerp(uint256 primaryAmount) public onlyOwner {
        IDealer(JOJODealer).deposit(primaryAmount, 0, address(this));
    }

    function fastWithdrawUSDCFromPerp(uint256 primaryAmount) public onlyOwner {
        IDealer(JOJODealer).fastWithdraw(address(this), address(this), primaryAmount, 0, false, "");
    }

    // ========================= LP Functions =======================

    function deposit(uint256 amount) external {
        require(amount != 0, "deposit amount is zero");
        IERC20(USDC).transferFrom(msg.sender, address(this), amount);
        uint256 feeAmount = amount.decimalMul(depositFeeRate);
        if (feeAmount > 0) {
            amount -= feeAmount;
            IERC20(USDC).transfer(owner(), feeAmount);
        }
        // deposit to JOJODealer
        transferOutJUSD(msg.sender, amount);
        uint256 earnUSDCAmount = amount.decimalDiv(getIndex());
        EarnUSDCBalance[msg.sender] += earnUSDCAmount;
        JUSDOutside[msg.sender] += amount;
        totalEarnUSDCBalance += earnUSDCAmount;
        require(getNetValue() <= maxNetValue, "net value exceed limitation");
        emit DepositToHedging(msg.sender, amount, feeAmount, earnUSDCAmount);
    }

    // withdraw all remaining balances
    function requestWithdraw(
        uint256 repayJUSDAmount
    ) external returns (uint256 withdrawEarnUSDCAmount) {
        transferInJUSD(msg.sender, repayJUSDAmount);
        require(repayJUSDAmount <= JUSDOutside[msg.sender], "Request Withdraw too big");
        JUSDOutside[msg.sender] -= repayJUSDAmount;
        uint256 index = getIndex();
        uint256 lockedEarnUSDCAmount = JUSDOutside[msg.sender].decimalDiv(index);
        withdrawEarnUSDCAmount = EarnUSDCBalance[msg.sender]-lockedEarnUSDCAmount;
        WithdrawalRequests.push(
            WithdrawalRequest(withdrawEarnUSDCAmount, msg.sender, false)
        );
        require(withdrawEarnUSDCAmount.decimalMul(index) >= withdrawSettleFee, "Withdraw amount is smaller than settleFee");
        EarnUSDCBalance[msg.sender] = lockedEarnUSDCAmount;
        uint256 withdrawIndex = WithdrawalRequests.length - 1;
        emit RequestWithdrawFromHedging(msg.sender, repayJUSDAmount, withdrawEarnUSDCAmount, withdrawIndex);
        return withdrawIndex;
    }

    function permitWithdrawRequests(
        uint256[] memory requestIDList
    ) external onlyOwner {
        uint256 index = getIndex();
        for (uint256 i; i < requestIDList.length; i++) {
            WithdrawalRequest storage request = WithdrawalRequests[requestIDList[i]];
            require(!request.executed);
            uint256 USDCAmount = request.amount.decimalMul(index);
            uint256 feeAmount = (USDCAmount - withdrawSettleFee).decimalMul(withdrawFeeRate) + withdrawSettleFee;
            if (feeAmount > 0) {
                IERC20(USDC).transfer(owner(), feeAmount);
            }
            IERC20(USDC).transfer(request.user, USDCAmount - feeAmount);
            request.executed = true;
            totalEarnUSDCBalance -= request.amount;
            emit PermitWithdraw(request.user, USDCAmount, feeAmount, request.amount);
        }
    }

    function transferInJUSD(address from, uint256 amount) internal {
        IERC20(JUSD).safeTransferFrom(from, address(this), amount);
    }

    function transferOutJUSD(address to, uint256 amount) internal {
        IDealer(JOJODealer).deposit(0, amount, to);
    }


    function burnJUSD(uint256 amount) public onlyOwner {
        IERC20(JUSD).safeTransfer(msg.sender, amount);
    }

}
