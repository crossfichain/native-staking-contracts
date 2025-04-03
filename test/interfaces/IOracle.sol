// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IOracle {
    function getCurrentAPY() external view returns (uint256);
    function getUnbondingPeriod() external view returns (uint256);
} 