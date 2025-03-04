// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../interfaces/IOracle.sol";

/**
 * @title CrossFiOracle
 * @dev Oracle contract that provides price data and validator information
 * Serves as a bridge between the Cosmos chain and the EVM chain
 * Implements the IOracle interface
 */
contract CrossFiOracle is 
    Initializable, 
    AccessControlUpgradeable, 
    PausableUpgradeable, 
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    IOracle 
{
    // Constants
    uint256 private constant PRICE_PRECISION = 1e18;
    
    // Custom roles for access control
    bytes32 public constant ORACLE_UPDATER_ROLE = keccak256("ORACLE_UPDATER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    
    // State variables
    mapping(string => uint256) private _prices;
    mapping(string => bool) private _activeValidators;
    mapping(string => uint256) private _validatorAPRs;
    uint256 private _totalStakedXFI;
    uint256 private _currentAPY;
    uint256 private _unbondingPeriod;
    
    // Events
    event PriceUpdated(string indexed symbol, uint256 price);
    event ValidatorStatusUpdated(string indexed validator, bool isActive);
    event ValidatorAPRUpdated(string indexed validator, uint256 apr);
    event TotalStakedXFIUpdated(uint256 amount);
    event CurrentAPYUpdated(uint256 apy);
    event UnbondingPeriodUpdated(uint256 period);
    
    /**
     * @dev Initializes the contract
     * Sets up roles and default values
     */
    function initialize() public initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ORACLE_UPDATER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        
        // Default unbonding period (21 days in seconds)
        _unbondingPeriod = 21 days;
    }
    
    /**
     * @dev Updates the price of a token
     * @param symbol The token symbol (e.g., "XFI", "MPX")
     * @param price The price with 18 decimals of precision
     */
    function setPrice(string calldata symbol, uint256 price) 
        external 
        onlyRole(ORACLE_UPDATER_ROLE) 
        whenNotPaused 
    {
        _prices[symbol] = price;
        emit PriceUpdated(symbol, price);
    }
    
    /**
     * @dev Updates the active status of a validator
     * @param validator The validator address/ID
     * @param isActive Whether the validator is active
     */
    function setValidatorStatus(string calldata validator, bool isActive) 
        external 
        onlyRole(ORACLE_UPDATER_ROLE) 
        whenNotPaused 
    {
        _activeValidators[validator] = isActive;
        emit ValidatorStatusUpdated(validator, isActive);
    }
    
    /**
     * @dev Updates multiple validators status at once
     * @param validators Array of validator addresses/IDs
     * @param statuses Array of active statuses
     */
    function bulkSetValidatorStatus(string[] calldata validators, bool[] calldata statuses) 
        external 
        onlyRole(ORACLE_UPDATER_ROLE) 
        whenNotPaused 
    {
        require(validators.length == statuses.length, "Length mismatch");
        
        for (uint256 i = 0; i < validators.length; i++) {
            _activeValidators[validators[i]] = statuses[i];
            emit ValidatorStatusUpdated(validators[i], statuses[i]);
        }
    }
    
    /**
     * @dev Updates the APR for a validator
     * @param validator The validator address/ID
     * @param apr The APR with 18 decimals of precision
     */
    function setValidatorAPR(string calldata validator, uint256 apr) 
        external 
        onlyRole(ORACLE_UPDATER_ROLE) 
        whenNotPaused 
    {
        _validatorAPRs[validator] = apr;
        emit ValidatorAPRUpdated(validator, apr);
    }
    
    /**
     * @dev Updates multiple validators APR at once
     * @param validators Array of validator addresses/IDs
     * @param aprs Array of APRs
     */
    function bulkSetValidatorAPR(string[] calldata validators, uint256[] calldata aprs) 
        external 
        onlyRole(ORACLE_UPDATER_ROLE) 
        whenNotPaused 
    {
        require(validators.length == aprs.length, "Length mismatch");
        
        for (uint256 i = 0; i < validators.length; i++) {
            _validatorAPRs[validators[i]] = aprs[i];
            emit ValidatorAPRUpdated(validators[i], aprs[i]);
        }
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
     * @dev Updates the current APY for the compound staking model
     * @param apy The current APY with 18 decimals of precision
     */
    function setCurrentAPY(uint256 apy) 
        external 
        onlyRole(ORACLE_UPDATER_ROLE) 
        whenNotPaused 
    {
        _currentAPY = apy;
        emit CurrentAPYUpdated(apy);
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
        override 
        returns (uint256) 
    {
        return _prices[symbol];
    }
    
    /**
     * @dev Checks if a validator is active and valid for staking
     * @param validator The validator address/ID to check
     * @return True if the validator is active
     */
    function isValidatorActive(string calldata validator) 
        external 
        view 
        override 
        returns (bool) 
    {
        return _activeValidators[validator];
    }
    
    /**
     * @dev Returns the total amount of XFI staked via the protocol
     * @return The total amount of XFI staked
     */
    function getTotalStakedXFI() 
        external 
        view 
        override 
        returns (uint256) 
    {
        return _totalStakedXFI;
    }
    
    /**
     * @dev Returns the current APR for staking with a specific validator
     * @param validator The validator address/ID
     * @return The current APR as a percentage with 18 decimals
     */
    function getValidatorAPR(string calldata validator) 
        external 
        view 
        override 
        returns (uint256) 
    {
        return _validatorAPRs[validator];
    }
    
    /**
     * @dev Returns the current APY for the compound staking model
     * @return The current APY as a percentage with 18 decimals
     */
    function getCurrentAPY() 
        external 
        view 
        override 
        returns (uint256) 
    {
        return _currentAPY;
    }
    
    /**
     * @dev Returns the current unbonding period in seconds
     * @return The unbonding period in seconds
     */
    function getUnbondingPeriod() 
        external 
        view 
        override 
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
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
} 