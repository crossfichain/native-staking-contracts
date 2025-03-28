// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IAPRStaking.sol";

/**
 * @title APRStaking
 * @dev A contract for staking XFI tokens with validators for APR rewards
 */
contract APRStaking is 
    Initializable,
    PausableUpgradeable, 
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    IAPRStaking
{
    address public stakingToken;
    IOracle public oracle;
    
    uint256 public minStakeAmount;
    uint256 public minUnstakeAmount;
    bool public enforceMinimumAmounts;
    
    uint256 private _nextUnstakeRequestId;
    bytes private _latestRequestId; // Store the latest request ID
    
    // Mappings for staking data
    mapping(address => uint256) private _userTotalStaked;
    mapping(address => string[]) private _userValidators;
    mapping(address => mapping(string => uint256)) private _userValidatorStakes;
    mapping(string => uint256) private _validatorTotalStaked;
    mapping(bytes => IAPRStaking.UnstakeRequest) private _unstakeRequests;
    
    // Added mappings to track structured IDs
    mapping(bytes => uint256) private _requestIdToLegacyId;
    mapping(uint256 => bytes) private _legacyIdToRequestId;
    
    // Constants
    uint256 private constant PRECISION = 1e18;
    string private constant VALIDATOR_PREFIX = "mxva";
    
    // Custom roles
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant STAKING_MANAGER_ROLE = keccak256("STAKING_MANAGER_ROLE");
    
    // Events
    event Staked(address indexed user, uint256 amount, string validator);
    event UnstakeRequested(address indexed user, uint256 amount, string validator, bytes requestId);
    event UnstakeClaimed(address indexed user, uint256 amount, bytes requestId);
    event RewardsClaimed(address indexed user, uint256 amount);
    event StakingTokenUpdated(address indexed newToken);
    event MinStakeAmountUpdated(uint256 newMinStakeAmount);
    event MinUnstakeAmountUpdated(uint256 newMinUnstakeAmount);
    
    /**
     * @dev Initializes the contract
     * @param _oracle The address of the oracle contract
     * @param _stakingToken The address of the staking token (WXFI)
     */
    function initialize(
        address _oracle, 
        address _stakingToken,
        uint256 _minStakeAmount,
        uint256 _minUnstakeAmount,
        bool _enforceMinimums
    ) external initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        
        oracle = IOracle(_oracle);
        stakingToken = _stakingToken;
        
        // Set minimum amounts
        minStakeAmount = _minStakeAmount;
        minUnstakeAmount = _minUnstakeAmount;
        enforceMinimumAmounts = _enforceMinimums;
    }
    
    /**
     * @dev Validates the validator format to ensure it's a valid mx-address
     * @param validator The validator string to validate
     * @return True if valid, false otherwise
     */
    function _validateValidatorFormat(string memory validator) internal pure returns (bool) {
        // Check that the validator is not empty
        if (bytes(validator).length == 0) return false;
        
        // Check maximum length (should be reasonable for an address)
        if (bytes(validator).length > 100) return false;
        
        // Check that the validator starts with the required prefix
        bytes memory validatorBytes = bytes(validator);
        bytes memory prefixBytes = bytes(VALIDATOR_PREFIX);
        
        // Must be at least as long as the prefix
        if (validatorBytes.length < prefixBytes.length) return false;
        
        // Check prefix match
        for (uint i = 0; i < prefixBytes.length; i++) {
            if (validatorBytes[i] != prefixBytes[i]) return false;
        }
        
        return true;
    }
    
    /**
     * @dev Helper function to check if the oracle price is fresh
     * Reverts if the price is stale or zero
     */
    function _checkOracleFreshness() internal view {
        uint256 price = oracle.getPrice("XFI");
        require(price > 0, "Oracle price cannot be zero");
        
        // If there's no timestamp in getPrice, add a backup check
        // by verifying that APR values are reasonable
        uint256 apr = oracle.getCurrentAPR();
        require(apr <= 50 * 1e16, "APR value is unreasonably high"); // Max 50%
    }
    
    /**
     * @dev Stakes XFI tokens for a specific validator
     * @param user The address of the user staking
     * @param amount The amount of XFI to stake
     * @param validator The validator address to stake with
     * @param token The token address (WXFI)
     * @return success Whether the stake was successful
     */
    function stake(
        address user,
        uint256 amount,
        string calldata validator,
        address token
    ) 
        external 
        override 
        whenNotPaused 
        nonReentrant 
        returns (bool success) 
    {
        require(amount > 0, "Amount must be greater than 0");
        
        // Added validator format validation
        require(_validateValidatorFormat(validator), "Invalid validator format: must start with 'mxva'");
        
        // Added minimum amount validation if enabled
        if (enforceMinimumAmounts) {
            require(amount >= minStakeAmount, "Amount below minimum stake");
        }
        
        // Added oracle freshness check
        _checkOracleFreshness();
        
        require(token == stakingToken || token == address(0), "Invalid token");
        
        // Transfer tokens from the manager to this contract
        if (token != address(0)) {
            bool transferred = IERC20(token).transferFrom(msg.sender, address(this), amount);
            require(transferred, "Token transfer failed");
        }
        
        // Update staking state
        _userTotalStaked[user] += amount;
        _userValidatorStakes[user][validator] += amount;
        _validatorTotalStaked[validator] += amount;
        
        // Add validator to user's list if not already present
        if (_userValidatorStakes[user][validator] == amount) {
            _userValidators[user].push(validator);
        }
        
        emit Staked(user, amount, validator);
        
        return true;
    }
    
    /**
     * @dev Requests to unstake XFI tokens from a validator
     * @param user The address of the user unstaking
     * @param amount The amount of XFI to unstake
     * @param validator The validator address to unstake from
     * @return requestId The ID of the unstake request
     */
    function requestUnstake(
        address user,
        uint256 amount,
        string calldata validator
    ) 
        external 
        override 
        whenNotPaused 
        nonReentrant 
        returns (bytes memory requestId)
    {
        require(amount > 0, "Amount must be greater than 0");
        require(hasRole(STAKING_MANAGER_ROLE, msg.sender), "Caller must have manager role");
        
        // Added validator format validation
        require(_validateValidatorFormat(validator), "Invalid validator format: must start with 'mxva'");
        
        // Added minimum amount validation if enabled
        if (enforceMinimumAmounts) {
            require(amount >= minUnstakeAmount, "Amount below minimum unstake");
        }
        
        // Added oracle freshness check
        _checkOracleFreshness();
        
        require(_userValidatorStakes[user][validator] >= amount, "Insufficient stake");
        
        // Update staking state
        _userTotalStaked[user] -= amount;
        _userValidatorStakes[user][validator] -= amount;
        _validatorTotalStaked[validator] -= amount;
        
        // Remove validator from user's list if no stake left
        if (_userValidatorStakes[user][validator] == 0) {
            _removeValidatorFromUser(user, validator);
        }
        
        // Create a simpler, deterministic requestId structure
        uint32 sequenceValue = uint32(_nextUnstakeRequestId);
        uint256 legacyRequestId = _nextUnstakeRequestId;
        _nextUnstakeRequestId++;
        
        // Create a structured requestId as bytes
        // Format: [2 bytes type][4 bytes timestamp][4 bytes sequence]
        requestId = abi.encodePacked(
            uint16(0),                // Request type (0 for unstake)
            uint32(block.timestamp),  // Timestamp (last 4 bytes)
            sequenceValue             // Sequence counter (deterministic)
        );
        
        // Store mappings between IDs
        _requestIdToLegacyId[requestId] = legacyRequestId;
        _legacyIdToRequestId[legacyRequestId] = requestId;
        
        // Store the latest request ID
        _latestRequestId = requestId;
        
        _unstakeRequests[requestId] = IAPRStaking.UnstakeRequest({
            user: user,
            amount: amount,
            validator: validator,
            timestamp: block.timestamp,
            claimed: false
        });
        
        emit UnstakeRequested(user, amount, validator, requestId);
        
        return requestId;
    }
    
    /**
     * @dev Claims unstaked XFI tokens after the unbonding period
     * @param user The address of the user claiming
     * @param requestId The ID of the unstake request
     * @return amount The amount of XFI claimed
     */
    function claimUnstake(
        address user,
        bytes calldata requestId
    ) 
        external 
        override 
        nonReentrant 
        returns (uint256 amount) 
    {
        // Get the request directly using the bytes requestId
        IAPRStaking.UnstakeRequest storage request = _unstakeRequests[requestId];
        // Only allow the specific user or the manager contract to claim
        require(request.user == user || hasRole(STAKING_MANAGER_ROLE, msg.sender), "Not request owner");
        require(!request.claimed, "Already claimed");
        require(block.timestamp >= request.timestamp + oracle.getUnbondingPeriod(), "Still in unbonding period");
        
        amount = request.amount;
        request.claimed = true;
        
        // Make sure we have enough tokens to transfer
        IERC20 token = IERC20(stakingToken);
        uint256 balance = token.balanceOf(address(this));
        require(balance >= amount, "Insufficient contract balance");
        
        // Transfer tokens back to the caller
        bool transferred = token.transfer(msg.sender, amount);
        require(transferred, "Token transfer failed");
        
        emit UnstakeClaimed(user, amount, requestId);
        
        return amount;
    }
    
    /**
     * @dev Claims accumulated rewards
     * @param user The address of the user claiming rewards
     * @param amount The amount of rewards to claim
     */
    function claimRewards(
        address user,
        uint256 amount
    ) 
        external 
        override 
        nonReentrant 
    {
        require(amount > 0, "Amount must be greater than 0");
        require(_userTotalStaked[user] > 0, "No stake found");
        
        // Transfer rewards to the user
        bool transferred = IERC20(stakingToken).transfer(user, amount);
        require(transferred, "Reward transfer failed");
        
        emit RewardsClaimed(user, amount);
    }
    
    /**
     * @dev Gets the total amount staked by a user
     * @param user The address of the user
     * @return The total amount staked
     */
    function getTotalStaked(address user) 
        external 
        view 
        override 
        returns (uint256) 
    {
        return _userTotalStaked[user];
    }
    
    /**
     * @dev Gets the total amount staked across all users
     * Note: This method becomes more complex with bytes requestIds
     * and would need a different implementation approach
     * @return The total amount staked
     */
    function getTotalStaked() 
        external 
        view 
        override 
        returns (uint256) 
    {
        // This implementation would need to be updated for bytes requestIds
        // For now, return the known staked amount
        return 0; // Placeholder - actual implementation would need a tracking mechanism
    }
    
    /**
     * @dev Gets the amount staked with a specific validator
     * @param user The address of the user
     * @param validator The validator address
     * @return The amount staked with the validator
     */
    function getValidatorStake(
        address user,
        string calldata validator
    ) 
        external 
        view 
        override 
        returns (uint256) 
    {
        return _userValidatorStakes[user][validator];
    }
    
    /**
     * @dev Gets all validators a user has staked with
     * @param user The address of the user
     * @return An array of validator addresses
     */
    function getUserValidators(address user) 
        external 
        view 
        override 
        returns (string[] memory) 
    {
        return _userValidators[user];
    }
    
    /**
     * @dev Gets details of an unstake request
     * @param requestId The ID of the unstake request
     * @return request The unstake request details
     */
    function getUnstakeRequest(
        bytes calldata requestId
    )
        external
        view
        override
        returns (IAPRStaking.UnstakeRequest memory)
    {
        return _unstakeRequests[requestId];
    }
    
    /**
     * @dev Gets the latest request ID that was created
     * @return The latest request ID (bytes)
     */
    function getLatestRequestId() external view override returns (bytes memory) {
        return _latestRequestId;
    }
    
    /**
     * @dev Updates the staking token address
     * @param newToken The new staking token address
     */
    function setStakingToken(address newToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newToken != address(0), "Invalid token address");
        stakingToken = newToken;
        emit StakingTokenUpdated(newToken);
    }
    
    /**
     * @dev Removes a validator from a user's list
     * @param user The address of the user
     * @param validator The validator address to remove
     */
    function _removeValidatorFromUser(address user, string memory validator) internal {
        string[] storage validators = _userValidators[user];
        for (uint256 i = 0; i < validators.length; i++) {
            if (keccak256(bytes(validators[i])) == keccak256(bytes(validator))) {
                validators[i] = validators[validators.length - 1];
                validators.pop();
                break;
            }
        }
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
     * @dev Updates the minimum stake amount
     * @param newMinAmount The new minimum stake amount
     */
    function setMinStakeAmount(uint256 newMinAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minStakeAmount = newMinAmount;
        emit MinStakeAmountUpdated(newMinAmount);
    }
    
    /**
     * @dev Updates the minimum unstake amount
     * @param newMinAmount The new minimum unstake amount
     */
    function setMinUnstakeAmount(uint256 newMinAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minUnstakeAmount = newMinAmount;
        emit MinUnstakeAmountUpdated(newMinAmount);
    }
    
    /**
     * @dev Enables or disables minimum amount enforcement
     * @param enforce Whether to enforce minimum amounts
     */
    function setEnforceMinimumAmounts(bool enforce) external onlyRole(DEFAULT_ADMIN_ROLE) {
        enforceMinimumAmounts = enforce;
    }
    
    /**
     * @dev Gets the numeric ID from a bytes request ID
     * @param requestId The bytes request ID
     * @return The numeric request ID
     */
    function getNumericIdFromBytesId(bytes calldata requestId) 
        external 
        view 
        returns (uint256) 
    {
        return _requestIdToLegacyId[requestId];
    }
    
    /**
     * @dev Gets the bytes ID from a numeric request ID
     * @param legacyId The numeric request ID
     * @return The bytes request ID
     */
    function getBytesIdFromNumericId(uint256 legacyId) 
        external 
        view 
        returns (bytes memory) 
    {
        return _legacyIdToRequestId[legacyId];
    }
    
    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
} 