// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    
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
    
    // Counter for legacy request IDs
    uint256 private _nextRequestId;
    
    // Mappings - simplified to remove validator-specific storage
    mapping(address => StakeInfo[]) private _userStakes;
    mapping(address => UnstakeRequest[]) private _userUnstakeRequests;
    mapping(address => uint256) private _totalStakedByUser;
    mapping(address => uint256) private _lastClaimTime;
    
    // New mapping to map requestId (as bytes) to array index
    mapping(address => mapping(bytes32 => uint256)) private _requestIdToIndex;
    
    // Add a private field to track the latest request ID
    bytes private _latestRequestId;
    
    // Events
    event Staked(address indexed user, uint256 amount, string validator, uint256 stakeId);
    event UnstakeRequested(address indexed user, uint256 amount, string validator, bytes indexed requestId, uint256 unlockTime);
    event UnstakeClaimed(address indexed user, uint256 amount, bytes indexed requestId);
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
        
        // Initialize the request ID counter
        _nextRequestId = 1;
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
        require(getActiveStakeCount(user) < maxStakesPerUser, "Max stakes reached");
        
        // Transfer tokens from the manager contract
        bool transferred = IERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);
        require(transferred, "Transfer failed");
        
        // Check if user already has a stake with this validator
        bool existingStakeFound = false;
        for (uint256 i = 0; i < _userStakes[user].length; i++) {
            StakeInfo storage stakeItem = _userStakes[user][i];
            // Compare validator strings and ensure stake is active
            if (stakeItem.unbondingAt == 0 && 
                stakeItem.amount > 0 && 
                keccak256(bytes(stakeItem.validator)) == keccak256(bytes(validator))) {
                
                // Update existing stake
                stakeItem.amount += amount;
                existingStakeFound = true;
                emit Staked(user, amount, validator, i);
                break;
            }
        }
        
        // If no existing stake found with this validator, create a new one
        if (!existingStakeFound) {
            // Add stake to user's stakes with validator information
            StakeInfo memory newStake = StakeInfo({
                amount: amount,
                stakedAt: block.timestamp,
                unbondingAt: 0,
                validator: validator
            });
            
            _userStakes[user].push(newStake);
            
            // Emit event with validator information
            uint256 stakeId = _userStakes[user].length - 1;
            emit Staked(user, amount, validator, stakeId);
        }
        
        _totalStakedByUser[user] += amount;
        
        // Set initial claim time if first stake
        if (_lastClaimTime[user] == 0) {
            _lastClaimTime[user] = block.timestamp;
        }
        
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
        returns (bytes memory requestId) 
    {
        require(amount > 0, "Amount must be > 0");
        require(_totalStakedByUser[user] >= amount, "Insufficient staked amount");
        
        // Check if user has a stake with this validator
        bool validatorStakeFound = false;
        uint256 validatorStakeTotal = 0;
        
        for (uint256 i = 0; i < _userStakes[user].length; i++) {
            StakeInfo storage stakeItem = _userStakes[user][i];
            if (stakeItem.unbondingAt == 0 && 
                stakeItem.amount > 0 && 
                keccak256(bytes(stakeItem.validator)) == keccak256(bytes(validator))) {
                validatorStakeFound = true;
                validatorStakeTotal += stakeItem.amount;
            }
        }
        
        require(validatorStakeFound, "No stake found for this validator");
        require(validatorStakeTotal >= amount, "Insufficient stake for this validator");
        
        // Calculate unlock time based on unbonding period
        uint256 unlockTime = block.timestamp + oracle.getUnbondingPeriod();
        
        // Create unstake request
        UnstakeRequest memory request = UnstakeRequest({
            user: user,
            amount: amount,
            validator: validator,
            timestamp: block.timestamp,
            claimed: false
        });
        
        // Store the request in the array
        _userUnstakeRequests[user].push(request);
        uint256 arrayIndex = _userUnstakeRequests[user].length - 1;
        
        // Generate a structured requestId as bytes
        // Format: [2 bytes: type][4 bytes: timestamp][20 bytes: user address][32 bytes: amount hash][4 bytes: sequence]
        
        // 1. Request type (0 = unstake) - 2 bytes
        bytes2 requestType = bytes2(uint16(0));
        
        // 2. Timestamp - 4 bytes
        bytes4 timestamp = bytes4(uint32(block.timestamp));
        
        // 3. User address - 20 bytes
        
        // 4. Hash of amount and validator - 32 bytes
        bytes32 amountValidatorHash = keccak256(abi.encodePacked(amount, validator));
        
        // 5. Sequence number - 4 bytes
        bytes4 sequence = bytes4(uint32(arrayIndex));
        
        // Combine all components
        requestId = abi.encodePacked(requestType, timestamp, user, amountValidatorHash, sequence);
        
        // Store the mapping from requestId hash to array index
        bytes32 requestIdHash = keccak256(requestId);
        _requestIdToIndex[user][requestIdHash] = arrayIndex;
        
        // Store the latest request ID for getLatestRequestId function
        _latestRequestId = requestId;
        
        // Increment the counter for future requests (for legacy support)
        _nextRequestId++;
        
        // Find stakes to mark as unbonding - prioritize stake with the requested validator
        uint256 remainingAmount = amount;
        
        // First, try to unstake from the specified validator
        for (uint256 i = 0; i < _userStakes[user].length && remainingAmount > 0; i++) {
            StakeInfo storage stakeItem = _userStakes[user][i];
            if (stakeItem.unbondingAt == 0 && 
                stakeItem.amount > 0 && 
                keccak256(bytes(stakeItem.validator)) == keccak256(bytes(validator))) {
                
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
                        unbondingAt: block.timestamp,
                        validator: stakeItem.validator // Copy the validator from the original stake
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
    function claimUnstake(address user, bytes calldata requestId) 
        external 
        override 
        onlyRole(STAKING_MANAGER_ROLE) 
        returns (uint256 amount) 
    {
        // Extract the array index from the requestId
        uint256 index;
        
        // Check if this is a bytes requestId or a legacy requestId (uint256 represented as bytes)
        if (requestId.length > 32) {
            // New format - get index from the requestId mapping
            bytes32 requestIdHash = keccak256(requestId);
            index = _requestIdToIndex[user][requestIdHash];
        } else {
            // Legacy format - parse as uint256 and extract index
            uint256 legacyId = abi.decode(requestId, (uint256));
            if (isStructuredRequestId(legacyId)) {
                // Extract the array index from the last 4 bytes
                index = getSequenceFromId(legacyId);
            } else {
                // Use the requestId directly as an index (very old legacy format)
                index = legacyId;
            }
        }
        
        // Validate the request exists
        require(index < _userUnstakeRequests[user].length, "Invalid request ID");
        UnstakeRequest storage request = _userUnstakeRequests[user][index];
        
        require(!request.claimed, "Already claimed");
        require(block.timestamp >= request.timestamp + oracle.getUnbondingPeriod(), "Still in unbonding period");
        
        amount = request.amount;
        request.claimed = true;
        
        // Claim any pending rewards first
        // We calculate pending rewards separately for unstaking
        uint256 pendingRewards = getUnclaimedRewards(user);
        if (pendingRewards > 0) {
            _claimRewards(user, pendingRewards);
        }
        
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
     * @param user The user claiming rewards
     * @param rewardAmount The amount of rewards to claim (determined by oracle)
     * @return amount The amount of rewards claimed
     */
    function claimRewards(address user, uint256 rewardAmount) 
        external 
        override 
        onlyRole(STAKING_MANAGER_ROLE) 
        nonReentrant 
        returns (uint256 amount) 
    {
        // The reward amount is now provided by the manager based on oracle data
        return _claimRewards(user, rewardAmount);
    }
    
    /**
     * @dev Internal function to claim staking rewards
     * @param user The user to claim rewards for
     * @param rewardAmount The amount of rewards to claim
     * @return amount The amount of rewards claimed
     */
    function _claimRewards(address user, uint256 rewardAmount) private returns (uint256 amount) {
        // Note: We are no longer using the internal calculation for rewards
        // Instead, the amount is passed from the manager which gets it from the oracle
        // The oracle's value is set by the backend system parsing Cosmos chain data
        
        // Update last claim time to now regardless of reward amount
        _lastClaimTime[user] = block.timestamp;
        
        // The amount is already determined by the manager based on oracle data
        // We just transfer the provided amount
        amount = rewardAmount;
        
        // This assumes the manager has already verified there are rewards to claim
        // and the contract has enough balance to cover them
        
        // Transfer rewards to the user via manager
        bool transferred = stakingToken.transfer(msg.sender, amount);
        require(transferred, "Transfer failed");
        
        emit RewardsClaimed(user, amount);
        
        return amount;
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
     * @return An array of StakeInfo structs with validator information
     */
    function getUserStakes(address user) 
        external 
        view 
        override 
        returns (StakeInfo[] memory) 
    {
        uint256 activeStakeCount = getActiveStakeCount(user);
        
        // Create an array with just the active stakes
        StakeInfo[] memory activeStakes = new StakeInfo[](activeStakeCount);
        uint256 currentIndex = 0;
        
        for (uint256 i = 0; i < _userStakes[user].length && currentIndex < activeStakeCount; i++) {
            if (_userStakes[user][i].unbondingAt == 0 && _userStakes[user][i].amount > 0) {
                activeStakes[currentIndex] = _userStakes[user][i];
                currentIndex++;
            }
        }
        
        return activeStakes;
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
     * @param newAmount The new minimum stake amount
     */
    function setMinStakeAmount(uint256 newAmount) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        minStakeAmount = newAmount;
        emit MinStakeAmountUpdated(newAmount);
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
     * @dev Extracts the request type from a structured request ID
     * @param requestId The structured request ID
     * @return The request type component (0 = unstake for this contract)
     */
    function getRequestTypeFromId(uint256 requestId) 
        public 
        pure 
        returns (uint16) 
    {
        return uint16(requestId >> 128);
    }
    
    /**
     * @dev Extracts the timestamp from a structured request ID
     * @param requestId The structured request ID
     * @return The timestamp component (seconds since Unix epoch)
     */
    function getTimestampFromId(uint256 requestId) 
        public 
        pure 
        returns (uint256) 
    {
        return uint256(uint32(requestId >> 96));
    }
    
    /**
     * @dev Extracts the sequence number (array index) from a structured request ID
     * @param requestId The structured request ID
     * @return The sequence number component
     */
    function getSequenceFromId(uint256 requestId) 
        public 
        pure 
        returns (uint256) 
    {
        return requestId & 0xFFFFFFFF;
    }
    
    /**
     * @dev Extracts the random component from a structured request ID
     * @param requestId The structured request ID
     * @return The random component derived from user and amount
     */
    function getRandomComponentFromId(uint256 requestId) 
        public 
        pure 
        returns (uint256) 
    {
        return (requestId >> 32) & 0xFFFFFFFFFFFFFFFF;
    }
    
    /**
     * @dev Checks if a requestId is in the new structured format
     * @param requestId The request ID to check
     * @return True if the requestId is in structured format, false if legacy
     */
    function isStructuredRequestId(uint256 requestId) 
        public 
        pure 
        returns (bool) 
    {
        return requestId >= 4294967296; // 2^32
    }
    
    /**
     * @dev Gets the count of active stakes for a user (not in unbonding)
     * @param user The user to get the count for
     * @return The count of active stakes
     */
    function getActiveStakeCount(address user) 
        public 
        view 
        returns (uint256) 
    {
        uint256 activeStakeCount = 0;
        for (uint256 i = 0; i < _userStakes[user].length; i++) {
            if (_userStakes[user][i].unbondingAt == 0 && _userStakes[user][i].amount > 0) {
                activeStakeCount++;
            }
        }
        return activeStakeCount;
    }
    
    /**
     * @dev Gets the amount staked with a specific validator by a user
     * @param user The user to get the stake for
     * @param validator The validator to get the stake for
     * @return The amount staked with the validator
     */
    function getValidatorStake(address user, string calldata validator) 
        external 
        view 
        override 
        returns (uint256) 
    {
        uint256 validatorStake = 0;
        
        for (uint256 i = 0; i < _userStakes[user].length; i++) {
            StakeInfo storage stakeItem = _userStakes[user][i];
            if (stakeItem.unbondingAt == 0 && 
                stakeItem.amount > 0 &&
                keccak256(bytes(stakeItem.validator)) == keccak256(bytes(validator))) {
                validatorStake += stakeItem.amount;
            }
        }
        
        return validatorStake;
    }
    
    /**
     * @dev Gets a specific unstake request without needing the user address
     * @param requestId The ID of the request
     * @return The UnstakeRequest struct
     */
    function getUnstakeRequest(bytes calldata requestId) 
        external 
        view 
        override 
        returns (UnstakeRequest memory) 
    {
        // In this implementation, we need to extract the user address from the requestId
        // This is a simplified implementation for compatibility
        
        // Check if this is likely a legacy format (uint256 as bytes)
        if (requestId.length <= 32) {
            // Legacy format - use a default user (msg.sender) as this is just for compatibility
            return this.getUnstakeRequest(msg.sender, requestId);
        }
        
        // For structured IDs, we extract the user from bytes
        // Since directly accessing calldata bytes is not allowed, we'll use a simpler approach
        // This is a fallback implementation that will work for compatibility
        // In a real implementation, you would need to properly decode the user from the requestId
        
        // For now, we'll return an empty struct if not found via the legacy method
        try this.getUnstakeRequest(msg.sender, requestId) returns (UnstakeRequest memory request) {
            return request;
        } catch {
            // Return an empty response - in production you would implement proper extraction
            return UnstakeRequest({
                user: address(0),
                amount: 0,
                validator: "",
                timestamp: 0,
                claimed: false
            });
        }
    }
    
    /**
     * @dev Gets a specific unstake request for a user (legacy function)
     * @param user The user to get the request for
     * @param requestId The ID of the request
     * @return The UnstakeRequest struct
     */
    function getUnstakeRequest(address user, bytes calldata requestId) 
        external 
        view 
        override 
        returns (UnstakeRequest memory) 
    {
        // Extract the array index from the requestId using similar logic to claimUnstake
        uint256 index;
        
        // Check if this is a bytes requestId or a legacy requestId (uint256 represented as bytes)
        if (requestId.length > 32) {
            // New format - get index from the requestId mapping
            bytes32 requestIdHash = keccak256(requestId);
            index = _requestIdToIndex[user][requestIdHash];
        } else {
            // Legacy format - parse as uint256 and extract index
            uint256 legacyId = abi.decode(requestId, (uint256));
            if (isStructuredRequestId(legacyId)) {
                // Extract the array index from the last 4 bytes
                index = getSequenceFromId(legacyId);
            } else {
                // Use the requestId directly as an index (very old legacy format)
                index = legacyId;
            }
        }
        
        require(index < _userUnstakeRequests[user].length, "Invalid request ID");
        return _userUnstakeRequests[user][index];
    }
    
    /**
     * @dev Gets the latest request ID that was created
     * @return The latest request ID (bytes)
     */
    function getLatestRequestId() external view override returns (bytes memory) {
        return _latestRequestId;
    }
    
    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap; // Adjusted for new mapping
} 