// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { ERC20 } from "solady/tokens/ERC20.sol";

contract USDB is ERC20 { 
    bool constant public IS_SCRIPT = true;
    
    function name() public pure override returns (string memory) {
        return "USDB";
    }

    function symbol() public pure override returns (string memory) {
        return "USDB Token";
    }

    uint256 public price;

    mapping (address => uint256) public balance;

    function addPrice(uint256 addition) public {
        price += addition;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}