// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title NativeStakingManagerLib
 * @dev Library for NativeStakingManager with utility functions and enums
 * to reduce contract size
 */
library NativeStakingManagerLib {
    // Define the staking mode enum here
    enum StakingMode { APR, APY }
    
    /**
     * @dev Calculates the APR reward for a staking amount over a period
     * @param amount The staked amount
     * @param apr The annual percentage rate (18 decimals)
     * @param timeInSeconds Time in seconds
     * @return The reward amount
     */
    function calculateAPRReward(
        uint256 amount,
        uint256 apr,
        uint256 timeInSeconds
    ) public pure returns (uint256) {
        uint256 secondsInYear = 365 days;
        
        // Calculate: amount * apr * (timeInSeconds / secondsInYear)
        return (amount * apr * timeInSeconds) / (secondsInYear * 1e18);
    }
    
    /**
     * @dev Validates if the amount meets the minimum requirement
     * @param amount The amount to check
     * @param minAmount The minimum required amount
     * @param enforceMinimums Whether minimums are enforced
     * @return Whether the amount is valid
     */
    function isValidAmount(
        uint256 amount,
        uint256 minAmount,
        bool enforceMinimums
    ) public pure returns (bool) {
        return !enforceMinimums || amount >= minAmount;
    }
    
    /**
     * @dev Validates the staking parameters
     * @param amount The amount to stake
     * @param minAmount The minimum amount required
     * @param enforceMinimums Whether to enforce minimum amounts
     * @return isValid Whether the parameters are valid
     * @return errorMessage The error message if not valid
     */
    function validateStakingParams(
        uint256 amount,
        uint256 minAmount,
        bool enforceMinimums
    ) internal pure returns (bool isValid, string memory errorMessage) {
        // Check for zero amount
        if (amount == 0) {
            return (false, "Amount must be greater than 0");
        }
        
        // Check for minimum amount if enforced
        if (enforceMinimums && amount < minAmount) {
            return (false, "Amount below minimum");
        }
        
        return (true, "");
    }
    
    /**
     * @dev Calculates the gas cost of a transaction
     * @param startGas The starting gas amount
     * @return The gas used
     */
    function calculateGasCost(uint256 startGas) internal view returns (uint256) {
        return startGas - gasleft();
    }
} 