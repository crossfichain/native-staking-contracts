// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./MockERC20.sol";

/**
 * @title MockWXFI
 * @dev Mock implementation of Wrapped XFI (WXFI) with deposit and withdraw functions
 */
contract MockWXFI is MockERC20 {
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    constructor() MockERC20("Wrapped XFI", "WXFI", 18) {}

    // Function to deposit native token and get wrapped tokens
    function deposit() public payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }
    
    // Function to burn wrapped tokens and get native token
    function withdraw(uint256 wad) public {
        require(balanceOf(msg.sender) >= wad, "WXFI: insufficient balance");
        
        // Check if the contract has enough ETH balance
        require(address(this).balance >= wad, "WXFI: insufficient ETH in contract");
        
        // First burn the tokens
        _burn(msg.sender, wad);
        
        // Then send the ETH without the restrictive gas limit for tests
        // Using a low-level call without gas limit for test environments
        (bool success, ) = msg.sender.call{value: wad}("");
        
        // If the transfer fails, we mint the tokens back to prevent loss of funds
        if (!success) {
            _mint(msg.sender, wad);
            revert("WXFI: ETH transfer failed");
        }
        
        emit Withdrawal(msg.sender, wad);
    }
    
    // Alternative withdraw function that just burns tokens without transferring ETH
    // This is useful for testing scenarios where we don't need actual ETH transfers
    function mockWithdraw(uint256 wad) public {
        require(balanceOf(msg.sender) >= wad, "WXFI: insufficient balance");
        _burn(msg.sender, wad);
        emit Withdrawal(msg.sender, wad);
    }
    
    // Function to receive ETH
    receive() external payable {
        deposit();
    }
} 