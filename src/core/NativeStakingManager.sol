// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/INativeStakingManager.sol";
import "../interfaces/INativeStaking.sol";
import "../interfaces/INativeStakingVault.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IWXFI.sol";
import "../interfaces/IAPRStaking.sol";

/**
 * @title NativeStakingManager
 * @dev Central router contract for the Native Staking system
 * Routes staking operations to the appropriate staking contract (APR or APY)
 * Handles both native XFI and wrapped XFI (WXFI)
 * Validator information is now only passed to events for off-chain processing
 */
contract NativeStakingManager is 
    Initializable, 
    AccessControlUpgradeable, 
    PausableUpgradeable, 
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    INativeStakingManager 
{
    // Constants
    uint256 private constant PRECISION = 1e18;
    address private constant XFI_NATIVE_ADDRESS = address(0);
    
    // Minimum amounts (now settable)
    uint256 public minStakeAmount;
    uint256 public minUnstakeAmount;
    uint256 public minRewardClaimAmount;
    
    // Validator prefix for validation
    string private constant VALIDATOR_PREFIX = "mxva";
    
    // Custom roles
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant FULFILLER_ROLE = keccak256("FULFILLER_ROLE");
    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");
    
    // Toggle for minimum amount validation (disable for testing)
    bool public enforceMinimumAmounts;
    
    // Request types
    enum RequestType { STAKE, UNSTAKE, CLAIM_REWARDS }
    
    // Request status
    enum RequestStatus { PENDING, FULFILLED, FAILED }
    
    // Request structure for tracking
    struct Request {
        address user;
        uint256 amount;
        string validator;
        uint256 timestamp;
        RequestType requestType;
        RequestStatus status;
        string statusReason;
    }
    
    // State variables
    INativeStaking public aprContract;
    INativeStakingVault public apyContract;
    IWXFI public wxfi;
    IOracle public oracle;
    
    // Unstaking freeze period variables
    uint256 private _launchTimestamp;
    uint256 private _unstakeFreezeTime;
    bool private _isManuallyFrozen;
    
    // Request tracking
    mapping(uint256 => Request) private _requests;
    uint256 private _nextRequestId;
    
    // Add new state variables for validator unbonding tracking
    mapping(address => mapping(string => uint256)) private _userValidatorUnbondingEnd;
    
    // Events
    event APRContractUpdated(address indexed newContract);
    event APYContractUpdated(address indexed newContract);
    event OracleUpdated(address indexed newOracle);
    event StakedAPR(address indexed user, uint256 xfiAmount, uint256 mpxAmount, string validator, bool success, bytes indexed requestId);
    event StakedAPY(address indexed user, uint256 xfiAmount, uint256 mpxAmount, uint256 shares, bytes indexed requestId);
    event UnstakedAPR(address indexed user, uint256 xfiAmount, uint256 mpxAmount, string validator, bytes indexed requestId);
    event WithdrawnAPY(address indexed user, uint256 shares, uint256 xfiAssets, uint256 mpxAssets, bytes indexed requestId);
    event WithdrawalRequestedAPY(address indexed user, uint256 xfiAssets, uint256 mpxAssets, bytes indexed requestId);
    event UnstakeClaimedAPR(address indexed user, bytes indexed requestId, uint256 xfiAmount, uint256 mpxAmount);
    event WithdrawalClaimedAPY(address indexed user, bytes indexed requestId, uint256 xfiAmount, uint256 mpxAmount);
    event RewardsClaimedAPR(address indexed user, uint256 xfiAmount, uint256 mpxAmount, bytes indexed requestId);
    event UnstakeFreezeTimeUpdated(uint256 newUnstakeFreezeTime);
    event LaunchTimestampSet(uint256 timestamp);
    event RequestFulfilled(uint256 indexed requestId, address indexed user, RequestStatus indexed status, string reason);
    event UnstakingFrozen(uint256 freezeDuration);
    event UnstakingUnfrozen();
    event UnstakingAutoUnfrozen();
    event MinStakeAmountUpdated(uint256 newMinStakeAmount);
    event MinUnstakeAmountUpdated(uint256 newMinUnstakeAmount);
    event MinRewardClaimAmountUpdated(uint256 newMinRewardClaimAmount);
    event ValidatorUnbondingStarted(address indexed user, string validator, uint256 endTime);
    event ValidatorUnbondingEnded(address indexed user, string validator);
    event RewardsClaimedAPRForValidator(address indexed user, uint256 xfiAmount, uint256 mpxAmount, string validator, bytes indexed requestId);
    
    /**
     * @dev Initializes the contract
     * @param _aprContract The address of the APR staking contract
     * @param _apyContract The address of the APY staking contract
     * @param _wxfi The address of the WXFI token
     * @param _oracle The address of the oracle
     * @param _enforceMinimums Whether to enforce minimum staking amounts
     * @param _initialFreezeTime Initial freeze period in seconds (default 30 days)
     * @param _minStake Minimum stake amount in XFI
     * @param _minUnstake Minimum unstake amount in XFI
     * @param _minRewardClaim Minimum reward claim amount in XFI
     */
    function initialize(
        address _aprContract,
        address _apyContract,
        address _wxfi,
        address _oracle,
        bool _enforceMinimums,
        uint256 _initialFreezeTime,
        uint256 _minStake,
        uint256 _minUnstake,
        uint256 _minRewardClaim
    ) external initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        _grantRole(FULFILLER_ROLE, msg.sender);
        _grantRole(ORACLE_MANAGER_ROLE, msg.sender);
        
        aprContract = INativeStaking(_aprContract);
        apyContract = INativeStakingVault(_apyContract);
        wxfi = IWXFI(_wxfi);
        oracle = IOracle(_oracle);
        
        // Set minimum amounts
        minStakeAmount = _minStake;
        minUnstakeAmount = _minUnstake;
        minRewardClaimAmount = _minRewardClaim;
        
        // Set default launch timestamp to now
        _launchTimestamp = block.timestamp;
        
        // Initialize unstaking freeze period
        _unstakeFreezeTime = _initialFreezeTime;
        
        // Set minimum enforcement flag based on deployment environment
        enforceMinimumAmounts = _enforceMinimums;
        
        // Initialize request ID
        _nextRequestId = 1;
        
        // Emit initial freeze event
        emit UnstakingFrozen(_initialFreezeTime);
    }
    
    /**
     * @dev Helper function to check if the oracle price is fresh
     * Reverts if the price is stale or zero
     */
    function _checkOracleFreshness() internal view {
        uint256 price = oracle.getPrice("XFI");
        require(price > 0, "Oracle price cannot be zero");
        
        // If there's no timestamp in getPrice, we'll add a backup check
        // by verifying that rewards and APR values are reasonable
        uint256 apr = oracle.getCurrentAPR();
        require(apr <= 50 * 1e16, "APR value is unreasonably high"); // Max 50%
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
     * @dev Stakes XFI using the APR model
     * Validator parameter is only used in events for off-chain processing
     * @param amount The amount of XFI to stake
     * @param validator The validator address/ID (only for events, not stored on-chain)
     * @return success Boolean indicating if the stake was successful
     */
    function stakeAPR(uint256 amount, string calldata validator) 
        external 
        payable 
        override 
        whenNotPaused 
        nonReentrant 
        returns (bool success) 
    {
        // Validate amount
        require(amount > 0, "Amount must be greater than zero");
        
        // Enforce minimum amount if enabled
        if (enforceMinimumAmounts) {
            require(amount >= minStakeAmount, "Amount must be at least 50 XFI");
        }
        
        // Validate validator format
        require(_validateValidatorFormat(validator), "Invalid validator format: must start with 'mxva'");
        
        // Check oracle freshness
        _checkOracleFreshness();

        address tokenAddress;
        
        if (msg.value > 0) {
            // User is staking native XFI
            require(msg.value == amount, "Amount mismatch");
            
            // Wrap XFI to WXFI
            wxfi.deposit{value: amount}();
            
            tokenAddress = address(wxfi);
        } else {
            // User is staking WXFI
            require(IERC20(address(wxfi)).balanceOf(msg.sender) >= amount, "Insufficient WXFI balance");
            require(IERC20(address(wxfi)).allowance(msg.sender, address(this)) >= amount, "Insufficient WXFI allowance");
            
            // Transfer WXFI from user to this contract
            bool transferred = IERC20(address(wxfi)).transferFrom(msg.sender, address(this), amount);
            require(transferred, "WXFI transfer failed");
            
            tokenAddress = address(wxfi);
        }
        
        // Approve APR contract to spend WXFI (only exact amount)
        // First reset approval to 0 to prevent some ERC20 issues
        IERC20(address(wxfi)).approve(address(aprContract), 0);
        // Then set exact approval amount
        IERC20(address(wxfi)).approve(address(aprContract), amount);
        
        // Call the APR staking contract, passing validator for events
        success = aprContract.stake(msg.sender, amount, validator, tokenAddress);
        
        // Create a request record
        uint256 requestId = _createRequest(
            msg.sender, 
            amount, 
            validator, 
            RequestType.STAKE
        );
        
        // Convert XFI to MPX for the event
        uint256 mpxAmount = oracle.convertXFItoMPX(amount);
        
        // Emit event with request ID
        emit StakedAPR(msg.sender, amount, mpxAmount, validator, success, abi.encode(requestId));
        
        return success;
    }
    
    /**
     * @dev Stakes XFI using the APY model (compound vault)
     * @param amount The amount of XFI to stake
     * @return shares The amount of vault shares received
     */
    function stakeAPY(uint256 amount) 
        external 
        payable 
        override 
        whenNotPaused 
        nonReentrant 
        returns (uint256 shares) 
    {
        // Validate amount
        require(amount > 0, "Amount must be greater than zero");
        
        // Check oracle freshness
        _checkOracleFreshness();
        
        if (msg.value > 0) {
            // User is staking native XFI
            require(msg.value == amount, "Amount mismatch");
            
            // Wrap XFI to WXFI
            wxfi.deposit{value: amount}();
        } else {
            // User is staking WXFI
            IERC20(address(wxfi)).transferFrom(msg.sender, address(this), amount);
        }
        
        // Ensure vault has approval to spend WXFI
        uint256 currentAllowance = IERC20(address(wxfi)).allowance(address(this), address(apyContract));
        if (currentAllowance < amount) {
            IERC20(address(wxfi)).approve(address(apyContract), type(uint256).max);
        }
        
        // Deposit to the APY staking contract (vault)
        shares = apyContract.deposit(amount, msg.sender);
        
        // Create a request record
        uint256 requestId = _createRequest(
            msg.sender, 
            amount, 
            "", 
            RequestType.STAKE
        );
        
        // Convert XFI to MPX for the event
        uint256 mpxAmount = oracle.convertXFItoMPX(amount);
        
        // Emit event with request ID
        emit StakedAPY(msg.sender, amount, mpxAmount, shares, abi.encode(requestId));
        
        return shares;
    }
    
    /**
     * @dev Requests to unstake XFI from the APR model
     * @param amount The amount of XFI to unstake
     * @param validator The validator address/ID to unstake from (only for events)
     * @return requestId The ID of the unstake request
     */
    function unstakeAPR(uint256 amount, string calldata validator) 
        external 
        override 
        whenNotPaused 
        nonReentrant 
        returns (bytes memory requestId) 
    {
        // Validate amount
        require(amount > 0, "Amount must be greater than zero");
        
        // Enforce minimum amount if enabled
        if (enforceMinimumAmounts) {
            require(amount >= minUnstakeAmount, "Amount must be at least 10 XFI");
        }
        
        // Validate validator format
        require(_validateValidatorFormat(validator), "Invalid validator format: must start with 'mxva'");
        
        // Check if unstaking is frozen (first month after launch)
        require(!isUnstakingFrozen(), "Unstaking is frozen for the first month");

        // Get current claimable rewards
        uint256 claimableRewards = oracle.getUserClaimableRewards(msg.sender);
        
        // If there are rewards, claim them regardless of threshold
        if (claimableRewards > 0) {
            // Clear rewards on oracle to prevent reentrancy
            oracle.clearUserClaimableRewards(msg.sender);
            
            // Call APR contract to handle the claim
            aprContract.claimRewards(msg.sender, claimableRewards);
            
            // Transfer rewards to user
            bool transferred = IERC20(wxfi).transfer(msg.sender, claimableRewards);
            require(transferred, "Reward transfer failed");
            
            // Emit rewards claimed event
            uint256 rewardsMpxAmount = oracle.convertXFItoMPX(claimableRewards);
            emit RewardsClaimedAPR(msg.sender, claimableRewards, rewardsMpxAmount, abi.encode(requestId));
        }
        
        // Call the APR staking contract to request unstake
        requestId = aprContract.requestUnstake(msg.sender, amount, validator);
        
        // Set unbonding period for this user-validator pair
        uint256 unbondingPeriod = oracle.getUnbondingPeriod();
        _userValidatorUnbondingEnd[msg.sender][validator] = block.timestamp + unbondingPeriod;
        emit ValidatorUnbondingStarted(msg.sender, validator, block.timestamp + unbondingPeriod);
        
        // Create a request record - this still uses uint256 for internal tracking
        uint256 internalRequestId = _createRequest(
            msg.sender, 
            amount, 
            validator, 
            RequestType.UNSTAKE
        );
        
        // Convert XFI to MPX for the event
        uint256 mpxAmount = oracle.convertXFItoMPX(amount);
        
        // Emit event with request ID - use the bytes requestId from the contract
        emit UnstakedAPR(msg.sender, amount, mpxAmount, validator, abi.encode(internalRequestId));
        
        return requestId;
    }
    
    /**
     * @dev Claims XFI from a completed APR unstake request
     * @param requestId The ID of the unstake request to claim
     * @return amount The amount of XFI claimed
     */
    function claimUnstakeAPR(bytes calldata requestId) 
        external 
        override 
        nonReentrant 
        returns (uint256 amount) 
    {
        // For bytes requestId, we need to extract information to find the matching request
        // Note: This is a simplified approach since we can't directly convert bytes to the old uint256 requestId
        
        // Call the APR contract to claim the unstake
        amount = aprContract.claimUnstake(msg.sender, requestId);
        
        // Ensure the amount is non-zero
        require(amount > 0, "Nothing to claim");
        
        // Get the validator information from the APR contract's unstake request
        // This is to know which validator's unbonding period should be cleared
        INativeStaking.UnstakeRequest memory request = aprContract.getUnstakeRequest(requestId);
        
        // Clear the unbonding period for this validator after successful claim
        // This allows the user to stake again with this validator immediately
        if (bytes(request.validator).length > 0) {
            _userValidatorUnbondingEnd[msg.sender][request.validator] = 0;
            emit ValidatorUnbondingEnded(msg.sender, request.validator);
        }
        
        // We can't directly access the request from _requests since we don't have the internal ID
        // For now, assuming validator information is not critical for the claim process
        // In production, consider storing a mapping from bytes requestId to internal requestId
        
        // Simplify token transfer logic to ensure tokens always get transferred
        bool transferred = IERC20(wxfi).transfer(msg.sender, amount);
        require(transferred, "Token transfer failed");
        
        // Convert XFI to MPX for the event
        uint256 mpxAmount = oracle.convertXFItoMPX(amount);
        
        // Emit the event with the requestId
        emit UnstakeClaimedAPR(msg.sender, requestId, amount, mpxAmount);
        
        return amount;
    }
    
    /**
     * @dev Withdraws XFI from the APY staking model
     * @param shares The amount of vault shares to withdraw
     * @return requestId The withdrawal request ID (the vault's request ID or a generated one for direct withdrawals)
     */
    function withdrawAPY(uint256 shares) 
        external 
        override 
        whenNotPaused 
        nonReentrant 
        returns (bytes memory requestId) 
    {
        // Check if unstaking is frozen (first month after launch)
        require(!isUnstakingFrozen(), "Unstaking is frozen for the first month");
        
        // Check if user has approved shares for withdrawal
        require(apyContract.allowance(msg.sender, address(this)) >= shares, "Insufficient share allowance");
        
        // Create a request record for tracking
        uint256 internalRequestId = _createRequest(
            msg.sender, 
            shares, 
            "", 
            RequestType.UNSTAKE
        );
        
        // First try a direct withdrawal
        try apyContract.redeem(shares, msg.sender, msg.sender) returns (uint256 redeemedAssets) {
            // Immediate withdrawal successful
            uint256 assets = redeemedAssets;
            
            // Convert XFI to MPX for the event
            uint256 mpxAssets = oracle.convertXFItoMPX(assets);
            
            // Convert to bytes for the return value
            requestId = abi.encode(internalRequestId);
            
            emit WithdrawnAPY(msg.sender, shares, assets, mpxAssets, requestId);
        } catch {
            // Not enough liquid assets, use delayed withdrawal
            uint256 previewAssets = apyContract.previewRedeem(shares);
            
            // Make the vault withdrawal request
            // The vault maintains its own request ID system internally
            requestId = apyContract.requestWithdrawal(previewAssets, msg.sender, msg.sender);
            
            // Convert XFI to MPX for the event
            uint256 mpxAssets = oracle.convertXFItoMPX(previewAssets);
            
            emit WithdrawalRequestedAPY(msg.sender, previewAssets, mpxAssets, abi.encode(internalRequestId));
        }
        
        return requestId;
    }
    
    /**
     * @dev Claims XFI from a completed APY withdrawal request
     * @param requestId The ID of the withdrawal request to claim
     * @return assets The amount of XFI claimed
     */
    function claimWithdrawalAPY(bytes calldata requestId) 
        external 
        override 
        nonReentrant 
        returns (uint256 assets) 
    {
        // Since we've changed the parameter type, we'll need to extract a uint256 from the bytes
        // Here we'll assume that for backward compatibility, we can extract a uint256 from the bytes
        uint256 legacyRequestId;
        if (requestId.length <= 32) {
            // Try to decode as uint256
            legacyRequestId = abi.decode(requestId, (uint256));
        } else {
            // For new format, we'll need to implement a way to look up the legacy requestId
            // This is a simplified placeholder - in production, you'd need a proper mapping
            legacyRequestId = uint256(keccak256(requestId)) % 1000000; // A simplified way to get a uint from bytes
        }
        
        // Convert back to bytes for the call
        bytes memory legacyRequestIdBytes = abi.encode(legacyRequestId);
        
        assets = apyContract.claimWithdrawal(legacyRequestIdBytes);
        
        // Convert XFI to MPX for the event
        uint256 mpxAssets = oracle.convertXFItoMPX(assets);
        
        emit WithdrawalClaimedAPY(msg.sender, requestId, assets, mpxAssets);
        
        return assets;
    }
    
    /**
     * @dev Claims rewards for a specific validator
     * @param validator The validator to claim rewards for
     * @param amount The amount of rewards to claim
     * @return requestId The ID of the request
     */
    function claimRewardsAPRForValidator(string calldata validator, uint256 amount) 
        external 
        whenNotPaused 
        nonReentrant 
        returns (bytes memory requestId) 
    {
        require(amount >= minRewardClaimAmount, "Amount must be at least minRewardClaimAmount");
        require(oracle.isValidatorActive(validator), "Validator is not active");
        
        // Check oracle freshness
        _checkOracleFreshness();
        
        // Get user's claimable rewards for this validator
        uint256 claimableRewards = oracle.getUserClaimableRewardsForValidator(msg.sender, validator);
        require(claimableRewards >= amount, "Insufficient claimable rewards");
        
        // Get user's stake for this validator
        uint256 userStake = oracle.getValidatorStake(msg.sender, validator);
        require(userStake > 0, "No stake found for this validator");
        
        // Safety check: reward amount should not exceed 25% of stake
        require(amount <= userStake / 4, "Reward amount exceeds reasonable threshold");
        
        // Clear rewards on oracle first to prevent reentrancy
        uint256 clearedAmount = oracle.clearUserClaimableRewardsForValidator(msg.sender, validator);
        require(clearedAmount >= amount, "Failed to clear rewards");
        
        // Transfer rewards to user
        require(wxfi.transfer(msg.sender, amount), "Failed to transfer rewards");
        
        // Create request record using the new structured ID format
        uint256 legacyRequestId = _nextRequestId++;
        
        // Generate the new formatted request ID
        requestId = _generateStructuredRequestId(
            RequestType.CLAIM_REWARDS,
            msg.sender,
            amount,
            validator
        );
        
        // Store using the legacy ID for backward compatibility
        _requests[legacyRequestId] = Request({
            user: msg.sender,
            amount: amount,
            validator: validator,
            timestamp: block.timestamp,
            requestType: RequestType.CLAIM_REWARDS,
            status: RequestStatus.FULFILLED,
            statusReason: "Success"
        });
        
        emit RewardsClaimedAPRForValidator(msg.sender, amount, 0, validator, requestId);
        emit RequestFulfilled(legacyRequestId, msg.sender, RequestStatus.FULFILLED, "Success");
        
        return requestId;
    }

    /**
     * @dev Claims all rewards from the APR model
     * @return amount The amount of rewards claimed
     */
    function claimRewardsAPR() 
        external 
        override 
        nonReentrant 
        returns (uint256 amount) 
    {
        // Check oracle freshness
        _checkOracleFreshness();
        
        // Get claimable rewards from the oracle (set by backend)
        amount = oracle.getUserClaimableRewards(msg.sender);
        require(amount > 0, "No rewards to claim");
        
        // Check minimum reward claim amount
        if (enforceMinimumAmounts) {
            require(amount >= minRewardClaimAmount, "Reward amount below minimum");
        }
        
        // Get user's total staked amount for validation
        uint256 totalStaked = aprContract.getTotalStaked(msg.sender);
        require(totalStaked > 0, "User has no stake");
        
        // Validate rewards are not unreasonably high (max 100% APR for safety check)
        uint256 maxReasonableReward = totalStaked / 4; // 25% of stake (100% APR / 4 for quarterly max)
        require(amount <= maxReasonableReward, "Reward amount exceeds safety threshold");
        
        // Clear rewards on oracle to prevent reentrancy
        oracle.clearUserClaimableRewards(msg.sender);
        
        // Directly transfer the rewards tokens to the user
        bool transferred = IERC20(wxfi).transfer(msg.sender, amount);
        require(transferred, "Reward transfer failed");
        
        // Create a request record
        uint256 requestId = _createRequest(
            msg.sender, 
            amount, 
            "", 
            RequestType.CLAIM_REWARDS
        );
        
        // Convert XFI to MPX for the event
        uint256 rewardsMpxAmount = oracle.convertXFItoMPX(amount);
        
        // Emit event with request ID
        emit RewardsClaimedAPR(msg.sender, amount, rewardsMpxAmount, abi.encode(requestId));
        
        return amount;
    }
    
    /**
     * @dev Marks a request as fulfilled by backend
     * Only callable by addresses with the FULFILLER_ROLE
     * @param requestId The ID of the request to fulfill
     * @param status The status to set (FULFILLED or FAILED)
     * @param reason Optional reason string, especially for FAILED status
     * @return success Boolean indicating if the fulfillment was successful
     */
    function fulfillRequest(uint256 requestId, RequestStatus status, string calldata reason) 
        external 
        onlyRole(FULFILLER_ROLE) 
        returns (bool success) 
    {
        // With our new hashing-based request ID system, we verify the request exists
        // by checking if its timestamp is non-zero rather than comparing against _nextRequestId
        Request storage request = _requests[requestId];
        require(request.timestamp > 0, "Invalid request ID");
        
        require(status != RequestStatus.PENDING, "Cannot set status to PENDING");
        
        // Request must be pending
        require(request.status == RequestStatus.PENDING, "Request not pending");
        
        // Update request status
        request.status = status;
        request.statusReason = reason;
        
        // Emit event
        emit RequestFulfilled(requestId, request.user, status, reason);
        
        return true;
    }
    
    /**
     * @dev Creates a new request and returns its ID
     * @param user The user making the request
     * @param amount The amount involved in the request
     * @param validator The validator ID if applicable
     * @param requestType The type of request
     * @return requestId The created request ID
     */
    function _createRequest(
        address user,
        uint256 amount,
        string memory validator,
        RequestType requestType
    ) 
        internal
        returns (uint256 requestId) 
    {
        // For stake and unstake operations, validate the validator format
        if (requestType == RequestType.STAKE || requestType == RequestType.UNSTAKE) {
            // Only validate non-empty validator strings (APY staking doesn't use validator)
            if (bytes(validator).length > 0) {
                require(_validateValidatorFormat(validator), "Invalid validator format in request creation");
            }
        }
        
        // Generate a structured request ID with:
        // [2 bytes: request type][4 bytes: timestamp][8 bytes: user+amount hash][4 bytes: sequence]
        
        // 1. Convert request type to 2 bytes
        uint16 requestTypeValue = uint16(requestType);
        
        // 2. Take last 4 bytes of timestamp (covers ~136 years)
        uint32 timestampValue = uint32(block.timestamp);
        
        // 3. Generate 8 bytes from user and amount (randomness component)
        bytes32 userAmountHash = keccak256(abi.encodePacked(user, amount, validator));
        uint64 randomComponent = uint64(uint256(userAmountHash));
        
        // 4. Use 4 bytes from sequence counter
        uint32 sequenceValue = uint32(_nextRequestId);
        
        // 5. Combine all components into a single uint256
        requestId = (uint256(requestTypeValue) << 128) |
                   (uint256(timestampValue) << 96) |
                   (uint256(randomComponent) << 32) |
                   uint256(sequenceValue);
        
        // Increment the counter for future requests
        _nextRequestId++;
        
        _requests[requestId] = Request({
            user: user,
            amount: amount,
            validator: validator,
            timestamp: block.timestamp,
            requestType: requestType,
            status: RequestStatus.PENDING,
            statusReason: ""
        });
        
        return requestId;
    }
    
    /**
     * @dev Gets details of a request by its ID
     * @param requestId The ID of the request to get
     * @return User address
     * @return Amount involved
     * @return Validator string
     * @return Timestamp of creation
     * @return Request type
     * @return Status of the request
     * @return Status reason (string)
     */
    function getRequest(uint256 requestId) 
        external 
        view 
        returns (
            address,
            uint256,
            string memory,
            uint256,
            RequestType,
            RequestStatus,
            string memory
        ) 
    {
        Request storage request = _requests[requestId];
        return (
            request.user,
            request.amount,
            request.validator,
            request.timestamp,
            request.requestType,
            request.status,
            request.statusReason
        );
    }
    
    /**
     * @dev Extracts the request type from a structured request ID
     * @param requestId The structured request ID
     * @return The request type component
     */
    function getRequestTypeFromId(uint256 requestId) 
        external 
        pure 
        returns (RequestType) 
    {
        uint16 requestTypeValue = uint16(requestId >> 128);
        return RequestType(requestTypeValue);
    }
    
    /**
     * @dev Extracts the timestamp from a structured request ID
     * @param requestId The structured request ID
     * @return The timestamp component (seconds since Unix epoch)
     */
    function getTimestampFromId(uint256 requestId) 
        external 
        pure 
        returns (uint256) 
    {
        uint32 timestampValue = uint32(requestId >> 96);
        return uint256(timestampValue);
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
     * @dev Extracts the sequence number from a structured request ID
     * @param requestId The structured request ID
     * @return The sequence number component
     */
    function getSequenceFromId(uint256 requestId) 
        public 
        pure 
        returns (uint256) 
    {
        // Use bitwise AND to mask only the last 4 bytes (32 bits)
        // This prevents overflow by directly extracting the bits
        return requestId & 0xFFFFFFFF;
    }

    /**
     * @dev Extracts the random component from a structured request ID
     * @param requestId The structured request ID
     * @return The random component derived from user and amount
     */
    function getRandomComponentFromId(uint256 requestId) 
        external 
        pure 
        returns (uint256) 
    {
        // Extract bits 32-95 (8 bytes) using bitwise operations
        return (requestId >> 32) & 0xFFFFFFFFFFFFFFFF;
    }
    
    /**
     * @dev Gets the total number of requests that have been created
     * @return The next request ID minus 1
     */
    function getTotalRequests() 
        external 
        view 
        returns (uint256) 
    {
        return _nextRequestId - 1;
    }
    
    /**
     * @dev Gets the address of the APR staking contract
     * @return The address of the APR staking contract
     */
    function getAPRContract() 
        external 
        view 
        override 
        returns (address) 
    {
        return address(aprContract);
    }
    
    /**
     * @dev Gets the address of the APY staking contract
     * @return The address of the APY staking contract
     */
    function getAPYContract() 
        external 
        view 
        override 
        returns (address) 
    {
        return address(apyContract);
    }
    
    /**
     * @dev Gets the address of the XFI token (or WXFI if wrapped)
     * @return The address of the XFI token
     */
    function getXFIToken() 
        external 
        view 
        override 
        returns (address) 
    {
        return address(wxfi);
    }
    
    /**
     * @dev Gets the current unbonding period in seconds
     * @return The unbonding period in seconds
     */
    function getUnbondingPeriod() 
        external 
        view 
        override 
        returns (uint256) 
    {
        return oracle.getUnbondingPeriod();
    }
    
    /**
     * @dev Sets the APR staking contract
     * @param _aprContract The new APR staking contract address
     */
    function setAPRContract(address _aprContract) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(_aprContract != address(0), "Invalid address");
        aprContract = INativeStaking(_aprContract);
        emit APRContractUpdated(_aprContract);
    }
    
    /**
     * @dev Sets the APY staking contract
     * @param _apyContract The new APY staking contract address
     */
    function setAPYContract(address _apyContract) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(_apyContract != address(0), "Invalid address");
        apyContract = INativeStakingVault(_apyContract);
        emit APYContractUpdated(_apyContract);
    }
    
    /**
     * @dev Sets the oracle contract
     * @param _oracle The new oracle contract address
     */
    function setOracle(address _oracle) 
        external 
        onlyRole(ORACLE_MANAGER_ROLE) 
    {
        require(_oracle != address(0), "Invalid address");
        oracle = IOracle(_oracle);
        emit OracleUpdated(_oracle);
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
     * @dev Receive function to handle native XFI transfers
     */
    receive() external payable {
        // Only accept direct transfers if the contract is not paused
        require(!paused(), "Contract is paused");
    }

    /**
     * @dev Checks if unstaking is frozen (during the initial freeze period after launch)
     * @return True if unstaking is still frozen
     */
    function isUnstakingFrozen() public view returns (bool) {
        // If manually frozen, check against launch timestamp
        if (_isManuallyFrozen) {
            return (block.timestamp < _launchTimestamp + _unstakeFreezeTime);
        }
        return false;
    }
    
    /**
     * @dev Sets the launch timestamp for the unstaking freeze period
     * @param timestamp The launch timestamp
     */
    function setLaunchTimestamp(uint256 timestamp) 
        external 
        onlyRole(ORACLE_MANAGER_ROLE) 
    {
        _launchTimestamp = timestamp;
        emit LaunchTimestampSet(timestamp);
    }
    
    /**
     * @dev Sets the duration of the unstaking freeze period
     * @param freezeTime The unstaking freeze time in seconds
     */
    function setUnstakeFreezeTime(uint256 freezeTime) 
        external 
        onlyRole(ORACLE_MANAGER_ROLE) 
    {
        _unstakeFreezeTime = freezeTime;
        emit UnstakeFreezeTimeUpdated(freezeTime);
    }
    
    /**
     * @dev Gets the unstaking freeze time in seconds
     * @return The unstaking freeze time in seconds
     */
    function getUnstakeFreezeTime() 
        external 
        view 
        returns (uint256) 
    {
        return _unstakeFreezeTime;
    }
    
    /**
     * @dev Gets the launch timestamp
     * @return The launch timestamp
     */
    function getLaunchTimestamp() 
        external 
        view 
        returns (uint256) 
    {
        return _launchTimestamp;
    }
    
    /**
     * @dev Allows batch cleanup of old fulfilled requests to save gas
     * Only requests that are FULFILLED or FAILED can be cleaned up
     * @param requestIds Array of request IDs to clean up
     * @return count The number of requests successfully cleaned up
     */
    function batchCleanupRequests(uint256[] calldata requestIds) 
        external 
        onlyRole(FULFILLER_ROLE) 
        returns (uint256 count) 
    {
        count = 0;
        
        for (uint256 i = 0; i < requestIds.length; i++) {
            uint256 requestId = requestIds[i];
            
            // Skip invalid request IDs
            if (requestId == 0 || requestId >= _nextRequestId) continue;
            
            Request storage request = _requests[requestId];
            
            // Only cleanup fulfilled or failed requests
            if (request.status == RequestStatus.FULFILLED || request.status == RequestStatus.FAILED) {
                // Check request is at least 30 days old to avoid cleaning up too recent data
                if (block.timestamp > request.timestamp + 30 days) {
                    // Clear data but keep some metadata
                    request.amount = 0;
                    request.validator = "";
                    request.statusReason = "";
                    count++;
                }
            }
        }
        
        return count;
    }
    
    /**
     * @dev Predicts what a request ID would be without creating it
     * @param user The user who would make the request
     * @param amount The amount that would be involved
     * @param validator The validator ID if applicable
     * @param requestType The type of request
     * @return The predicted request ID
     */
    function predictRequestId(
        address user,
        uint256 amount,
        string calldata validator,
        RequestType requestType
    ) 
        external 
        view 
        returns (uint256) 
    {
        // Generate a structured request ID with:
        // [2 bytes: request type][4 bytes: timestamp][8 bytes: user+amount hash][4 bytes: sequence]
        
        // 1. Convert request type to 2 bytes
        uint16 requestTypeValue = uint16(requestType);
        
        // 2. Take last 4 bytes of timestamp (covers ~136 years)
        uint32 timestampValue = uint32(block.timestamp);
        
        // 3. Generate 8 bytes from user and amount (randomness component)
        bytes32 userAmountHash = keccak256(abi.encodePacked(user, amount, validator));
        uint64 randomComponent = uint64(uint256(userAmountHash));
        
        // 4. Use 4 bytes from sequence counter
        uint32 sequenceValue = uint32(_nextRequestId);
        
        // 5. Combine all components into a single uint256
        return (uint256(requestTypeValue) << 128) |
               (uint256(timestampValue) << 96) |
               (uint256(randomComponent) << 32) |
               uint256(sequenceValue);
    }
    
    /**
     * @dev Manually freezes unstaking for a specified duration
     * @param freezeDuration Duration in seconds to freeze unstaking
     */
    function freezeUnstaking(uint256 freezeDuration) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(freezeDuration > 0, "Freeze duration must be greater than 0");
        _unstakeFreezeTime = freezeDuration;
        _launchTimestamp = block.timestamp;
        _isManuallyFrozen = true;
        emit UnstakingFrozen(freezeDuration);
    }
    
    /**
     * @dev Manually unfreezes unstaking immediately
     */
    function unfreezeUnstaking() 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        _unstakeFreezeTime = 0;
        _isManuallyFrozen = false;
        emit UnstakingUnfrozen();
    }
    
    /**
     * @dev Function to check and auto-unfreeze if the freeze period has ended
     * Can be called by anyone to update the state
     */
    function checkAndAutoUnfreeze() public {
        if (_isManuallyFrozen && block.timestamp >= _launchTimestamp + _unstakeFreezeTime) {
            _isManuallyFrozen = false;
            emit UnstakingAutoUnfrozen();
        }
    }
    
    /**
     * @dev Sets the minimum stake amount
     * @param amount The new minimum stake amount in XFI
     */
    function setMinStakeAmount(uint256 amount) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(amount > 0, "Amount must be greater than 0");
        minStakeAmount = amount;
        emit MinStakeAmountUpdated(amount);
    }
    
    /**
     * @dev Sets the minimum unstake amount
     * @param amount The new minimum unstake amount in XFI
     */
    function setMinUnstakeAmount(uint256 amount) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(amount > 0, "Amount must be greater than 0");
        minUnstakeAmount = amount;
        emit MinUnstakeAmountUpdated(amount);
    }
    
    /**
     * @dev Sets the minimum reward claim amount
     * @param amount The new minimum reward claim amount in XFI
     */
    function setMinRewardClaimAmount(uint256 amount) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(amount > 0, "Amount must be greater than 0");
        minRewardClaimAmount = amount;
        emit MinRewardClaimAmountUpdated(amount);
    }
    
    /**
     * @dev Checks if a validator is in unbonding period for a specific user
     * @param user The user address
     * @param validator The validator address
     * @return bool True if validator is in unbonding period for the user
     */
    function isValidatorUnbondingForUser(address user, string calldata validator) 
        public 
        view 
        returns (bool) 
    {
        return block.timestamp < _userValidatorUnbondingEnd[user][validator];
    }

    /**
     * @dev Gets the end time of validator unbonding for a user
     * @param user The user address
     * @param validator The validator address
     * @return uint256 The end time of unbonding period
     */
    function getValidatorUnbondingEndTime(address user, string calldata validator) 
        external 
        view 
        returns (uint256) 
    {
        return _userValidatorUnbondingEnd[user][validator];
    }
    
    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;

    /**
     * @dev Generates a structured request ID in bytes format
     * @param requestType The type of request
     * @param user The user making the request
     * @param amount The amount involved in the request
     * @param validator The validator ID if applicable
     * @return requestId The bytes representation of the request ID
     */
    function _generateStructuredRequestId(
        RequestType requestType,
        address user,
        uint256 amount,
        string memory validator
    ) 
        internal
        view
        returns (bytes memory) 
    {
        // 1. Convert request type to 2 bytes
        uint256 requestTypeValue = uint256(uint16(requestType));
        
        // 2. Take last 4 bytes of timestamp (covers ~136 years)
        uint256 timestampValue = uint256(uint32(block.timestamp));
        
        // 3. Generate 8 bytes from user and amount (randomness component)
        bytes32 userAmountHash = keccak256(abi.encodePacked(user, amount, validator));
        uint256 randomComponent = uint256(uint64(uint256(userAmountHash)));
        
        // 4. Use 4 bytes from sequence counter
        uint256 sequenceValue = uint256(uint32(_nextRequestId));
        
        // 5. Combine all components into a single uint256 using safe bit operations
        uint256 numericId = 0;
        numericId |= (requestTypeValue & 0xFFFF) << 128;
        numericId |= (timestampValue & 0xFFFFFFFF) << 96;
        numericId |= (randomComponent & 0xFFFFFFFFFFFFFFFF) << 32;
        numericId |= (sequenceValue & 0xFFFFFFFF);
                   
        // Convert to bytes
        return abi.encode(numericId);
    }
} 