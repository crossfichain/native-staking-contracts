// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IWXFI.sol";

/**
 * @title WXFI
 * @dev Wrapped XFI token implementation (similar to WETH)
 * Allows native XFI to be wrapped as an ERC20 token
 */
contract WXFI is ERC20, ReentrancyGuard, IWXFI {
    /**
     * @dev Constructor
     * Sets the name and symbol of the token
     */
    constructor() ERC20("Wrapped XFI", "WXFI") {}
    
    /**
     * @dev Deposits native XFI and mints WXFI tokens
     * Must be payable as it accepts native XFI
     */
    function deposit() external payable override nonReentrant {
        _mint(msg.sender, msg.value);
        emit Transfer(address(0), msg.sender, msg.value);
    }
    
    /**
     * @dev Withdraws native XFI by burning WXFI tokens
     * @param amount The amount of WXFI to burn and XFI to withdraw
     */
    function withdraw(uint256 amount) external override nonReentrant {
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
        
        emit Transfer(msg.sender, address(0), amount);
    }
    
    /**
     * @dev Override ERC20.balanceOf to also implement IWXFI.balanceOf
     */
    function balanceOf(address account) public view override(ERC20, IWXFI) returns (uint256) {
        return super.balanceOf(account);
    }
    
    /**
     * @dev Override ERC20.transfer to also implement IWXFI.transfer
     */
    function transfer(address to, uint256 amount) public override(ERC20, IWXFI) returns (bool) {
        return super.transfer(to, amount);
    }
    
    /**
     * @dev Override ERC20.transferFrom to also implement IWXFI.transferFrom
     */
    function transferFrom(address from, address to, uint256 amount) public override(ERC20, IWXFI) returns (bool) {
        return super.transferFrom(from, to, amount);
    }
    
    /**
     * @dev Override ERC20.approve to also implement IWXFI.approve
     */
    function approve(address spender, uint256 amount) public override(ERC20, IWXFI) returns (bool) {
        return super.approve(spender, amount);
    }
    
    /**
     * @dev Receive function to handle native XFI transfers
     * Automatically wraps received XFI as WXFI
     */
    receive() external payable {
        _mint(msg.sender, msg.value);
        emit Transfer(address(0), msg.sender, msg.value);
    }

    /**
     * @dev Override ERC20.allowance to also implement IWXFI.allowance
     */
    function allowance(address owner, address spender) public view override(ERC20, IWXFI) returns (uint256) {
        return super.allowance(owner, spender);
    }
} 