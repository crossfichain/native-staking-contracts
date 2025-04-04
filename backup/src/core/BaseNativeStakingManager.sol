// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Import interface directly instead of NativeStakingManager
import "../interfaces/INativeStakingManager.sol";
import "../interfaces/INativeStaking.sol";
import "../interfaces/INativeStakingVault.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IWXFI.sol";
import "./NativeStakingManagerLib.sol";

/**
 * @title BaseNativeStakingManager
 * @dev Base implementation for the NativeStakingManager interface
 * with core functionality. This is split from ConcreteNativeStakingManager
 * to reduce contract size.
 */
abstract contract BaseNativeStakingManager is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    INativeStakingManager
{
    // Import StakingMode for clarity in this contract
    using NativeStakingManagerLib for uint256;
    
    // Use the StakingMode enum from the library
    NativeStakingManagerLib.StakingMode public defaultStakingMode;
    
    // Role constants
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant FULFILLER_ROLE = keccak256("FULFILLER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    
    // Contracts
    INativeStaking public aprStaking;
    INativeStakingVault public apyStaking;
    IWXFI public wxfi;
    IOracle public oracle;
    
    // Settings
    bool public enforceMinimums;
    uint256 public minStake;
    uint256 public minUnstake;
    uint256 public minRewardClaim;
    
    // Unstaking freeze
    uint256 public unstakingFrozenUntil;
    uint256 public freezeDuration;
    
    // Events
    event StakingModeChanged(NativeStakingManagerLib.StakingMode mode);
    event StakeRequested(address indexed user, uint256 amount, NativeStakingManagerLib.StakingMode mode, string validator);
    event UnstakeRequested(address indexed user, uint256 amount, NativeStakingManagerLib.StakingMode mode, string validator);
    event RewardsClaimRequested(address indexed user, NativeStakingManagerLib.StakingMode mode, uint256 amount);
    event StakeFulfilled(address indexed user, uint256 amount, NativeStakingManagerLib.StakingMode mode, string validator);
    event UnstakeFulfilled(address indexed user, uint256 amount, NativeStakingManagerLib.StakingMode mode, string validator);
    event RewardsClaimFulfilled(address indexed user, NativeStakingManagerLib.StakingMode mode, uint256 amount);
    event StakingModeDefaultSet(NativeStakingManagerLib.StakingMode mode);
    event UnstakingFrozen(uint256 freezeDuration);
    event UnstakingThawed();
    event MinimumsChanged(bool enforced, uint256 minStake, uint256 minUnstake, uint256 minRewardClaim);
    
    // Request trackers for off-chain processing
    struct StakingRequest {
        address user;
        uint256 amount;
        NativeStakingManagerLib.StakingMode mode;
        string validator;
        uint256 timestamp;
        bool processed;
    }
    
    struct UnstakingRequest {
        address user;
        uint256 amount;
        NativeStakingManagerLib.StakingMode mode;
        string validator;
        uint256 timestamp;
        bool processed;
    }
    
    struct RewardsClaimRequest {
        address user;
        NativeStakingManagerLib.StakingMode mode;
        uint256 timestamp;
        bool processed;
    }
    
    // Storage for pending requests
    StakingRequest[] public stakingRequests;
    UnstakingRequest[] public unstakingRequests;
    RewardsClaimRequest[] public rewardsClaimRequests;
    
    /**
     * @dev Initializes the contract
     */
    function initialize(
        address _aprStaking,
        address _apyStaking,
        address _wxfi,
        address _oracle,
        bool _enforceMinimums,
        uint256 _initialFreezeTime,
        uint256 _minStake,
        uint256 _minUnstake,
        uint256 _minRewardClaim
    ) public virtual initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(PAUSER_ROLE, msg.sender);
        _setupRole(EMERGENCY_ROLE, msg.sender);
        _setupRole(FULFILLER_ROLE, msg.sender);
        _setupRole(UPGRADER_ROLE, msg.sender);
        
        aprStaking = INativeStaking(_aprStaking);
        apyStaking = INativeStakingVault(_apyStaking);
        wxfi = IWXFI(_wxfi);
        oracle = IOracle(_oracle);
        
        enforceMinimums = _enforceMinimums;
        minStake = _minStake;
        minUnstake = _minUnstake;
        minRewardClaim = _minRewardClaim;
        
        // Default to APR staking
        defaultStakingMode = NativeStakingManagerLib.StakingMode.APR;
        
        // Set unstaking freeze if specified
        if (_initialFreezeTime > 0) {
            freezeDuration = _initialFreezeTime;
            unstakingFrozenUntil = block.timestamp + _initialFreezeTime;
            emit UnstakingFrozen(_initialFreezeTime);
        }
    }
    
    /**
     * @dev Pauses all functions with the whenNotPaused modifier
     */
    function pause() external virtual onlyRole(PAUSER_ROLE) {
        _pause();
    }
    
    /**
     * @dev Unpauses the contract
     */
    function unpause() external virtual onlyRole(PAUSER_ROLE) {
        _unpause();
    }
    
    /**
     * @dev Freezes unstaking for a specified duration
     */
    function freezeUnstaking(uint256 duration) external virtual onlyRole(EMERGENCY_ROLE) {
        freezeDuration = duration;
        unstakingFrozenUntil = block.timestamp + duration;
        emit UnstakingFrozen(duration);
    }
    
    /**
     * @dev Thaws unstaking before the freeze period ends
     */
    function thawUnstaking() external virtual onlyRole(EMERGENCY_ROLE) {
        unstakingFrozenUntil = block.timestamp;
        emit UnstakingThawed();
    }
    
    /**
     * @dev Updates minimum values
     */
    function setMinimums(
        bool _enforceMinimums,
        uint256 _minStake,
        uint256 _minUnstake,
        uint256 _minRewardClaim
    ) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        enforceMinimums = _enforceMinimums;
        minStake = _minStake;
        minUnstake = _minUnstake;
        minRewardClaim = _minRewardClaim;
        emit MinimumsChanged(_enforceMinimums, _minStake, _minUnstake, _minRewardClaim);
    }
    
    /**
     * @dev Sets the default staking mode
     */
    function setDefaultStakingMode(NativeStakingManagerLib.StakingMode mode) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        defaultStakingMode = mode;
        emit StakingModeDefaultSet(mode);
    }
    
    /**
     * @dev Gets the default staking mode
     */
    function getDefaultStakingMode() public virtual view returns (NativeStakingManagerLib.StakingMode) {
        return defaultStakingMode;
    }
    
    /**
     * @dev Request to stake tokens 
     */
    function requestStake(
        uint256 amount, 
        NativeStakingManagerLib.StakingMode mode, 
        string calldata validator
    ) 
        public
        virtual 
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        // Validate amount
        require(amount > 0, "Amount must be greater than 0");
        if (enforceMinimums) {
            require(amount >= minStake, "Amount below minimum");
        }
        
        // Get WXFI from sender
        require(wxfi.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        // Store request
        stakingRequests.push(StakingRequest({
            user: msg.sender,
            amount: amount,
            mode: mode,
            validator: validator,
            timestamp: block.timestamp,
            processed: false
        }));
        
        uint256 requestId = stakingRequests.length - 1;
        emit StakeRequested(msg.sender, amount, mode, validator);
        
        return requestId;
    }
    
    /**
     * @dev Request to unstake tokens
     */
    function requestUnstake(
        uint256 amount, 
        NativeStakingManagerLib.StakingMode mode, 
        string calldata validator
    ) 
        public
        virtual
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        // Check if unstaking is frozen
        require(!isUnstakingFrozen(), "Unstaking is currently frozen");
        
        // Validate amount
        require(amount > 0, "Amount must be greater than 0");
        if (enforceMinimums) {
            require(amount >= minUnstake, "Amount below minimum");
        }
        
        // Store request
        unstakingRequests.push(UnstakingRequest({
            user: msg.sender,
            amount: amount,
            mode: mode,
            validator: validator,
            timestamp: block.timestamp,
            processed: false
        }));
        
        uint256 requestId = unstakingRequests.length - 1;
        emit UnstakeRequested(msg.sender, amount, mode, validator);
        
        return requestId;
    }
    
    /**
     * @dev Request to claim rewards
     */
    function requestClaimRewards(
        NativeStakingManagerLib.StakingMode mode
    ) 
        public
        virtual
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        // Store request
        rewardsClaimRequests.push(RewardsClaimRequest({
            user: msg.sender,
            mode: mode,
            timestamp: block.timestamp,
            processed: false
        }));
        
        uint256 requestId = rewardsClaimRequests.length - 1;
        emit RewardsClaimRequested(msg.sender, mode, 0);
        
        return requestId;
    }
    
    /**
     * @dev Checks if unstaking is frozen 
     */
    function isUnstakingFrozen() public virtual view returns (bool) {
        return block.timestamp < unstakingFrozenUntil;
    }
    
    /**
     * @dev Checks if the contract has enough balance to pay rewards
     * @param amount The amount of rewards to check
     * @return Whether the contract has enough balance
     */
    function hasEnoughRewardBalance(uint256 amount) public virtual view returns (bool) {
        return wxfi.balanceOf(address(this)) >= amount;
    }
    
    /**
     * @dev Implement the _authorizeUpgrade function required by UUPSUpgradeable
     * @param newImplementation The address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(UPGRADER_ROLE) {
        // This function is intentionally empty and is used for authorization only
    }

    /**
     * @dev Required to receive native token transfers
     */
    receive() external virtual payable {
        // Allow receiving ETH
    }
} 