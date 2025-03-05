// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/INativeStaking.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IWXFI.sol";

/**
 * @title NativeStaking
 * @dev Implementation of the APR staking model
 * Users lock XFI and specify a validator to delegate to (handled off-chain)
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
    // Constants
    uint256 private constant PRECISION = 1e18;
    
    // Custom roles
    bytes32 public constant STAKING_MANAGER_ROLE = keccak256("STAKING_MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    
    // State variables
    IERC20 public stakingToken;
    IOracle public oracle;
    uint256 public minStakeAmount;
    uint256 public maxStakesPerUser;
    
    // Mappings - simplified to remove validator-specific storage
    mapping(address => StakeInfo[]) private _userStakes;
    mapping(address => UnstakeRequest[]) private _userUnstakeRequests;
    mapping(address => uint256) private _totalStakedByUser;
    mapping(address => uint256) private _lastClaimTime;
    
    // Events
    event Staked(address indexed user, uint256 amount, string validator, uint256 stakeId);
    event UnstakeRequested(address indexed user, uint256 amount, string validator, uint256 indexed requestId, uint256 unlockTime);
    event UnstakeClaimed(address indexed user, uint256 amount, uint256 indexed requestId);
    event RewardsClaimed(address indexed user, uint256 amount);
    event RewardsAdded(string validator, uint256 amount);
    event TreasuryUpdated(address newTreasury);
    event MinStakeAmountUpdated(uint256 newAmount);
    event MaxStakesPerUserUpdated(uint256 newLimit);
    
    /**
     * @dev Initializes the contract
     * @param _stakingToken The address of the staking token (WXFI)
     * @param _oracle The address of the oracle contract
     */
    function initialize(
        address _stakingToken,
        address _oracle
    ) external initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(STAKING_MANAGER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        
        stakingToken = IERC20(_stakingToken);
        oracle = IOracle(_oracle);
        
        // Default values
        minStakeAmount = 1 ether;
        maxStakesPerUser = 10;
    }
    
    /**
     * @dev Stakes XFI with validator information emitted in events
     * @param user The user who is staking
     * @param amount The amount of XFI to stake
     * @param validator The validator address/ID to stake to (only used in events)
     * @param tokenAddress The address of token being staked (XFI or WXFI)
     * @return success Boolean indicating if the stake was successful
     */
    function stake(address user, uint256 amount, string calldata validator, address tokenAddress) 
        external 
        override 
        onlyRole(STAKING_MANAGER_ROLE) 
        whenNotPaused 
        returns (bool success) 
    {
        require(amount >= minStakeAmount, "Amount below minimum");
        require(_userStakes[user].length < maxStakesPerUser, "Max stakes reached");
        
        // Transfer tokens from the manager contract
        bool transferred = IERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);
        require(transferred, "Transfer failed");
        
        // Add stake to user's stakes (simplified, no validator storage)
        StakeInfo memory newStake = StakeInfo({
            amount: amount,
            stakedAt: block.timestamp,
            unbondingAt: 0
        });
        
        _userStakes[user].push(newStake);
        _totalStakedByUser[user] += amount;
        
        // Set initial claim time if first stake
        if (_lastClaimTime[user] == 0) {
            _lastClaimTime[user] = block.timestamp;
        }
        
        // Emit event with validator information for off-chain processing
        uint256 stakeId = _userStakes[user].length - 1;
        emit Staked(user, amount, validator, stakeId);
        
        return true;
    }
    
    /**
     * @dev Requests to unstake XFI
     * @param user The user who is unstaking
     * @param amount The amount of XFI to unstake
     * @param validator The validator address/ID to unstake from (only used in events)
     * @return requestId The ID of the unstake request
     */
    function requestUnstake(address user, uint256 amount, string calldata validator) 
        external 
        override 
        onlyRole(STAKING_MANAGER_ROLE) 
        whenNotPaused 
        returns (uint256 requestId) 
    {
        require(amount > 0, "Amount must be > 0");
        require(_totalStakedByUser[user] >= amount, "Insufficient staked amount");
        
        // Calculate unlock time based on unbonding period
        uint256 unlockTime = block.timestamp + oracle.getUnbondingPeriod();
        
        // Create unstake request (simplified, validator only in event)
        UnstakeRequest memory request = UnstakeRequest({
            amount: amount,
            unlockTime: unlockTime,
            completed: false
        });
        
        _userUnstakeRequests[user].push(request);
        requestId = _userUnstakeRequests[user].length - 1;
        
        // Find stakes to mark as unbonding
        uint256 remainingAmount = amount;
        for (uint256 i = 0; i < _userStakes[user].length && remainingAmount > 0; i++) {
            StakeInfo storage stakeItem = _userStakes[user][i];
            if (stakeItem.unbondingAt == 0 && stakeItem.amount > 0) {
                uint256 unstakeAmount = stakeItem.amount <= remainingAmount ? stakeItem.amount : remainingAmount;
                
                if (unstakeAmount == stakeItem.amount) {
                    // Unstaking entire stake
                    stakeItem.unbondingAt = block.timestamp;
                } else {
                    // Unstaking partial stake
                    // Create a new unbonding stake entry
                    _userStakes[user].push(StakeInfo({
                        amount: unstakeAmount,
                        stakedAt: stakeItem.stakedAt,
                        unbondingAt: block.timestamp
                    }));
                    
                    // Reduce the original stake
                    stakeItem.amount -= unstakeAmount;
                }
                
                remainingAmount -= unstakeAmount;
            }
        }
        
        // Update total staked amount
        _totalStakedByUser[user] -= amount;
        
        // Emit event with validator information for off-chain processing
        emit UnstakeRequested(user, amount, validator, requestId, unlockTime);
        
        return requestId;
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
        onlyRole(STAKING_MANAGER_ROLE) 
        returns (uint256 amount) 
    {
        require(requestId < _userUnstakeRequests[user].length, "Invalid request ID");
        UnstakeRequest storage request = _userUnstakeRequests[user][requestId];
        
        require(!request.completed, "Already claimed");
        require(block.timestamp >= request.unlockTime, "Still in unbonding period");
        
        amount = request.amount;
        request.completed = true;
        
        // Claim any pending rewards first
        _claimRewards(user);
        
        // Transfer tokens back to the user via manager
        bool transferred = stakingToken.transfer(msg.sender, amount);
        require(transferred, "Transfer failed");
        
        emit UnstakeClaimed(user, amount, requestId);
        
        return amount;
    }
    
    /**
     * @dev Adds rewards to be distributed
     * @param validator The validator that generated the rewards
     * @param amount The amount of rewards to add
     * @return success Boolean indicating if the addition was successful
     */
    function addRewards(string calldata validator, uint256 amount) 
        external 
        onlyRole(STAKING_MANAGER_ROLE) 
        returns (bool success) 
    {
        // For APR model, rewards are claimed on-demand based on APR
        // This function can be used to actually add extra rewards
        // In a real implementation, this would update some internal reward state
        
        emit RewardsAdded(validator, amount);
        
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
        onlyRole(STAKING_MANAGER_ROLE) 
        returns (uint256 amount) 
    {
        return _claimRewards(user);
    }
    
    /**
     * @dev Internal function to claim staking rewards
     * @param user The user to claim rewards for
     * @return amount The amount of rewards claimed
     */
    function _claimRewards(address user) private returns (uint256 amount) {
        uint256 rewards = getUnclaimedRewards(user);
        
        if (rewards > 0) {
            _lastClaimTime[user] = block.timestamp;
            
            // Transfer rewards to the user via manager
            bool transferred = stakingToken.transfer(msg.sender, rewards);
            require(transferred, "Transfer failed");
            
            emit RewardsClaimed(user, rewards);
        }
        
        return rewards;
    }
    
    /**
     * @dev Gets details of a specific stake by index
     * @param user The user to get the stake for
     * @param index The index of the stake
     * @return amount The amount of XFI staked
     * @return timestamp The timestamp when the stake was created
     */
    function getUserStake(address user, uint256 index)
        external
        view
        returns (uint256 amount, uint256 timestamp)
    {
        require(index < _userStakes[user].length, "Invalid stake index");
        StakeInfo storage stakeItem = _userStakes[user][index];
        
        return (stakeItem.amount, stakeItem.stakedAt);
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
        return _userStakes[user];
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
        return _userUnstakeRequests[user];
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
        return _totalStakedByUser[user];
    }
    
    /**
     * @dev Gets the total amount of unclaimed rewards for a user
     * @param user The user to get the rewards for
     * @return The total amount of unclaimed rewards
     */
    function getUnclaimedRewards(address user) 
        public 
        view 
        override 
        returns (uint256) 
    {
        if (_totalStakedByUser[user] == 0 || _lastClaimTime[user] == 0) {
            return 0;
        }
        
        uint256 totalRewards = 0;
        uint256 timeElapsed = block.timestamp - _lastClaimTime[user];
        
        // Calculate rewards for each active stake
        for (uint256 i = 0; i < _userStakes[user].length; i++) {
            StakeInfo storage stakeItem = _userStakes[user][i];
            
            // Skip if stake is in unbonding
            if (stakeItem.unbondingAt > 0) {
                continue;
            }
            
            // Get current APR (annual percentage rate)
            uint256 validatorAPR = oracle.getCurrentAPR();
            
            // Calculate rewards: amount * APR * timeElapsed / 365 days
            uint256 stakeRewards = stakeItem.amount * validatorAPR * timeElapsed / (365 days) / PRECISION;
            totalRewards += stakeRewards;
        }
        
        return totalRewards;
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
     * @dev Sets the maximum number of stakes per user
     * @param limit The new maximum number of stakes
     */
    function setMaxStakesPerUser(uint256 limit) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(limit > 0, "Limit must be > 0");
        maxStakesPerUser = limit;
        emit MaxStakesPerUserUpdated(limit);
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