// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
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
 */
contract NativeStakingManager is 
    Initializable, 
    AccessControlUpgradeable, 
    PausableUpgradeable, 
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    INativeStakingManager 
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    
    // Constants
    uint256 private constant PRECISION = 1e18;
    address private constant XFI_NATIVE_ADDRESS = address(0);
    
    // Custom roles
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    
    // State variables
    INativeStaking public aprContract;
    INativeStakingVault public apyContract;
    IWXFI public wxfi;
    IOracle public oracle;
    
    // Events
    event APRContractUpdated(address indexed newContract);
    event APYContractUpdated(address indexed newContract);
    event OracleUpdated(address indexed newOracle);
    event StakedAPR(address indexed user, uint256 amount, string validator, bool success);
    event StakedAPY(address indexed user, uint256 amount, uint256 shares);
    event UnstakedAPR(address indexed user, uint256 amount, string validator, uint256 requestId);
    event WithdrawnAPY(address indexed user, uint256 shares, uint256 assets);
    event WithdrawalRequestedAPY(address indexed user, uint256 assets, uint256 requestId);
    event UnstakeClaimedAPR(address indexed user, uint256 requestId, uint256 amount);
    event WithdrawalClaimedAPY(address indexed user, uint256 requestId, uint256 amount);
    event RewardsClaimedAPR(address indexed user, uint256 amount);
    
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
        
        aprContract = INativeStaking(_aprContract);
        apyContract = INativeStakingVault(_apyContract);
        wxfi = IWXFI(_wxfi);
        oracle = IOracle(_oracle);
    }
    
    /**
     * @dev Stakes XFI using the APR model (direct staking to a validator)
     * @param amount The amount of XFI to stake
     * @param validator The validator address/ID to stake to
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
        address tokenAddress;
        
        if (msg.value > 0) {
            // User is staking native XFI
            require(msg.value == amount, "Amount mismatch");
            
            // Wrap XFI to WXFI
            wxfi.deposit{value: amount}();
            
            // Approve APR contract to spend WXFI
            IERC20(address(wxfi)).approve(address(aprContract), amount);
            
            tokenAddress = address(wxfi);
        } else {
            // User is staking WXFI
            IERC20(address(wxfi)).transferFrom(msg.sender, address(this), amount);
            IERC20(address(wxfi)).approve(address(aprContract), amount);
            
            tokenAddress = address(wxfi);
        }
        
        // Call the APR staking contract
        success = aprContract.stake(msg.sender, amount, validator, tokenAddress);
        
        emit StakedAPR(msg.sender, amount, validator, success);
        
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
        if (msg.value > 0) {
            // User is staking native XFI
            require(msg.value == amount, "Amount mismatch");
            
            // Wrap XFI to WXFI
            wxfi.deposit{value: amount}();
            
            // Approve APY contract to spend WXFI
            IERC20(address(wxfi)).approve(address(apyContract), amount);
            
            // Deposit into the vault
            shares = apyContract.deposit(amount, msg.sender);
        } else {
            // User is staking WXFI
            // Transfer WXFI from user to this contract
            IERC20(address(wxfi)).transferFrom(msg.sender, address(this), amount);
            
            // Approve APY contract to spend WXFI
            IERC20(address(wxfi)).approve(address(apyContract), amount);
            
            // Deposit into the vault
            shares = apyContract.deposit(amount, msg.sender);
        }
        
        emit StakedAPY(msg.sender, amount, shares);
        
        return shares;
    }
    
    /**
     * @dev Requests to unstake XFI from the APR model
     * @param amount The amount of XFI to unstake
     * @param validator The validator address/ID to unstake from
     * @return requestId The ID of the unstake request
     */
    function unstakeAPR(uint256 amount, string calldata validator) 
        external 
        override 
        whenNotPaused 
        nonReentrant 
        returns (uint256 requestId) 
    {
        requestId = aprContract.requestUnstake(msg.sender, amount, validator);
        
        emit UnstakedAPR(msg.sender, amount, validator, requestId);
        
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
        
        emit UnstakeClaimedAPR(msg.sender, requestId, amount);
        
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
        // First try a direct withdrawal
        try apyContract.redeem(shares, msg.sender, msg.sender) returns (uint256 redeemedAssets) {
            // Immediate withdrawal successful
            assets = redeemedAssets;
            emit WithdrawnAPY(msg.sender, shares, assets);
        } catch {
            // Not enough liquid assets, use delayed withdrawal
            uint256 previewAssets = apyContract.previewRedeem(shares);
            uint256 requestId = apyContract.requestWithdrawal(previewAssets, msg.sender, msg.sender);
            
            // Assets will be delivered later
            assets = 0;
            
            emit WithdrawalRequestedAPY(msg.sender, previewAssets, requestId);
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
        
        emit WithdrawalClaimedAPY(msg.sender, requestId, assets);
        
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
        amount = aprContract.claimRewards(msg.sender);
        
        emit RewardsClaimedAPR(msg.sender, amount);
        
        return amount;
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
        onlyRole(DEFAULT_ADMIN_ROLE) 
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
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
} 