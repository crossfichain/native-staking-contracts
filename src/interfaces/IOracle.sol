// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IOracle
 * @dev Interface for the Oracle that provides XFI/MPX price data and staking information
 * Validator-specific functionality is now optional as validation occurs off-chain
 */
interface IOracle {
    /**
     * @dev Returns the current price of the given symbol
     * @param symbol The symbol to get the price for (e.g., "XFI", "MPX")
     * @return The price with 18 decimals of precision
     */
    function getPrice(string calldata symbol) external view returns (uint256);
    
    /**
     * @dev [OPTIONAL] Checks if a validator is active
     * This is now only for informational purposes as validation occurs off-chain
     * @param validator The validator address/ID to check
     * @return True if the validator is active and valid for staking
     */
    function isValidatorActive(string calldata validator) external view returns (bool);
    
    /**
     * @dev Returns the total amount of XFI staked via the protocol (for APY model)
     * @return The total amount of XFI staked with 18 decimals of precision
     */
    function getTotalStakedXFI() external view returns (uint256);
    
    /**
     * @dev [OPTIONAL] Returns the current APR for staking with a specific validator
     * This is now only for informational purposes as validation occurs off-chain
     * @param validator The validator address/ID
     * @return The current APR as a percentage with 18 decimals
     */
    function getValidatorAPR(string calldata validator) external view returns (uint256);
    
    /**
     * @dev Returns the current APY for the compound staking model
     * @return The current APY as a percentage with 18 decimals
     */
    function getCurrentAPY() external view returns (uint256);
    
    /**
     * @dev Returns the current APR for the APR staking model
     * @return The current APR as a percentage with 18 decimals
     */
    function getCurrentAPR() external view returns (uint256);
    
    /**
     * @dev Returns the current unbonding period in seconds
     * @return The unbonding period in seconds
     */
    function getUnbondingPeriod() external view returns (uint256);

    /**
     * @dev Returns the fixed price of MPX in USD
     * @return The MPX price with 18 decimals of precision
     */
    function getMPXPrice() external pure returns (uint256);
    
    /**
     * @dev Converts XFI amount to MPX amount based on current prices
     * @param xfiAmount The amount of XFI to convert
     * @return mpxAmount The equivalent amount of MPX
     */
    function convertXFItoMPX(uint256 xfiAmount) external view returns (uint256 mpxAmount);
    
    /**
     * @dev Gets claimable rewards for a specific user
     * @param user The user address
     * @return amount The claimable reward amount
     */
    function getUserClaimableRewards(address user) external view returns (uint256);

    /**
     * @dev Clears claimable rewards for a user after they have been claimed
     * @param user The user address
     * @return amount The amount that was cleared
     */
    function clearUserClaimableRewards(address user) external returns (uint256 amount);
    
    /**
     * @dev Decreases claimable rewards for a user by a specific amount
     * @param user The user address
     * @param amount The amount to decrease by
     * @return newAmount The new reward amount after decrease
     */
    function decreaseUserClaimableRewards(address user, uint256 amount) external returns (uint256 newAmount);

    /**
     * @dev Gets the claimable rewards for a user from a specific validator
     * @param user The user address
     * @param validator The validator address
     * @return The amount of claimable rewards
     */
    function getUserClaimableRewardsForValidator(address user, string calldata validator) 
        external 
        view 
        returns (uint256);

    /**
     * @dev Clears the claimable rewards for a user from a specific validator
     * @param user The user address
     * @param validator The validator address
     * @return The amount of rewards that were cleared
     */
    function clearUserClaimableRewardsForValidator(address user, string calldata validator) 
        external 
        returns (uint256);

    /**
     * @dev Gets the stake amount for a user with a specific validator
     * @param user The user address
     * @param validator The validator address
     * @return The amount of stake
     */
    function getValidatorStake(address user, string calldata validator) 
        external 
        view 
        returns (uint256);

    /**
     * @dev Gets total claimable rewards for all users
     * @return totalRewards The total of all claimable rewards
     */
    function getTotalClaimableRewards() external view returns (uint256);
} 