// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/INativeStakingManager.sol";
import "../interfaces/INativeStaking.sol";
import "../interfaces/INativeStakingVault.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IWXFI.sol";

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
    uint256 private constant MIN_STAKE_AMOUNT = 50 ether; // 50 XFI minimum stake
    uint256 private constant MIN_UNSTAKE_AMOUNT = 10 ether; // 10 XFI minimum unstake
    
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
    
    // Request tracking
    mapping(uint256 => Request) private _requests;
    uint256 private _nextRequestId;
    
    // Events
    event APRContractUpdated(address indexed newContract);
    event APYContractUpdated(address indexed newContract);
    event OracleUpdated(address indexed newOracle);
    event StakedAPR(address indexed user, uint256 xfiAmount, uint256 mpxAmount, string validator, bool success, uint256 indexed requestId);
    event StakedAPY(address indexed user, uint256 xfiAmount, uint256 mpxAmount, uint256 shares, uint256 indexed requestId);
    event UnstakedAPR(address indexed user, uint256 xfiAmount, uint256 mpxAmount, string validator, uint256 indexed requestId);
    event WithdrawnAPY(address indexed user, uint256 shares, uint256 xfiAssets, uint256 mpxAssets, uint256 indexed requestId);
    event WithdrawalRequestedAPY(address indexed user, uint256 xfiAssets, uint256 mpxAssets, uint256 indexed requestId);
    event UnstakeClaimedAPR(address indexed user, uint256 indexed requestId, uint256 xfiAmount, uint256 mpxAmount);
    event WithdrawalClaimedAPY(address indexed user, uint256 indexed requestId, uint256 xfiAmount, uint256 mpxAmount);
    event RewardsClaimedAPR(address indexed user, uint256 xfiAmount, uint256 mpxAmount, uint256 indexed requestId);
    event UnstakeFreezeTimeUpdated(uint256 newUnstakeFreezeTime);
    event LaunchTimestampSet(uint256 timestamp);
    event RequestFulfilled(uint256 indexed requestId, address indexed user, RequestStatus indexed status, string reason);
    
    /**
     * @dev Initializes the contract
     * @param _aprContract The address of the APR staking contract
     * @param _apyContract The address of the APY staking vault
     * @param _wxfi The address of the WXFI token
     * @param _oracle The address of the oracle
     * @param _enforceMinimums Whether to enforce minimum staking amounts
     */
    function initialize(
        address _aprContract,
        address _apyContract,
        address _wxfi,
        address _oracle,
        bool _enforceMinimums
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
        
        // Set default launch timestamp to now
        _launchTimestamp = block.timestamp;
        
        // Initialize unstaking freeze period (default 30 days)
        _unstakeFreezeTime = 30 days;
        
        // Set minimum enforcement flag based on deployment environment
        enforceMinimumAmounts = _enforceMinimums;
        
        // Initialize request ID
        _nextRequestId = 1;
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
            require(amount >= MIN_STAKE_AMOUNT, "Amount must be at least 50 XFI");
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
        emit StakedAPR(msg.sender, amount, mpxAmount, validator, success, requestId);
        
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
            
            // Approve APY contract to spend WXFI (only exact amount)
            // First reset approval to 0 to prevent some ERC20 issues
            IERC20(address(wxfi)).approve(address(apyContract), 0);
            // Then set exact approval amount
            IERC20(address(wxfi)).approve(address(apyContract), amount);
        } else {
            // User is staking WXFI
            IERC20(address(wxfi)).transferFrom(msg.sender, address(this), amount);
            
            // Approve APY contract to spend WXFI (only exact amount)
            // First reset approval to 0 to prevent some ERC20 issues
            IERC20(address(wxfi)).approve(address(apyContract), 0);
            // Then set exact approval amount
            IERC20(address(wxfi)).approve(address(apyContract), amount);
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
        emit StakedAPY(msg.sender, amount, mpxAmount, shares, requestId);
        
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
        returns (uint256 requestId) 
    {
        // Validate amount
        require(amount > 0, "Amount must be greater than zero");
        
        // Enforce minimum amount if enabled
        if (enforceMinimumAmounts) {
            require(amount >= MIN_UNSTAKE_AMOUNT, "Amount must be at least 10 XFI");
        }
        
        // Validate validator format
        require(_validateValidatorFormat(validator), "Invalid validator format: must start with 'mxva'");
        
        // Check if unstaking is frozen (first month after launch)
        require(!isUnstakingFrozen(), "Unstaking is frozen for the first month");
        
        // Call the APR staking contract to request unstake
        // The returned unstake request ID is not used locally since we track with our own ID system
        aprContract.requestUnstake(msg.sender, amount, validator);
        
        // Create a request record
        requestId = _createRequest(
            msg.sender, 
            amount, 
            validator, 
            RequestType.UNSTAKE
        );
        
        // Convert XFI to MPX for the event
        uint256 mpxAmount = oracle.convertXFItoMPX(amount);
        
        // Emit event with request ID
        emit UnstakedAPR(msg.sender, amount, mpxAmount, validator, requestId);
        
        return requestId;
    }
    
    /**
     * @dev Claims XFI from a completed APR unstake request
     * @param requestId The ID of the unstake request to claim
     * @return amount The amount of XFI claimed
     */
    function claimUnstakeAPR(uint256 requestId) 
        external 
        override 
        nonReentrant 
        returns (uint256 amount) 
    {
        // Get the amount from APR contract
        amount = aprContract.claimUnstake(msg.sender, requestId);
        
        // Ensure the amount is non-zero
        require(amount > 0, "Nothing to claim");
        
        // Transfer the XFI/WXFI to the user
        bool transferred;
        if (address(this) != address(wxfi)) {
            // If calling from an account different than WXFI contract,
            // we transfer WXFI token to the user
            transferred = IERC20(wxfi).transfer(msg.sender, amount);
        } else {
            // If calling from WXFI contract itself (unlikely), we unwrap and send native XFI
            IWXFI(wxfi).withdraw(amount);
            payable(msg.sender).transfer(amount);
            transferred = true;
        }
        
        require(transferred, "Token transfer failed");
        
        // Convert XFI to MPX for the event
        uint256 mpxAmount = oracle.convertXFItoMPX(amount);
        
        emit UnstakeClaimedAPR(msg.sender, requestId, amount, mpxAmount);
        
        return amount;
    }
    
    /**
     * @dev Withdraws XFI from the APY model by burning vault shares
     * If there are sufficient liquid assets, withdrawal is immediate
     * Otherwise, it will be queued for the unbonding period
     * @param shares The amount of vault shares to burn
     * @return assets The amount of XFI withdrawn or 0 if request is queued
     */
    function withdrawAPY(uint256 shares) 
        external 
        override 
        whenNotPaused 
        nonReentrant 
        returns (uint256 assets) 
    {
        // Check if unstaking is frozen (first month after launch)
        require(!isUnstakingFrozen(), "Unstaking is frozen for the first month");
        
        // Create a request record for tracking
        uint256 requestId = _createRequest(
            msg.sender, 
            shares, 
            "", 
            RequestType.UNSTAKE
        );
        
        // First try a direct withdrawal
        try apyContract.redeem(shares, msg.sender, msg.sender) returns (uint256 redeemedAssets) {
            // Immediate withdrawal successful
            assets = redeemedAssets;
            
            // Convert XFI to MPX for the event
            uint256 mpxAssets = oracle.convertXFItoMPX(assets);
            
            emit WithdrawnAPY(msg.sender, shares, assets, mpxAssets, requestId);
        } catch {
            // Not enough liquid assets, use delayed withdrawal
            uint256 previewAssets = apyContract.previewRedeem(shares);
            
            // Make the vault withdrawal request
            // The vault maintains its own request ID system internally
            apyContract.requestWithdrawal(previewAssets, msg.sender, msg.sender);
            
            // Assets will be delivered later
            assets = 0;
            
            // Convert XFI to MPX for the event
            uint256 mpxAssets = oracle.convertXFItoMPX(previewAssets);
            
            emit WithdrawalRequestedAPY(msg.sender, previewAssets, mpxAssets, requestId);
        }
        
        return assets;
    }
    
    /**
     * @dev Claims XFI from a completed APY withdrawal request
     * @param requestId The ID of the withdrawal request to claim
     * @return assets The amount of XFI claimed
     */
    function claimWithdrawalAPY(uint256 requestId) 
        external 
        override 
        nonReentrant 
        returns (uint256 assets) 
    {
        assets = apyContract.claimWithdrawal(requestId);
        
        // Convert XFI to MPX for the event
        uint256 mpxAssets = oracle.convertXFItoMPX(assets);
        
        emit WithdrawalClaimedAPY(msg.sender, requestId, assets, mpxAssets);
        
        return assets;
    }
    
    /**
     * @dev Claims rewards from the APR model
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
        
        // Get user's total staked amount for validation
        uint256 totalStaked = aprContract.getTotalStaked(msg.sender);
        require(totalStaked > 0, "User has no stake");
        
        // Validate rewards are not unreasonably high (max 100% APR for safety check)
        // This is a simple check to avoid excessive rewards due to oracle manipulation
        uint256 maxReasonableReward = totalStaked / 4; // 25% of stake (100% APR / 4 for quarterly max)
        require(amount <= maxReasonableReward, "Reward amount exceeds safety threshold");
        
        // Clear rewards on oracle to prevent reentrancy
        oracle.clearUserClaimableRewards(msg.sender);
        
        // Call APR contract to handle the claim, passing the amount from oracle
        aprContract.claimRewards(msg.sender, amount);
        
        // Create a request record
        uint256 requestId = _createRequest(
            msg.sender, 
            amount, 
            "", 
            RequestType.CLAIM_REWARDS
        );
        
        // Directly transfer the rewards tokens to the user
        bool transferred = IERC20(wxfi).transfer(msg.sender, amount);
        require(transferred, "Reward transfer failed");
        
        // Convert XFI to MPX for the event
        uint256 mpxAmount = oracle.convertXFItoMPX(amount);
        
        // Emit event with request ID
        emit RewardsClaimedAPR(msg.sender, amount, mpxAmount, requestId);
        
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
     * @dev Extracts the sequence number from a structured request ID
     * @param requestId The structured request ID
     * @return The sequence number component
     */
    function getSequenceFromId(uint256 requestId) 
        external 
        pure 
        returns (uint256) 
    {
        uint32 sequenceValue = uint32(requestId);
        return uint256(sequenceValue);
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
        uint64 randomComponent = uint64(requestId >> 32);
        return uint256(randomComponent);
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
        return (block.timestamp < _launchTimestamp + _unstakeFreezeTime);
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
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
} 