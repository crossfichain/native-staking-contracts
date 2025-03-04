// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
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
     * @dev Receive function to handle native XFI transfers
     * Automatically wraps received XFI as WXFI
     */
    receive() external payable {
        _mint(msg.sender, msg.value);
        emit Transfer(address(0), msg.sender, msg.value);
    }
} 