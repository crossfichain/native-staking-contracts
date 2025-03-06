// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "../interfaces/IOracle.sol";

/**
 * @title CrossFiOracle
 * @dev Oracle contract that provides price data and staking information
 * Serves as a bridge between the Cosmos chain and the EVM chain
 * Validator information is now just informational as validation occurs off-chain
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
    uint256 private constant MPX_PRICE_USD = 4 * 1e16; // $0.04 in 18 decimals (4 * 10^16)
    
    // Custom roles for access control
    bytes32 public constant ORACLE_UPDATER_ROLE = keccak256("ORACLE_UPDATER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    
    // State variables
    mapping(string => uint256) private _prices;
    mapping(string => bool) private _activeValidators;
    mapping(string => uint256) private _validatorAPRs;
    mapping(address => uint256) private _userClaimableRewards; // Added: Claimable rewards per user
    uint256 private _totalStakedXFI;
    uint256 private _currentAPY;
    uint256 private _currentAPR;
    uint256 private _unbondingPeriod;
    uint256 private _launchTimestamp; // Added: Timestamp of product launch for unstaking freeze
    
    // Events
    event PriceUpdated(string indexed symbol, uint256 price);
    event ValidatorStatusUpdated(string indexed validator, bool isActive);
    event ValidatorAPRUpdated(string indexed validator, uint256 apr);
    event TotalStakedXFIUpdated(uint256 amount);
    event CurrentAPYUpdated(uint256 apy);
    event CurrentAPRUpdated(uint256 apr);
    event UnbondingPeriodUpdated(uint256 period);
    event UserRewardsUpdated(address indexed user, uint256 amount); // Added: Event for user rewards
    event LaunchTimestampSet(uint256 timestamp); // Added: Event for launch timestamp
    
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
        
        // Default APR and APY values
        _currentAPY = 8 * PRICE_PRECISION / 100;  // 8%
        _currentAPR = 10 * PRICE_PRECISION / 100; // 10%
        
        // Set launch timestamp to current time
        _launchTimestamp = block.timestamp;
    }
    
    /**
     * @dev Updates the price of a token
     * @param price The price with 18 decimals of precision
     */
    function setPrice(uint256 price) 
        external 
        onlyRole(ORACLE_UPDATER_ROLE) 
        whenNotPaused 
    {
        _prices["XFI"] = price;
        emit PriceUpdated("XFI", price);
    }
    
    /**
     * @dev Updates the active status of a validator (informational only)
     * This is now only for informational purposes as validation occurs off-chain
     * @param validator The validator address/ID
     * @param isActive Whether the validator is active
     * @param apr The APR with 18 decimals of precision
     */
    function setValidator(string calldata validator, bool isActive, uint256 apr) 
        external 
        onlyRole(ORACLE_UPDATER_ROLE) 
        whenNotPaused 
    {
        _activeValidators[validator] = isActive;
        _validatorAPRs[validator] = apr * PRICE_PRECISION / 100; // Convert from percentage to 18 decimal precision
        emit ValidatorStatusUpdated(validator, isActive);
        emit ValidatorAPRUpdated(validator, _validatorAPRs[validator]);
    }
    
    /**
     * @dev Updates multiple validators status at once (informational only)
     * This is now only for informational purposes as validation occurs off-chain
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
     * @dev Updates the APR for a validator (informational only)
     * This is now only for informational purposes as validation occurs off-chain
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
     * @dev Updates the current APR for the APR staking model
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
     * @dev Checks if a validator is active (informational only)
     * This is now only for informational purposes as validation occurs off-chain
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
     * @dev Returns the current APR for staking with a specific validator (informational only)
     * This is now only for informational purposes as validation occurs off-chain
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
     * @dev Returns the current APR for the compound staking model
     * @return The current APR as a percentage with 18 decimals
     */
    function getCurrentAPR() 
        external 
        view 
        override 
        returns (uint256) 
    {
        return _currentAPR;
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
     * @dev Sets the launch timestamp for the unstaking freeze period
     * @param timestamp The launch timestamp
     */
    function setLaunchTimestamp(uint256 timestamp) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        _launchTimestamp = timestamp;
        emit LaunchTimestampSet(timestamp);
    }
    
    /**
     * @dev Sets claimable rewards for a specific user
     * @param user The user address
     * @param amount The claimable reward amount
     */
    function setUserClaimableRewards(address user, uint256 amount) 
        external 
        onlyRole(ORACLE_UPDATER_ROLE) 
        whenNotPaused 
    {
        _userClaimableRewards[user] = amount;
        emit UserRewardsUpdated(user, amount);
    }
    
    /**
     * @dev Sets claimable rewards for multiple users in a batch
     * @param users Array of user addresses
     * @param amounts Array of reward amounts
     */
    function batchSetUserClaimableRewards(address[] calldata users, uint256[] calldata amounts) 
        external 
        onlyRole(ORACLE_UPDATER_ROLE) 
        whenNotPaused 
    {
        require(users.length == amounts.length, "Length mismatch");
        
        for (uint256 i = 0; i < users.length; i++) {
            _userClaimableRewards[users[i]] = amounts[i];
            emit UserRewardsUpdated(users[i], amounts[i]);
        }
    }
    
    /**
     * @dev Gets claimable rewards for a specific user
     * @param user The user address
     * @return amount The claimable reward amount
     */
    function getUserClaimableRewards(address user) 
        external 
        view 
        returns (uint256) 
    {
        return _userClaimableRewards[user];
    }
    
    /**
     * @dev Checks if unstaking is frozen (first month after launch)
     * @return True if unstaking is still frozen
     */
    function isUnstakingFrozen() 
        external 
        view 
        returns (bool) 
    {
        return (block.timestamp < _launchTimestamp + 30 days);
    }
    
    /**
     * @dev Returns the fixed price of MPX in USD
     * @return The MPX price with 18 decimals of precision
     */
    function getMPXPrice() 
        external 
        pure 
        returns (uint256) 
    {
        return MPX_PRICE_USD;
    }
    
    /**
     * @dev Converts XFI amount to MPX amount based on current prices
     * @param xfiAmount The amount of XFI to convert
     * @return mpxAmount The equivalent amount of MPX
     */
    function convertXFItoMPX(uint256 xfiAmount) 
        external 
        view 
        returns (uint256 mpxAmount) 
    {
        // MPX amount = (XFI amount ? XFI price in USD) ? MPX price ($0.04)
        uint256 xfiPriceUSD = _prices["XFI"];
        require(xfiPriceUSD > 0, "XFI price not available");
        
        mpxAmount = (xfiAmount * xfiPriceUSD) / MPX_PRICE_USD;
        return mpxAmount;
    }
    
    /**
     * @dev Clears claimable rewards for a user after they have been claimed
     * @param user The user address
     * @return amount The amount that was cleared
     */
    function clearUserClaimableRewards(address user) 
        external 
        onlyRole(ORACLE_UPDATER_ROLE) 
        whenNotPaused 
        returns (uint256 amount) 
    {
        amount = _userClaimableRewards[user];
        _userClaimableRewards[user] = 0;
        emit UserRewardsUpdated(user, 0);
        return amount;
    }
    
    /**
     * @dev Decreases claimable rewards for a user by a specific amount
     * @param user The user address
     * @param amount The amount to decrease by
     * @return newAmount The new reward amount after decrease
     */
    function decreaseUserClaimableRewards(address user, uint256 amount) 
        external 
        onlyRole(ORACLE_UPDATER_ROLE) 
        whenNotPaused 
        returns (uint256 newAmount) 
    {
        require(_userClaimableRewards[user] >= amount, "Insufficient rewards");
        
        _userClaimableRewards[user] -= amount;
        newAmount = _userClaimableRewards[user];
        
        emit UserRewardsUpdated(user, newAmount);
        return newAmount;
    }
    
    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
} 