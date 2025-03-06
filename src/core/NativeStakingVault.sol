// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../interfaces/INativeStakingVault.sol";
import "../interfaces/IOracle.sol";

/**
 * @title NativeStakingVault
 * @dev Implementation of the APY staking model (compound vault)
 * Users stake XFI and receive vault shares that appreciate in value
 * Implements the INativeStakingVault interface and follows ERC-4626 standard
 */
contract NativeStakingVault is 
    Initializable,
    AccessControlUpgradeable,
    ERC20Upgradeable,
    ERC4626Upgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    INativeStakingVault
{
    // Constants
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MAX_BPS = 10000; // 100% in basis points
    
    // Custom roles
    bytes32 public constant STAKING_MANAGER_ROLE = keccak256("STAKING_MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant COMPOUNDER_ROLE = keccak256("COMPOUNDER_ROLE");
    
    // State variables
    IOracle public oracle;
    uint256 public maxLiquidityPercent; // in basis points
    uint256 public minWithdrawalAmount;
    
    // Withdrawal request tracking
    mapping(address => uint256[]) private _userWithdrawalRequestIds;
    mapping(uint256 => WithdrawalRequest) private _withdrawalRequests;
    uint256 private _nextWithdrawalRequestId;
    
    // Mapping of last compound timestamp
    uint256 private _lastCompoundTimestamp;
    
    // Mapping of total pending withdrawals
    uint256 private _totalPendingWithdrawals;
    
    // Events
    event WithdrawalRequested(address indexed owner, address indexed receiver, uint256 indexed requestId, uint256 assets, uint256 shares, uint256 unlockTime);
    event WithdrawalClaimed(address indexed receiver, uint256 indexed requestId, uint256 assets);
    event CompoundExecuted(uint256 rewardsAdded, uint256 timestamp);
    event MaxLiquidityPercentUpdated(uint256 newPercent);
    event MinWithdrawalAmountUpdated(uint256 newAmount);
    
    /**
     * @dev Initializes the contract
     * @param _asset The address of the underlying asset (WXFI)
     * @param _oracle The address of the oracle contract
     * @param _name The name of the vault token
     * @param _symbol The symbol of the vault token
     */
    function initialize(
        address _asset,
        address _oracle,
        string memory _name,
        string memory _symbol
    ) external initializer {
        __AccessControl_init();
        __ERC20_init(_name, _symbol);
        __ERC4626_init(IERC20(_asset));
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(STAKING_MANAGER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        _grantRole(COMPOUNDER_ROLE, msg.sender);
        
        oracle = IOracle(_oracle);
        
        // Default values
        maxLiquidityPercent = 1000; // 10% in basis points
        minWithdrawalAmount = 0.1 ether; // 0.1 XFI
        _nextWithdrawalRequestId = 1;
        _lastCompoundTimestamp = block.timestamp;
    }
    
    /**
     * @dev Override decimals function to resolve the inheritance conflict
     * @return The number of decimals for the token
     */
    function decimals() public view override(ERC20Upgradeable, ERC4626Upgradeable, IERC20Metadata) returns (uint8) {
        return ERC4626Upgradeable.decimals();
    }
    
    /**
     * @dev Overrides the deposit function to add additional checks
     * @param assets The amount of underlying assets to deposit
     * @param receiver The address to receive the shares
     * @return shares The amount of shares minted
     */
    function deposit(uint256 assets, address receiver) 
        public 
        override(ERC4626Upgradeable, IERC4626) 
        whenNotPaused 
        nonReentrant 
        returns (uint256 shares) 
    {
        require(assets > 0, "Deposit amount must be > 0");
        
        // Call the parent implementation
        shares = super.deposit(assets, receiver);
        
        return shares;
    }
    
    /**
     * @dev Overrides the mint function to add additional checks
     * @param shares The amount of shares to mint
     * @param receiver The address to receive the shares
     * @return assets The amount of assets used
     */
    function mint(uint256 shares, address receiver) 
        public 
        override(ERC4626Upgradeable, IERC4626) 
        whenNotPaused 
        nonReentrant 
        returns (uint256 assets) 
    {
        require(shares > 0, "Shares amount must be > 0");
        
        // Call the parent implementation
        assets = super.mint(shares, receiver);
        
        return assets;
    }
    
    /**
     * @dev Overrides the withdraw function to add additional checks
     * @param assets The amount of underlying assets to withdraw
     * @param receiver The address to receive the assets
     * @param owner The address that owns the shares
     * @return shares The amount of shares burned
     */
    function withdraw(uint256 assets, address receiver, address owner) 
        public 
        override(ERC4626Upgradeable, IERC4626) 
        whenNotPaused 
        nonReentrant 
        returns (uint256 shares) 
    {
        require(assets >= minWithdrawalAmount, "Amount below minimum");
        
        // Check if there's enough liquidity in the vault for immediate withdrawal
        uint256 availableLiquidity = _maxWithdrawalLiquidity();
        require(assets <= availableLiquidity, "Exceeds available liquidity");
        
        // Call the parent implementation
        shares = super.withdraw(assets, receiver, owner);
        
        return shares;
    }
    
    /**
     * @dev Overrides the redeem function to add additional checks
     * @param shares The amount of shares to burn
     * @param receiver The address to receive the assets
     * @param owner The address that owns the shares
     * @return assets The amount of assets redeemed
     */
    function redeem(uint256 shares, address receiver, address owner) 
        public 
        override(ERC4626Upgradeable, IERC4626) 
        whenNotPaused 
        nonReentrant 
        returns (uint256 assets) 
    {
        assets = previewRedeem(shares);
        require(assets >= minWithdrawalAmount, "Amount below minimum");
        
        // Check if there's enough liquidity in the vault for immediate withdrawal
        uint256 availableLiquidity = _maxWithdrawalLiquidity();
        require(assets <= availableLiquidity, "Exceeds available liquidity");
        
        // Call the parent implementation
        assets = super.redeem(shares, receiver, owner);
        
        return assets;
    }
    
    /**
     * @dev Requests a withdrawal, handling the unbonding period
     * Called when there are not enough liquid assets in the vault
     * @param assets The amount of underlying assets to withdraw
     * @param receiver The address to receive the assets
     * @param owner The owner of the shares
     * @return requestId The ID of the withdrawal request
     */
    function requestWithdrawal(
        uint256 assets,
        address receiver,
        address owner
    ) 
        external 
        override 
        whenNotPaused 
        nonReentrant 
        returns (uint256 requestId) 
    {
        require(assets >= minWithdrawalAmount, "Amount below minimum");
        require(assets <= maxRedeem(owner), "Insufficient shares");
        
        uint256 shares = previewWithdraw(assets);
        
        if (msg.sender != owner) {
            uint256 currentAllowance = allowance(owner, msg.sender);
            require(currentAllowance >= shares, "Insufficient allowance");
            _approve(owner, msg.sender, currentAllowance - shares);
        }
        
        // Burn the shares immediately
        _burn(owner, shares);
        
        // Calculate unlock time based on unbonding period
        uint256 unbondingPeriod = oracle.getUnbondingPeriod();
        uint256 unlockTime = block.timestamp + unbondingPeriod;
        
        // Create withdrawal request
        requestId = _nextWithdrawalRequestId++;
        
        _withdrawalRequests[requestId] = WithdrawalRequest({
            assets: assets,
            shares: shares,
            unlockTime: unlockTime,
            owner: owner,
            completed: false
        });
        
        _userWithdrawalRequestIds[owner].push(requestId);
        _totalPendingWithdrawals += assets;
        
        emit WithdrawalRequested(owner, receiver, requestId, assets, shares, unlockTime);
        
        return requestId;
    }
    
    /**
     * @dev Claims assets from a completed withdrawal request
     * @param requestId The ID of the withdrawal request
     * @return assets The amount of assets claimed
     */
    function claimWithdrawal(uint256 requestId) 
        external 
        override 
        nonReentrant 
        returns (uint256 assets) 
    {
        WithdrawalRequest storage request = _withdrawalRequests[requestId];
        require(request.owner != address(0), "Invalid request ID");
        require(!request.completed, "Already claimed");
        require(block.timestamp >= request.unlockTime, "Still in unbonding period");
        
        assets = request.assets;
        request.completed = true;
        _totalPendingWithdrawals -= assets;
        
        // Transfer the assets to the user
        IERC20(asset()).transfer(msg.sender, assets);
        
        emit WithdrawalClaimed(msg.sender, requestId, assets);
        
        return assets;
    }
    
    /**
     * @dev Gets all pending withdrawal requests for a user
     * @param user The user to get withdrawal requests for
     * @return An array of WithdrawalRequest structs
     */
    function getUserWithdrawalRequests(address user) 
        external 
        view 
        override 
        returns (WithdrawalRequest[] memory) 
    {
        uint256[] storage requestIds = _userWithdrawalRequestIds[user];
        uint256 validCount = 0;
        
        // Count valid requests
        for (uint256 i = 0; i < requestIds.length; i++) {
            if (!_withdrawalRequests[requestIds[i]].completed) {
                validCount++;
            }
        }
        
        WithdrawalRequest[] memory result = new WithdrawalRequest[](validCount);
        uint256 index = 0;
        
        // Add valid requests to result
        for (uint256 i = 0; i < requestIds.length && index < validCount; i++) {
            if (!_withdrawalRequests[requestIds[i]].completed) {
                result[index] = _withdrawalRequests[requestIds[i]];
                index++;
            }
        }
        
        return result;
    }
    
    /**
     * @dev Compounds rewards into the vault
     * Only callable by accounts with the COMPOUNDER_ROLE
     * @return success Boolean indicating if the compound was successful
     */
    function compound() 
        external 
        onlyRole(COMPOUNDER_ROLE) 
        whenNotPaused 
        nonReentrant 
        returns (bool success) 
    {
        // In a real implementation, this would interact with the Cosmos staking
        // and compound the rewards. For this implementation, we'll simulate it.
        
        // Calculate rewards based on APY since last compound
        uint256 calculatedTotalAssets = _calculateTotalAssetsWithCompounding();
        uint256 currentAssets = super.totalAssets();
        
        if (calculatedTotalAssets > currentAssets) {
            uint256 rewardsAmount = calculatedTotalAssets - currentAssets;
            
            // Update last compound timestamp
            _lastCompoundTimestamp = block.timestamp;
            
            emit CompoundExecuted(rewardsAmount, block.timestamp);
            
            return true;
        }
        
        return false;
    }
    
    /**
     * @dev Manually adds rewards to the vault
     * @param rewardAmount The amount of rewards to add
     * @return success Boolean indicating if the compound was successful
     */
    function compoundRewards(uint256 rewardAmount) 
        external 
        override 
        onlyRole(COMPOUNDER_ROLE) 
        whenNotPaused 
        nonReentrant 
        returns (bool success) 
    {
        // Transfer the rewards to the vault
        IERC20(asset()).transferFrom(msg.sender, address(this), rewardAmount);
        
        // Update last compound timestamp
        _lastCompoundTimestamp = block.timestamp;
        
        emit CompoundExecuted(rewardAmount, block.timestamp);
        
        return true;
    }
    
    /**
     * @dev Overrides the totalAssets function to include pending rewards
     * @return The total assets in the vault, including pending rewards
     */
    function totalAssets() 
        public 
        view 
        override(ERC4626Upgradeable, IERC4626) 
        returns (uint256) 
    {
        return _calculateTotalAssetsWithCompounding();
    }
    
    /**
     * @dev Internal function to calculate total assets with compounding
     * @return The total assets with compounding applied
     */
    function _calculateTotalAssetsWithCompounding() internal view returns (uint256) {
        // Get the raw asset balance
        uint256 rawAssets = IERC20(asset()).balanceOf(address(this));
        
        // Add pending withdrawals (assets that are being withdrawn)
        uint256 pendingWithdrawals = _totalPendingWithdrawals;
        
        // Calculate total with compounding
        uint256 calculatedTotalAssets = rawAssets + pendingWithdrawals;
        
        return calculatedTotalAssets;
    }
    
    /**
     * @dev Gets the maximum amount of assets that can be withdrawn immediately
     * @return The maximum amount of assets available for immediate withdrawal
     */
    function _maxWithdrawalLiquidity() private view returns (uint256) {
        uint256 totalVaultAssets = super.totalAssets();
        
        // Subtract pending withdrawals
        if (totalVaultAssets <= _totalPendingWithdrawals) {
            return 0;
        }
        
        uint256 availableAssets = totalVaultAssets - _totalPendingWithdrawals;
        
        // Apply max liquidity percent
        return availableAssets * maxLiquidityPercent / MAX_BPS;
    }
    
    /**
     * @dev Gets the current APY of the vault
     * @return The current APY as a percentage with 18 decimals
     */
    function getCurrentAPY() 
        external 
        view 
        override 
        returns (uint256) 
    {
        return oracle.getCurrentAPY();
    }
    
    /**
     * @dev Gets the total staked amount in the vault
     * @return The total staked amount with 18 decimals
     */
    function getTotalStaked() 
        external 
        view 
        override 
        returns (uint256) 
    {
        return super.totalAssets();
    }
    
    /**
     * @dev Sets the maximum liquidity percentage
     * @param percent The new maximum liquidity percentage in basis points
     */
    function setMaxLiquidityPercent(uint256 percent) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(percent <= MAX_BPS, "Percent exceeds maximum");
        maxLiquidityPercent = percent;
        emit MaxLiquidityPercentUpdated(percent);
    }
    
    /**
     * @dev Sets the minimum withdrawal amount
     * @param amount The new minimum withdrawal amount
     */
    function setMinWithdrawalAmount(uint256 amount) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        minWithdrawalAmount = amount;
        emit MinWithdrawalAmountUpdated(amount);
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