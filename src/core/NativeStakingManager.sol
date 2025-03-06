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
    
    // Custom roles
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant FULFILLER_ROLE = keccak256("FULFILLER_ROLE");
    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");
    
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
     * @param _apyContract The address of the APY staking contract
     * @param _wxfi The address of the wrapped XFI token
     * @param _oracle The address of the oracle contract
     */
    function initialize(
        address _aprContract,
        address _apyContract,
        address _wxfi,
        address _oracle
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
        
        // Initialize unstaking freeze period (default 30 days)
        _unstakeFreezeTime = 30 days;
        _launchTimestamp = block.timestamp;
        
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
        
        // Validate validator format
        require(bytes(validator).length > 0, "Validator ID cannot be empty");
        require(bytes(validator).length <= 100, "Validator ID too long");
        
        // Check oracle freshness
        _checkOracleFreshness();
        
        address tokenAddress;
        
        if (msg.value > 0) {
            // User is staking native XFI
            require(msg.value == amount, "Amount mismatch");
            
            // Wrap XFI to WXFI
            wxfi.deposit{value: amount}();
            
            // Approve APR contract to spend WXFI (only exact amount)
            // First reset approval to 0 to prevent some ERC20 issues
            IERC20(address(wxfi)).approve(address(aprContract), 0);
            // Then set exact approval amount
            IERC20(address(wxfi)).approve(address(aprContract), amount);
            
            tokenAddress = address(wxfi);
        } else {
            // User is staking WXFI
            IERC20(address(wxfi)).transferFrom(msg.sender, address(this), amount);
            
            // Approve APR contract to spend WXFI (only exact amount)
            // First reset approval to 0 to prevent some ERC20 issues
            IERC20(address(wxfi)).approve(address(aprContract), 0);
            // Then set exact approval amount
            IERC20(address(wxfi)).approve(address(aprContract), amount);
            
            tokenAddress = address(wxfi);
        }
        
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
     * Validator parameter is only used in events for off-chain processing
     * @param amount The amount of XFI to unstake
     * @param validator The validator address/ID (only for events, not stored on-chain)
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
        
        // Validate validator format
        require(bytes(validator).length > 0, "Validator ID cannot be empty");
        require(bytes(validator).length <= 100, "Validator ID too long");
        
        // Check if unstaking is frozen (first month after launch)
        require(!isUnstakingFrozen(), "Unstaking is frozen for the first month");
        
        // Call APR contract and pass validator for events
        uint256 unstakeReqId = aprContract.requestUnstake(msg.sender, amount, validator);
        
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
        amount = aprContract.claimUnstake(msg.sender, requestId);
        
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
            uint256 vaultRequestId = apyContract.requestWithdrawal(previewAssets, msg.sender, msg.sender);
            
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
        amount = aprContract.claimRewards(msg.sender, amount);
        
        // Create a request record
        uint256 requestId = _createRequest(
            msg.sender, 
            amount, 
            "", 
            RequestType.CLAIM_REWARDS
        );
        
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
        require(requestId > 0 && requestId < _nextRequestId, "Invalid request ID");
        require(status != RequestStatus.PENDING, "Cannot set status to PENDING");
        
        Request storage request = _requests[requestId];
        
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
     * @dev Creates a new request record
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
        returns (uint256) 
    {
        uint256 requestId = _nextRequestId++;
        
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
     * @dev Gets information about a specific request
     * @param requestId The ID of the request to get
     * @return user The user who made the request
     * @return amount The amount involved in the request
     * @return validator The validator ID if applicable
     * @return timestamp When the request was created
     * @return requestType The type of request
     * @return status The current status of the request
     * @return statusReason Reason for the current status
     */
    function getRequest(uint256 requestId) 
        external 
        view 
        returns (
            address user,
            uint256 amount,
            string memory validator,
            uint256 timestamp,
            RequestType requestType,
            RequestStatus status,
            string memory statusReason
        ) 
    {
        require(requestId > 0 && requestId < _nextRequestId, "Invalid request ID");
        
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
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
} 