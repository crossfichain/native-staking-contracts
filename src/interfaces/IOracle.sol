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
} 