// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IWXFI
 * @dev Interface for the Wrapped XFI token (WXFI) which extends ERC20 with deposit/withdraw functionality
 * Similar to WETH, this allows native XFI to be wrapped as an ERC20 token
 */
interface IWXFI is IERC20 {
    /**
     * @dev Deposits native XFI and mints WXFI tokens
     * Must be payable as it accepts native XFI
     */
    function deposit() external payable;
    
    /**
     * @dev Withdraws native XFI by burning WXFI tokens
     * @param amount The amount of WXFI to burn and XFI to withdraw
     */
    function withdraw(uint256 amount) external;
} 