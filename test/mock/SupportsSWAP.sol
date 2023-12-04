/*
    Copyright 2022 JOJO Exchange
    SPDX-License-Identifier: BUSL-1.1
    ONLY FOR TEST
    DO NOT DEPLOY IN PRODUCTION ENV
*/
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IPriceChainLink2 {
    //    get token address price
    function getAssetPrice() external view returns (uint256);
}

contract SupportsSWAP {

    using SafeERC20 for IERC20;
    address USDC;
    address wstETH;
    mapping(address => address) tokenPrice;

    constructor(address _USDC, address _ETH, address _price) {
        USDC = _USDC;
        wstETH = _ETH;
        tokenPrice[_ETH] = _price;
    }

    function addTokenPrice(address token, address price) public {
        tokenPrice[token] = price;
    }

    function swapBuyWsteth(uint256 amount, address token) external {
        IERC20(USDC).safeTransferFrom(msg.sender, address(this), amount);
        uint256 value = amount * 1e18 /
            IPriceChainLink2(tokenPrice[token]).getAssetPrice();
        IERC20(wstETH).safeTransfer(msg.sender, value);
    }


    function swapBuyUSDC(uint256 amount, address token) external {
        IERC20(wstETH).safeTransferFrom(msg.sender, address(this), amount);
        uint256 value = amount * IPriceChainLink2(tokenPrice[token]).getAssetPrice() / 1e18;
        IERC20(USDC).safeTransfer(msg.sender, value);
    }

    function getSwapBuyWstethData(
        uint256 amount,
        address token
    ) external pure returns (bytes memory) {
        return abi.encodeWithSignature("swapBuyWsteth(uint256,address)", amount, token);
    }

    function getSwapBuyUSDChData(
        uint256 amount,
        address token
    ) external pure returns (bytes memory) {
        return abi.encodeWithSignature("swapBuyUSDC(uint256,address)", amount, token);
    }
}
