// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./MockERC20.sol";
import "../../src/interfaces/IWXFI.sol";

/**
 * @title MockWXFI
 * @dev Mock implementation of Wrapped XFI (WXFI) with deposit and withdraw functions
 */
contract MockWXFI is MockERC20, IWXFI {
    // Events (required by IWXFI interface)
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    constructor() MockERC20("Wrapped XFI", "WXFI", 18) {}

    // Function to deposit native token and get wrapped tokens
    function deposit() external payable override {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }
    
    // Function to burn wrapped tokens and get native token
    function withdraw(uint256 amount) external override {
        require(balanceOf(msg.sender) >= amount, "MockWXFI: insufficient balance");
        _burn(msg.sender, amount);
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "MockWXFI: ETH transfer failed");
        emit Withdrawal(msg.sender, amount);
    }
    
    // Override ERC20 functions to satisfy IWXFI interface
    function balanceOf(address account) public view override(ERC20, IWXFI) returns (uint256) {
        return super.balanceOf(account);
    }
    
    function transfer(address to, uint256 amount) public override(ERC20, IWXFI) returns (bool) {
        return super.transfer(to, amount);
    }
    
    function transferFrom(address from, address to, uint256 amount) public override(ERC20, IWXFI) returns (bool) {
        return super.transferFrom(from, to, amount);
    }
    
    function approve(address spender, uint256 amount) public override(ERC20, IWXFI) returns (bool) {
        return super.approve(spender, amount);
    }
    
    function allowance(address owner, address spender) public view override(ERC20, IWXFI) returns (uint256) {
        return super.allowance(owner, spender);
    }
    
    // Function to receive ETH
    receive() external payable {
        this.deposit();
    }
} 