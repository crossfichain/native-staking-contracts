// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/INativeStaking.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IWXFI.sol";

/**
 * @title NativeStaking
 * @dev Implementation of the APR staking model (direct staking to validators)
 * Users lock XFI and specify a validator to delegate to
 * Implements the INativeStaking interface
 */
contract NativeStaking is 
    Initializable, 
    AccessControlUpgradeable, 
    PausableUpgradeable, 
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    INativeStaking 
{
    using SafeERC20Upgradeable for IERC20;
    
    // Constants
    uint256 private constant PRECISION = 1e18;
    
    // Custom roles
    bytes32 public constant STAKING_MANAGER_ROLE = keccak256("STAKING_MANAGER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    
    // State variables
    address public stakingToken; // XFI or WXFI
    IOracle public oracle;
    
    // Mapping of user -> array of stake IDs
    mapping(address => uint256[]) private _userStakeIds;
    
    // Mapping of stakeId -> StakeInfo
    mapping(uint256 => StakeInfo) private _stakes;
    
    // Mapping of user -> array of unstake request IDs
    mapping(address => uint256[]) private _userUnstakeRequestIds;
    
    // Mapping of requestId -> UnstakeRequest
    mapping(uint256 => UnstakeRequest) private _unstakeRequests;
    
    // Mapping of user -> unclaimed rewards
    mapping(address => uint256) private _unclaimedRewards;
    
    // Counter for stake IDs
    uint256 private _nextStakeId;
    
    // Counter for unstake request IDs
    uint256 private _nextUnstakeRequestId;
    
    // Minimum stake amount
    uint256 public minStakeAmount;
    
    // Maximum number of concurrent stakes per user
    uint256 public maxStakesPerUser;
    
    // Events
    event Staked(address indexed user, uint256 indexed stakeId, string validator, uint256 amount, uint256 mpxEstimate);
    event UnstakeRequested(address indexed user, uint256 indexed requestId, string validator, uint256 amount, uint256 unlockTime);
    event UnstakeClaimed(address indexed user, uint256 indexed requestId, string validator, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event RewardsAdded(address indexed user, uint256 amount);
    event MinStakeAmountUpdated(uint256 amount);
    event MaxStakesPerUserUpdated(uint256 amount);
    
    /**
     * @dev Initializes the contract
     * @param _stakingToken The address of the staking token (XFI or WXFI)
     * @param _oracle The address of the oracle contract
     */
    function initialize(address _stakingToken, address _oracle) external initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(STAKING_MANAGER_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        
        stakingToken = _stakingToken;
        oracle = IOracle(_oracle);
        
        minStakeAmount = 1 * PRECISION; // 1 XFI
        maxStakesPerUser = 10;
        
        _nextStakeId = 1;
        _nextUnstakeRequestId = 1;
    }
    
    /**
     * @dev Stakes XFI to a specified validator
     * @param user The user who is staking
     * @param amount The amount of XFI to stake
     * @param validator The validator address/ID to stake to
     * @param tokenAddress The address of the token being staked (must match stakingToken)
     * @return success Boolean indicating if the stake was successful
     */
    function stake(address user, uint256 amount, string calldata validator, address tokenAddress) 
        external 
        override 
        whenNotPaused 
        nonReentrant 
        onlyRole(STAKING_MANAGER_ROLE) 
        returns (bool success) 
    {
        require(user != address(0), "Invalid user address");
        require(amount >= minStakeAmount, "Amount below minimum");
        require(tokenAddress == stakingToken, "Invalid token");
        require(oracle.isValidatorActive(validator), "Validator not active");
        require(_userStakeIds[user].length < maxStakesPerUser, "Max stakes reached");
        
        // Store the stake information
        uint256 stakeId = _nextStakeId++;
        
        _stakes[stakeId] = StakeInfo({
            amount: amount,
            stakedAt: block.timestamp,
            unbondingAt: 0, // 0 means not unbonding
            validator: validator
        });
        
        _userStakeIds[user].push(stakeId);
        
        // Calculate MPX estimate based on current prices
        uint256 xfiPrice = oracle.getPrice("XFI");
        uint256 mpxPrice = oracle.getPrice("MPX");
        uint256 mpxEstimate = 0;
        
        if (mpxPrice > 0 && xfiPrice > 0) {
            mpxEstimate = (amount * xfiPrice) / mpxPrice;
        }
        
        emit Staked(user, stakeId, validator, amount, mpxEstimate);
        
        return true;
    }
    
    /**
     * @dev Requests to unstake XFI from a specified validator
     * @param user The user who is unstaking
     * @param amount The amount of XFI to unstake
     * @param validator The validator address/ID to unstake from
     * @return requestId The ID of the unstake request
     */
    function requestUnstake(address user, uint256 amount, string calldata validator) 
        external 
        override 
        whenNotPaused 
        nonReentrant 
        onlyRole(STAKING_MANAGER_ROLE) 
        returns (uint256 requestId) 
    {
        require(user != address(0), "Invalid user address");
        require(amount > 0, "Amount must be positive");
        
        // Find the stake with the matching validator and sufficient amount
        (uint256 stakeId, uint256 remainingAmount) = _findAndUpdateStake(user, validator, amount);
        
        // Calculate unlock time based on unbonding period
        uint256 unbondingPeriod = oracle.getUnbondingPeriod();
        uint256 unlockTime = block.timestamp + unbondingPeriod;
        
        // Create unstake request
        requestId = _nextUnstakeRequestId++;
        
        _unstakeRequests[requestId] = UnstakeRequest({
            amount: amount,
            unlockTime: unlockTime,
            validator: validator,
            completed: false
        });
        
        _userUnstakeRequestIds[user].push(requestId);
        
        // If stake is fully unstaked, mark it as unbonding
        if (remainingAmount == 0) {
            _stakes[stakeId].unbondingAt = block.timestamp;
        }
        
        emit UnstakeRequested(user, requestId, validator, amount, unlockTime);
        
        return requestId;
    }
    
    /**
     * @dev Helper function to find and update a stake
     * @param user The user address
     * @param validator The validator to unstake from
     * @param amount The amount to unstake
     * @return stakeId The ID of the stake that was updated
     * @return remainingAmount The amount remaining in the stake after unstaking
     */
    function _findAndUpdateStake(address user, string calldata validator, uint256 amount) 
        private 
        returns (uint256 stakeId, uint256 remainingAmount) 
    {
        uint256[] storage stakeIds = _userStakeIds[user];
        require(stakeIds.length > 0, "No stakes found");
        
        bool found = false;
        uint256 totalAvailable = 0;
        
        // First, calculate total staked with this validator
        for (uint256 i = 0; i < stakeIds.length; i++) {
            StakeInfo storage stake = _stakes[stakeIds[i]];
            if (
                keccak256(bytes(stake.validator)) == keccak256(bytes(validator)) && 
                stake.unbondingAt == 0 // Not already unbonding
            ) {
                totalAvailable += stake.amount;
            }
        }
        
        require(totalAvailable >= amount, "Insufficient staked amount");
        
        // Now find a stake to update
        uint256 amountToUnstake = amount;
        
        for (uint256 i = 0; i < stakeIds.length && amountToUnstake > 0; i++) {
            stakeId = stakeIds[i];
            StakeInfo storage stake = _stakes[stakeId];
            
            if (
                keccak256(bytes(stake.validator)) == keccak256(bytes(validator)) && 
                stake.unbondingAt == 0 // Not already unbonding
            ) {
                found = true;
                
                if (stake.amount <= amountToUnstake) {
                    // Fully unstake this position
                    amountToUnstake -= stake.amount;
                    stake.amount = 0;
                    remainingAmount = 0;
                } else {
                    // Partially unstake
                    stake.amount -= amountToUnstake;
                    amountToUnstake = 0;
                    remainingAmount = stake.amount;
                }
                
                if (amountToUnstake == 0) {
                    break;
                }
            }
        }
        
        require(found, "No matching stake found");
        return (stakeId, remainingAmount);
    }
    
    /**
     * @dev Claims XFI from a completed unstake request
     * @param user The user claiming the unstaked XFI
     * @param requestId The ID of the unstake request to claim
     * @return amount The amount of XFI claimed
     */
    function claimUnstake(address user, uint256 requestId) 
        external 
        override 
        nonReentrant 
        returns (uint256 amount) 
    {
        require(user != address(0), "Invalid user address");
        require(_isUserUnstakeRequest(user, requestId), "Not user's request");
        
        UnstakeRequest storage request = _unstakeRequests[requestId];
        require(!request.completed, "Already claimed");
        require(block.timestamp >= request.unlockTime, "Still in unbonding period");
        
        request.completed = true;
        amount = request.amount;
        
        // Transfer the tokens back to the user
        IERC20(stakingToken).safeTransfer(user, amount);
        
        emit UnstakeClaimed(user, requestId, request.validator, amount);
        
        return amount;
    }
    
    /**
     * @dev Helper function to check if an unstake request belongs to a user
     * @param user The user address
     * @param requestId The unstake request ID
     * @return True if the request belongs to the user
     */
    function _isUserUnstakeRequest(address user, uint256 requestId) private view returns (bool) {
        uint256[] storage requestIds = _userUnstakeRequestIds[user];
        
        for (uint256 i = 0; i < requestIds.length; i++) {
            if (requestIds[i] == requestId) {
                return true;
            }
        }
        
        return false;
    }
    
    /**
     * @dev Adds rewards for a user (called by the operator)
     * @param user The user to add rewards for
     * @param amount The amount of rewards to add
     * @return success Boolean indicating if the operation was successful
     */
    function addRewards(address user, uint256 amount) 
        external 
        whenNotPaused 
        nonReentrant 
        onlyRole(OPERATOR_ROLE) 
        returns (bool success) 
    {
        require(user != address(0), "Invalid user address");
        require(amount > 0, "Amount must be positive");
        
        _unclaimedRewards[user] += amount;
        
        emit RewardsAdded(user, amount);
        
        return true;
    }
    
    /**
     * @dev Claims staking rewards for a user
     * @param user The user to claim rewards for
     * @return amount The amount of rewards claimed
     */
    function claimRewards(address user) 
        external 
        override 
        nonReentrant 
        returns (uint256 amount) 
    {
        require(user != address(0), "Invalid user address");
        require(
            msg.sender == user || 
            hasRole(STAKING_MANAGER_ROLE, msg.sender) || 
            hasRole(OPERATOR_ROLE, msg.sender), 
            "Not authorized"
        );
        
        amount = _unclaimedRewards[user];
        require(amount > 0, "No rewards to claim");
        
        _unclaimedRewards[user] = 0;
        
        // Transfer the rewards to the user
        IERC20(stakingToken).safeTransfer(user, amount);
        
        emit RewardsClaimed(user, amount);
        
        return amount;
    }
    
    /**
     * @dev Gets all active stakes for a user
     * @param user The user to get stakes for
     * @return An array of StakeInfo structs
     */
    function getUserStakes(address user) 
        external 
        view 
        override 
        returns (StakeInfo[] memory) 
    {
        uint256[] storage stakeIds = _userStakeIds[user];
        StakeInfo[] memory result = new StakeInfo[](stakeIds.length);
        
        for (uint256 i = 0; i < stakeIds.length; i++) {
            result[i] = _stakes[stakeIds[i]];
        }
        
        return result;
    }
    
    /**
     * @dev Gets all pending unstake requests for a user
     * @param user The user to get unstake requests for
     * @return An array of UnstakeRequest structs
     */
    function getUserUnstakeRequests(address user) 
        external 
        view 
        override 
        returns (UnstakeRequest[] memory) 
    {
        uint256[] storage requestIds = _userUnstakeRequestIds[user];
        UnstakeRequest[] memory result = new UnstakeRequest[](requestIds.length);
        
        for (uint256 i = 0; i < requestIds.length; i++) {
            result[i] = _unstakeRequests[requestIds[i]];
        }
        
        return result;
    }
    
    /**
     * @dev Gets the total amount of XFI staked by a user
     * @param user The user to get the total for
     * @return The total amount of XFI staked
     */
    function getTotalStaked(address user) 
        external 
        view 
        override 
        returns (uint256) 
    {
        uint256[] storage stakeIds = _userStakeIds[user];
        uint256 total = 0;
        
        for (uint256 i = 0; i < stakeIds.length; i++) {
            StakeInfo storage stake = _stakes[stakeIds[i]];
            if (stake.unbondingAt == 0) { // Only count active stakes
                total += stake.amount;
            }
        }
        
        return total;
    }
    
    /**
     * @dev Gets the total amount of unclaimed rewards for a user
     * @param user The user to get the rewards for
     * @return The total amount of unclaimed rewards
     */
    function getUnclaimedRewards(address user) 
        external 
        view 
        override 
        returns (uint256) 
    {
        return _unclaimedRewards[user];
    }
    
    /**
     * @dev Sets the minimum stake amount
     * @param amount The new minimum stake amount
     */
    function setMinStakeAmount(uint256 amount) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        minStakeAmount = amount;
        emit MinStakeAmountUpdated(amount);
    }
    
    /**
     * @dev Sets the maximum number of concurrent stakes per user
     * @param max The new maximum number of stakes
     */
    function setMaxStakesPerUser(uint256 max) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(max > 0, "Max stakes must be positive");
        maxStakesPerUser = max;
        emit MaxStakesPerUserUpdated(max);
    }
    
    /**
     * @dev Sets the oracle contract address
     * @param _oracle The new oracle address
     */
    function setOracle(address _oracle) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(_oracle != address(0), "Invalid oracle address");
        oracle = IOracle(_oracle);
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