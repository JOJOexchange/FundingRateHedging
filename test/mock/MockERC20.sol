// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {

    constructor(uint256 a) ERC20("mock token", "mock") {
        _mint(msg.sender, a);
    }
}
