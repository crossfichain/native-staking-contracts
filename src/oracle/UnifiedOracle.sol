// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../interfaces/IUnifiedOracle.sol";
import "../interfaces/IDIAOracle.sol";

contract UnifiedOracle is 
    Initializable, 
    AccessControlUpgradeable, 
    PausableUpgradeable, 
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    IUnifiedOracle 
{
    // Constants
    uint256 private constant PRECISION = 1e18;
    
    // Custom roles
    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");
    
    // State variables
    IDIAOracle public diaOracle;
    uint256 public lastPrice;
    uint256 public lastPriceTimestamp;
    uint256 public currentAPR;
    uint256 public currentAPY;
    uint256 public totalStakedXFI;
    uint256 public unbondingPeriod;
    uint256 public validatorAPR;
    
    // State variables for reward management
    mapping(address => uint256) private _userClaimableRewards;
    
    // Events
    event PriceUpdated(uint256 price, uint256 timestamp);
    event APRUpdated(uint256 apr);
    event APYUpdated(uint256 apy);
    event UnbondingPeriodUpdated(uint256 period);
    event UserRewardsAdded(address indexed user, uint256 amount);
    event UserRewardsCleared(address indexed user);
    event TotalStakedXFIUpdated(uint256 amount);
    event ValidatorAPRUpdated(uint256 apr);
    
    /**
     * @dev Initializes the contract
     * @param _diaOracle The address of the DIA oracle
     * @param _unbondingPeriod The unbonding period in seconds
     */
    function initialize(
        address _diaOracle,
        uint256 _unbondingPeriod
    ) external initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ORACLE_MANAGER_ROLE, msg.sender);
        
        require(_diaOracle != address(0), "Invalid DIA oracle address");
        diaOracle = IDIAOracle(_diaOracle);
        
        unbondingPeriod = _unbondingPeriod;
    }
    
    /**
     * @dev Gets claimable rewards for a user
     * @param user The user address
     * @return The amount of claimable rewards
     */
    function getUserClaimableRewards(address user) 
        external 
        view 
        returns (uint256) 
    {
        return _userClaimableRewards[user];
    }

    /**
     * @dev Adds claimable rewards for a user
     * @param user The user address
     * @param amount The amount of rewards to add
     */
    function addUserClaimableRewards(address user, uint256 amount) 
        external 
        onlyRole(ORACLE_MANAGER_ROLE) 
    {
        require(user != address(0), "Invalid user address");
        require(amount > 0, "Amount must be greater than 0");
        
        _userClaimableRewards[user] += amount;
        emit UserRewardsAdded(user, amount);
    }

    /**
     * @dev Clears claimable rewards for a user
     * @param user The user address
     */
    function clearUserClaimableRewards(address user) 
        external 
        onlyRole(ORACLE_MANAGER_ROLE) 
    {
        require(user != address(0), "Invalid user address");
        
        _userClaimableRewards[user] = 0;
        emit UserRewardsCleared(user);
    }
    
    /**
     * @dev Gets the current price of XFI
     * @return The current price
     */
    function getPrice(string memory) external view returns (uint256) {
        return lastPrice;
    }
    
    /**
     * @dev Gets the current APR
     * @return The current APR
     */
    function getCurrentAPR() external view returns (uint256) {
        return currentAPR;
    }
    
    /**
     * @dev Gets the unbonding period
     * @return The unbonding period in seconds
     */
    function getUnbondingPeriod() external view returns (uint256) {
        return unbondingPeriod;
    }
    
    /**
     * @dev Gets the current XFI price and timestamp
     */
    function getXFIPrice() external view returns (uint256 price, uint256 timestamp) {
        return (lastPrice, lastPriceTimestamp);
    }
    
    /**
     * @dev Gets the current rewards data
     */
    function getCurrentRewards() external view returns (uint256 apr, uint256 apy) {
        return (currentAPR, currentAPY);
    }
    
    /**
     * @dev Gets the total amount of XFI staked
     */
    function getTotalStakedXFI() external view returns (uint256) {
        return totalStakedXFI;
    }
    
    /**
     * @dev Gets the current APY
     */
    function getCurrentAPY() external view returns (uint256) {
        return currentAPY;
    }
    
    /**
     * @dev Gets the validator APR
     */
    function getValidatorAPR() external view returns (uint256) {
        return validatorAPR;
    }
    
    /**
     * @dev Checks if the oracle data is fresh
     */
    function isOracleFresh() external view returns (bool) {
        return (block.timestamp - lastPriceTimestamp) <= 1 hours;
    }
    
    /**
     * @dev Updates the price from DIA oracle
     */
    function updatePrice() external onlyRole(ORACLE_MANAGER_ROLE) {
        (uint128 price, uint128 timestamp) = diaOracle.getValue("XFI/USD");
        require(price > 0, "Invalid price from DIA oracle");
        
        // Convert from 8 decimals to 18 decimals
        lastPrice = uint256(price) * 1e10;
        lastPriceTimestamp = uint256(timestamp);
        emit PriceUpdated(lastPrice, lastPriceTimestamp);
    }
    
    /**
     * @dev Updates the APR
     * @param apr The new APR value
     */
    function updateAPR(uint256 apr) external onlyRole(ORACLE_MANAGER_ROLE) {
        require(apr <= 50 * 1e16, "APR too high"); // Max 50%
        currentAPR = apr;
        emit APRUpdated(apr);
    }
    
    /**
     * @dev Updates the unbonding period
     * @param period The new unbonding period in seconds
     */
    function updateUnbondingPeriod(uint256 period) external onlyRole(ORACLE_MANAGER_ROLE) {
        require(period >= 1 days && period <= 30 days, "Invalid unbonding period");
        unbondingPeriod = period;
        emit UnbondingPeriodUpdated(period);
    }
    
    /**
     * @dev Updates the APY
     * @param apy The new APY value
     */
    function updateAPY(uint256 apy) external onlyRole(ORACLE_MANAGER_ROLE) {
        require(apy <= 50 * 1e16, "APY too high"); // Max 50%
        currentAPY = apy;
        emit APYUpdated(apy);
    }
    
    /**
     * @dev Updates the total staked XFI amount
     * @param amount The new total staked amount
     */
    function updateTotalStakedXFI(uint256 amount) external onlyRole(ORACLE_MANAGER_ROLE) {
        totalStakedXFI = amount;
        emit TotalStakedXFIUpdated(amount);
    }
    
    /**
     * @dev Updates the validator APR
     * @param apr The new validator APR value
     */
    function updateValidatorAPR(uint256 apr) external onlyRole(ORACLE_MANAGER_ROLE) {
        require(apr <= 50 * 1e16, "Validator APR too high"); // Max 50%
        validatorAPR = apr;
        emit ValidatorAPRUpdated(apr);
    }
    
    /**
     * @dev Converts XFI amount to MPX amount
     * @param xfiAmount The amount in XFI
     * @return The amount in MPX
     */
    function convertXFItoMPX(uint256 xfiAmount) external view returns (uint256) {
        return (xfiAmount * lastPrice) / PRECISION;
    }
    
    /**
     * @dev Function that authorizes an upgrade
     */
    function _authorizeUpgrade(address newImplementation) 
        internal 
        override 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        // No additional logic needed
    }
    
    /**
     * @dev Sets the DIA Oracle address
     */
    function setDIAOracle(address _oracle) external onlyRole(ORACLE_MANAGER_ROLE) {
        require(_oracle != address(0), "Invalid oracle address");
        diaOracle = IDIAOracle(_oracle);
    }
    
    /**
     * @dev Sets the fallback oracle address
     */
    function setFallbackOracle(address _oracle) external onlyRole(ORACLE_MANAGER_ROLE) {
        require(_oracle != address(0), "Invalid oracle address");
        // Implementation for fallback oracle will be added later
    }
    
    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     */
    uint256[50] private __gap;
} 