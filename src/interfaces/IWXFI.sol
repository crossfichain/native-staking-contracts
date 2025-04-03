// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IWXFI {
    function balanceOf(address) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function deposit() external payable;
    function withdraw(uint256) external;
} 