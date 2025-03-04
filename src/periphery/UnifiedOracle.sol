// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "../interfaces/IUnifiedOracle.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IDIAOracle.sol";

/**
 * @title UnifiedOracle
 * @dev Oracle contract that combines DIA Oracle price data with Native Staking specific information
 * Implements both IUnifiedOracle and IOracle interfaces
 * Acts as a bridge between the Cosmos chain and the EVM chain
 */
contract UnifiedOracle is 
    Initializable, 
    AccessControlUpgradeable, 
    PausableUpgradeable, 
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    IUnifiedOracle,
    IOracle 
{
    // Constants
    uint256 private constant PRICE_PRECISION = 1e18;
    uint128 private constant DIA_PRECISION = 1e8;
    uint256 private constant PRICE_FRESHNESS_THRESHOLD = 1 hours;
    
    // Custom roles for access control
    bytes32 public constant ORACLE_UPDATER_ROLE = keccak256("ORACLE_UPDATER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    
    // External oracle references
    IDIAOracle public diaOracle;
    address public fallbackOracle;
    
    // Price data from DIA
    mapping(string => uint256) private _prices;
    uint256 private _lastPriceUpdateTimestamp;
    
    // Native Staking specific information
    uint256 private _totalStakedXFI;
    uint256 private _currentAPR;
    uint256 private _currentAPY;
    uint256 private _unbondingPeriod;
    
    // Events
    event PriceUpdated(string indexed symbol, uint256 price);
    event DiaOracleUpdated(address indexed newOracle);
    event FallbackOracleUpdated(address indexed newOracle);
    event TotalStakedXFIUpdated(uint256 amount);
    event CurrentAPRUpdated(uint256 apr);
    event CurrentAPYUpdated(uint256 apy);
    event UnbondingPeriodUpdated(uint256 period);
    
    /**
     * @dev Initializes the contract
     * @param _diaOracle The address of the DIA Oracle contract
     */
    function initialize(address _diaOracle) public initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ORACLE_UPDATER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        
        // Set DIA Oracle
        diaOracle = IDIAOracle(_diaOracle);
        
        // Default unbonding period (21 days in seconds)
        _unbondingPeriod = 21 days;
        
        // Default APR and APY
        _currentAPR = 10 * PRICE_PRECISION / 100; // 10%
        _currentAPY = 8 * PRICE_PRECISION / 100;  // 8%
    }
    
    /**
     * @dev Gets the current XFI price from the DIA Oracle
     * @return price The price of XFI in USD with 18 decimals
     * @return timestamp The timestamp when the price was updated
     */
    function getXFIPrice() public view returns (uint256 price, uint256 timestamp) {
        (uint128 diaPrice, uint128 diaTimestamp) = diaOracle.getValue("XFI/USD");
        
        // Convert from DIA 8 decimals to our 18 decimals
        price = uint256(diaPrice) * PRICE_PRECISION / DIA_PRECISION;
        timestamp = diaTimestamp;
        
        // If price is zero or too old, use fallback price
        if (price == 0 || block.timestamp - timestamp > PRICE_FRESHNESS_THRESHOLD) {
            price = _prices["XFI"];
            timestamp = _lastPriceUpdateTimestamp;
        }
        
        return (price, timestamp);
    }
    
    /**
     * @dev Gets the current rewards data
     * @return apr The current APR with 18 decimals
     * @return apy The current APY with 18 decimals
     */
    function getCurrentRewards() external view returns (uint256 apr, uint256 apy) {
        return (_currentAPR, _currentAPY);
    }
    
    /**
     * @dev Sets the DIA Oracle address
     * @param oracle The address of the DIA Oracle contract
     */
    function setDIAOracle(address oracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(oracle != address(0), "Invalid oracle address");
        diaOracle = IDIAOracle(oracle);
        emit DiaOracleUpdated(oracle);
    }
    
    /**
     * @dev Sets the fallback oracle address
     * @param oracle The address of the fallback oracle
     */
    function setFallbackOracle(address oracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
        fallbackOracle = oracle;
        emit FallbackOracleUpdated(oracle);
    }
    
    /**
     * @dev Checks if the oracle data is fresh
     * @return True if the data is fresh, false otherwise
     */
    function isOracleFresh() external view returns (bool) {
        (,uint256 timestamp) = getXFIPrice();
        return block.timestamp - timestamp <= PRICE_FRESHNESS_THRESHOLD;
    }
    
    /**
     * @dev Manually updates the price of a token
     * @param symbol The symbol to update the price for
     * @param price The price with 18 decimals of precision
     */
    function setPrice(string calldata symbol, uint256 price) 
        external 
        onlyRole(ORACLE_UPDATER_ROLE) 
        whenNotPaused 
    {
        _prices[symbol] = price;
        _lastPriceUpdateTimestamp = block.timestamp;
        emit PriceUpdated(symbol, price);
    }
    
    /**
     * @dev Updates the total amount of XFI staked
     * @param amount The total amount of XFI staked
     */
    function setTotalStakedXFI(uint256 amount) 
        external 
        onlyRole(ORACLE_UPDATER_ROLE) 
        whenNotPaused 
    {
        _totalStakedXFI = amount;
        emit TotalStakedXFIUpdated(amount);
    }
    
    /**
     * @dev Updates the current APR
     * @param apr The current APR as a percentage (e.g., 12 for 12%)
     */
    function setCurrentAPR(uint256 apr) 
        external 
        onlyRole(ORACLE_UPDATER_ROLE) 
        whenNotPaused 
    {
        _currentAPR = apr * PRICE_PRECISION / 100; // Convert from percentage to 18 decimal precision
        emit CurrentAPRUpdated(_currentAPR);
    }
    
    /**
     * @dev Updates the current APY for the compound staking model
     * @param apy The current APY as a percentage (e.g., 12 for 12%)
     */
    function setCurrentAPY(uint256 apy) 
        external 
        onlyRole(ORACLE_UPDATER_ROLE) 
        whenNotPaused 
    {
        _currentAPY = apy * PRICE_PRECISION / 100; // Convert from percentage to 18 decimal precision
        emit CurrentAPYUpdated(_currentAPY);
    }
    
    /**
     * @dev Updates the unbonding period
     * @param period The unbonding period in seconds
     */
    function setUnbondingPeriod(uint256 period) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        _unbondingPeriod = period;
        emit UnbondingPeriodUpdated(period);
    }
    
    /**
     * @dev Returns the current price of the given symbol
     * @param symbol The symbol to get the price for
     * @return The price with 18 decimals of precision
     */
    function getPrice(string calldata symbol) 
        external 
        view 
        override(IOracle, IUnifiedOracle)
        returns (uint256) 
    {
        if (keccak256(bytes(symbol)) == keccak256(bytes("XFI"))) {
            (uint256 price,) = getXFIPrice();
            return price;
        }
        return _prices[symbol];
    }
    
    /**
     * @dev Returns the total amount of XFI staked via the protocol
     * @return The total amount of XFI staked
     */
    function getTotalStakedXFI() 
        external 
        view 
        override(IOracle, IUnifiedOracle)
        returns (uint256) 
    {
        return _totalStakedXFI;
    }
    
    /**
     * @dev Returns the current APY for the compound staking model
     * @return The current APY as a percentage with 18 decimals
     */
    function getCurrentAPY() 
        external 
        view 
        override(IOracle, IUnifiedOracle)
        returns (uint256) 
    {
        return _currentAPY;
    }
    
    /**
     * @dev Returns the current APR for the APR staking model
     * @return The current APR as a percentage with 18 decimals
     */
    function getCurrentAPR() 
        external 
        view 
        override(IOracle, IUnifiedOracle)
        returns (uint256) 
    {
        return _currentAPR;
    }
    
    /**
     * @dev Returns the default APR for validators
     * @return The default APR with 18 decimals
     */
    function getValidatorAPR() 
        external 
        view 
        returns (uint256) 
    {
        return _currentAPR;
    }
    
    /**
     * @dev Legacy function to check if a validator is active
     * Always returns true as validation is now handled off-chain
     */
    function isValidatorActive(string calldata) 
        external 
        pure 
        override 
        returns (bool) 
    {
        // Always return true as validation is now handled off-chain
        return true;
    }
    
    /**
     * @dev Legacy function to get a validator's APR
     * Now just returns the default APR
     */
    function getValidatorAPR(string calldata)
        external 
        view 
        override
        returns (uint256) 
    {
        // Return the default APR as validator specifics are now handled off-chain
        return _currentAPR;
    }
    
    /**
     * @dev Returns the current unbonding period in seconds
     * @return The unbonding period in seconds
     */
    function getUnbondingPeriod() 
        external 
        view 
        override(IOracle, IUnifiedOracle)
        returns (uint256) 
    {
        return _unbondingPeriod;
    }
    
    /**
     * @dev Pauses the contract
     * Only callable by accounts with the PAUSER_ROLE
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }
    
    /**
     * @dev Unpauses the contract
     * Only callable by accounts with the PAUSER_ROLE
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
    
    /**
     * @dev Function that authorizes an upgrade
     * Only callable by accounts with the UPGRADER_ROLE
     */
    function _authorizeUpgrade(address newImplementation) 
        internal 
        override 
        onlyRole(UPGRADER_ROLE) 
    {
        // No additional logic needed
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     */
    uint256[50] private __gap;
} 