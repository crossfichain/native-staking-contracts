// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IAPRStaking.sol";
import "../interfaces/IOracle.sol";

/**
 * @title APRStaking
 * @dev Implementation of the APR staking model
 * Users stake XFI with specific validators and receive rewards based on APR
 */
contract APRStaking is 
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    IAPRStaking
{
    // Constants
    uint256 private constant PRECISION = 1e18;
    
    // Custom roles
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    
    // State variables
    IOracle public oracle;
    address public stakingToken;
    
    // Staking state
    mapping(address => uint256) private _userTotalStaked;
    mapping(address => mapping(string => uint256)) private _userValidatorStakes;
    mapping(address => string[]) private _userValidators;
    mapping(string => uint256) private _validatorTotalStaked;
    
    // Unstaking state
    struct UnstakeRequest {
        address user;
        uint256 amount;
        string validator;
        uint256 timestamp;
        bool claimed;
    }
    
    mapping(uint256 => UnstakeRequest) private _unstakeRequests;
    uint256 private _nextUnstakeRequestId;
    
    // Events
    event Staked(address indexed user, uint256 amount, string validator);
    event UnstakeRequested(address indexed user, uint256 amount, string validator, uint256 indexed requestId);
    event UnstakeClaimed(address indexed user, uint256 amount, uint256 indexed requestId);
    event RewardsClaimed(address indexed user, uint256 amount);
    event StakingTokenUpdated(address indexed newToken);
    
    /**
     * @dev Initializes the contract
     * @param _oracle The address of the oracle contract
     * @param _stakingToken The address of the staking token (WXFI)
     */
    function initialize(address _oracle, address _stakingToken) external initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        
        oracle = IOracle(_oracle);
        stakingToken = _stakingToken;
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
        require(bytes(validator).length > 0, "Validator cannot be empty");
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
    {
        require(amount > 0, "Amount must be greater than 0");
        require(_userValidatorStakes[user][validator] >= amount, "Insufficient stake");
        
        // Update staking state
        _userTotalStaked[user] -= amount;
        _userValidatorStakes[user][validator] -= amount;
        _validatorTotalStaked[validator] -= amount;
        
        // Remove validator from user's list if no stake left
        if (_userValidatorStakes[user][validator] == 0) {
            _removeValidatorFromUser(user, validator);
        }
        
        // Create unstake request
        uint256 requestId = _nextUnstakeRequestId++;
        _unstakeRequests[requestId] = UnstakeRequest({
            user: user,
            amount: amount,
            validator: validator,
            timestamp: block.timestamp,
            claimed: false
        });
        
        emit UnstakeRequested(user, amount, validator, requestId);
    }
    
    /**
     * @dev Claims unstaked XFI tokens after the unbonding period
     * @param user The address of the user claiming
     * @param requestId The ID of the unstake request
     * @return amount The amount of XFI claimed
     */
    function claimUnstake(
        address user,
        uint256 requestId
    ) 
        external 
        override 
        nonReentrant 
        returns (uint256 amount) 
    {
        // Extract the actual request ID when it's a structured ID
        uint256 actualRequestId = requestId;
        
        // Check if this is a structured requestId (using same threshold as NativeStaking)
        if (requestId >= 4294967296) { // 2^32
            // Extract the sequence number from the last 4 bytes (same as in NativeStaking)
            actualRequestId = uint256(uint32(requestId));
        }
        
        UnstakeRequest storage request = _unstakeRequests[actualRequestId];
        require(request.user == user, "Not request owner");
        require(!request.claimed, "Already claimed");
        require(block.timestamp >= request.timestamp + oracle.getUnbondingPeriod(), "Still in unbonding period");
        
        amount = request.amount;
        request.claimed = true;
        
        // Transfer tokens back to the manager
        bool transferred = IERC20(stakingToken).transfer(msg.sender, amount);
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
     * @return The total amount staked
     */
    function getTotalStaked() 
        external 
        view 
        override 
        returns (uint256) 
    {
        uint256 total = 0;
        for (uint256 i = 0; i < _nextUnstakeRequestId; i++) {
            if (!_unstakeRequests[i].claimed) {
                total += _unstakeRequests[i].amount;
            }
        }
        return total;
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
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
} 