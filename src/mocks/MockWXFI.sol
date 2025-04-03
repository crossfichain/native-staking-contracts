// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IWXFI.sol";

/**
 * @title MockWXFI
 * @dev Mock Wrapped XFI token for testing
 */
contract MockWXFI is ERC20, Ownable, IWXFI {
    uint8 private _decimals;
    
    /**
     * @dev Constructor
     * @param name Token name
     * @param symbol Token symbol
     * @param decimals_ Token decimals
     */
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) ERC20(name, symbol) Ownable() {
        _decimals = decimals_;
    }
    
    /**
     * @dev Returns the number of decimals used for token
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
    
    /**
     * @dev Mints tokens to an address
     * @param account Address to mint to
     * @param amount Amount to mint
     */
    function mint(address account, uint256 amount) external onlyOwner {
        _mint(account, amount);
    }
    
    /**
     * @dev Burns tokens from an address
     * @param account Address to burn from
     * @param amount Amount to burn
     */
    function burn(address account, uint256 amount) external onlyOwner {
        _burn(account, amount);
    }
    
    /**
     * @dev Deposits native XFI and mints WXFI tokens (mock implementation)
     */
    function deposit() external payable override {
        _mint(msg.sender, msg.value);
    }
    
    /**
     * @dev Withdraws native XFI by burning WXFI tokens (mock implementation)
     * @param amount The amount of WXFI to burn and XFI to withdraw
     */
    function withdraw(uint256 amount) external override {
        _burn(msg.sender, amount);
    }
    
    /**
     * @dev Override standard ERC20 functions to also implement IWXFI interface
     */
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
    
    /**
     * @dev Receive function to handle native XFI transfers
     * Automatically wraps received XFI as WXFI
     */
    receive() external payable {
        _mint(msg.sender, msg.value);
    }

    function allowance(address owner, address spender) public view override(ERC20, IWXFI) returns (uint256) {
        return super.allowance(owner, spender);
    }
} 