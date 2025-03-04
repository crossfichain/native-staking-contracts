// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IUnifiedOracle
 * @dev Interface for the unified oracle system that combines DIA Oracle price data
 * with Native Staking specific information
 */
interface IUnifiedOracle {
    /**
     * @dev Returns the current price of XFI
     * @return price The price of XFI in USD with 18 decimals
     * @return timestamp The timestamp when the price was updated
     */
    function getXFIPrice() external view returns (uint256 price, uint256 timestamp);
    
    /**
     * @dev Returns the current rewards data
     * @return apr The current APR with 18 decimals
     * @return apy The current APY with 18 decimals
     */
    function getCurrentRewards() external view returns (uint256 apr, uint256 apy);
    
    /**
     * @dev Returns the total amount of XFI staked via the protocol
     * @return The total amount of XFI staked with 18 decimals
     */
    function getTotalStakedXFI() external view returns (uint256);
    
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
     * @dev Returns the current APR for validator information
     * This is now only for informational purposes
     * @return The default APR for validators with 18 decimals
     */
    function getValidatorAPR() external view returns (uint256);
    
    /**
     * @dev Returns the current unbonding period in seconds
     * @return The unbonding period in seconds
     */
    function getUnbondingPeriod() external view returns (uint256);
    
    /**
     * @dev Sets the DIA Oracle address
     * @param oracle The address of the DIA Oracle contract
     */
    function setDIAOracle(address oracle) external;
    
    /**
     * @dev Sets the fallback oracle address
     * @param oracle The address of the fallback oracle contract
     */
    function setFallbackOracle(address oracle) external;
    
    /**
     * @dev Checks if the oracle data is fresh
     * @return True if the data is fresh, false otherwise
     */
    function isOracleFresh() external view returns (bool);
    
    /**
     * @dev Gets the price of a token by its symbol
     * @param symbol The symbol of the token
     * @return The price with 18 decimals of precision
     */
    function getPrice(string calldata symbol) external view returns (uint256);
} 