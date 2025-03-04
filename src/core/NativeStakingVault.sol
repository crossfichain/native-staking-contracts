// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/INativeStakingVault.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IWXFI.sol";

/**
 * @title NativeStakingVault
 * @dev Implementation of the APY staking model (compound vault)
 * Users stake XFI and receive vault shares that grow in value as rewards compound
 * Implements the ERC-4626 standard for tokenized vaults
 */
contract NativeStakingVault is 
    Initializable, 
    ERC4626Upgradeable,
    AccessControlUpgradeable, 
    PausableUpgradeable, 
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    INativeStakingVault 
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    
    // Constants
    uint256 private constant PRECISION = 1e18;
    
    // Custom roles
    bytes32 public constant STAKING_MANAGER_ROLE = keccak256("STAKING_MANAGER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    
    // State variables
    IOracle public oracle;
    
    // Counter for withdrawal request IDs
    uint256 private _nextWithdrawalRequestId;
    
    // Mapping of user -> array of withdrawal request IDs
    mapping(address => uint256[]) private _userWithdrawalRequestIds;
    
    // Mapping of requestId -> WithdrawalRequest
    mapping(uint256 => WithdrawalRequest) private _withdrawalRequests;
    
    // Amount of assets staked on Cosmos (not physically in this contract)
    uint256 private _stakedAssets;
    
    // Maximum percentage of vault assets that can be liquid (not staked)
    uint256 public maxLiquidityPercent;
    
    // Minimum withdrawal amount
    uint256 public minWithdrawalAmount;
    
    // Events
    event Deposited(address indexed user, uint256 assets, uint256 shares);
    event WithdrawalRequested(address indexed user, uint256 indexed requestId, uint256 assets, uint256 shares, uint256 unlockTime);
    event WithdrawalClaimed(address indexed user, uint256 indexed requestId, uint256 assets);
    event RewardsCompounded(uint256 rewardAmount);
    event AssetsStaked(uint256 amount);
    event AssetsUnstaked(uint256 amount);
    event MaxLiquidityPercentUpdated(uint256 percent);
    event MinWithdrawalAmountUpdated(uint256 amount);
    
    /**
     * @dev Initializes the contract
     * @param _asset The address of the underlying asset (XFI or WXFI)
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
        __ERC4626_init(IERC20Upgradeable(_asset));
        __ERC20_init(_name, _symbol);
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(STAKING_MANAGER_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        
        oracle = IOracle(_oracle);
        
        maxLiquidityPercent = 20; // 20% of assets can be liquid by default
        minWithdrawalAmount = 0.1 * PRECISION; // 0.1 XFI
        
        _nextWithdrawalRequestId = 1;
        _stakedAssets = 0;
    }
    
    /**
     * @dev Override for totalAssets to include staked assets
     * @return The total amount of the underlying asset managed by the vault
     */
    function totalAssets() public view override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        return IERC20Upgradeable(asset()).balanceOf(address(this)) + _stakedAssets;
    }
    
    /**
     * @dev Override deposit to ensure the contract is not paused
     * @param assets The amount of assets to deposit
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
        require(assets > 0, "Cannot deposit 0 assets");
        
        // Call the parent deposit function
        shares = super.deposit(assets, receiver);
        
        emit Deposited(msg.sender, assets, shares);
        
        // If we have too much liquidity, stake the excess
        _stakeExcessLiquidity();
        
        return shares;
    }
    
    /**
     * @dev Override mint to ensure the contract is not paused
     * @param shares The amount of shares to mint
     * @param receiver The address to receive the shares
     * @return assets The amount of assets deposited
     */
    function mint(uint256 shares, address receiver) 
        public 
        override(ERC4626Upgradeable, IERC4626)
        whenNotPaused 
        nonReentrant 
        returns (uint256 assets) 
    {
        require(shares > 0, "Cannot mint 0 shares");
        
        // Call the parent mint function
        assets = super.mint(shares, receiver);
        
        emit Deposited(msg.sender, assets, shares);
        
        // If we have too much liquidity, stake the excess
        _stakeExcessLiquidity();
        
        return assets;
    }
    
    /**
     * @dev Override withdraw to handle insufficient liquidity case
     * @param assets The amount of assets to withdraw
     * @param receiver The address to receive the assets
     * @param owner The owner of the shares
     * @return shares The amount of shares burned
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) 
        public 
        override(ERC4626Upgradeable, IERC4626)
        whenNotPaused 
        nonReentrant 
        returns (uint256 shares) 
    {
        require(assets >= minWithdrawalAmount, "Amount below minimum");
        
        uint256 liquidAssets = IERC20Upgradeable(asset()).balanceOf(address(this));
        
        if (assets > liquidAssets) {
            // Not enough liquid assets, create a withdrawal request
            return _createWithdrawalRequest(assets, receiver, owner);
        }
        
        // If we have enough liquid assets, proceed with immediate withdrawal
        shares = super.withdraw(assets, receiver, owner);
        
        return shares;
    }
    
    /**
     * @dev Override redeem to handle insufficient liquidity case
     * @param shares The amount of shares to redeem
     * @param receiver The address to receive the assets
     * @param owner The owner of the shares
     * @return assets The amount of assets withdrawn
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) 
        public 
        override(ERC4626Upgradeable, IERC4626)
        whenNotPaused 
        nonReentrant 
        returns (uint256 assets) 
    {
        require(shares > 0, "Cannot redeem 0 shares");
        
        // Calculate how many assets these shares represent
        assets = previewRedeem(shares);
        require(assets >= minWithdrawalAmount, "Amount below minimum");
        
        uint256 liquidAssets = IERC20Upgradeable(asset()).balanceOf(address(this));
        
        if (assets > liquidAssets) {
            // Not enough liquid assets, create a withdrawal request
            _createWithdrawalRequest(assets, receiver, owner);
            return 0; // Assets will be delivered later
        }
        
        // If we have enough liquid assets, proceed with immediate withdrawal
        assets = super.redeem(shares, receiver, owner);
        
        return assets;
    }
    
    /**
     * @dev Creates a withdrawal request for delayed processing
     * @param assets The amount of assets to withdraw
     * @param receiver The address to receive the assets
     * @param owner The owner of the shares
     * @return shares The amount of shares that will be burned
     */
    function _createWithdrawalRequest(
        uint256 assets,
        address receiver,
        address owner
    ) 
        private 
        returns (uint256 shares) 
    {
        // Check allowance if not the owner
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        
        // Calculate shares to burn
        shares = previewWithdraw(assets);
        
        // Burn the shares now
        _burn(owner, shares);
        
        // Calculate unlock time based on unbonding period
        uint256 unbondingPeriod = oracle.getUnbondingPeriod();
        uint256 unlockTime = block.timestamp + unbondingPeriod;
        
        // Create withdrawal request
        uint256 requestId = _nextWithdrawalRequestId++;
        
        _withdrawalRequests[requestId] = WithdrawalRequest({
            assets: assets,
            shares: shares,
            unlockTime: unlockTime,
            owner: owner,
            completed: false
        });
        
        _userWithdrawalRequestIds[owner].push(requestId);
        
        // Request unstaking from Cosmos via operator
        emit WithdrawalRequested(owner, requestId, assets, shares, unlockTime);
        
        // Reduce the staked assets amount
        _stakedAssets -= assets;
        
        // Request unstaking of assets
        emit AssetsUnstaked(assets);
        
        return shares;
    }
    
    /**
     * @dev Implements the requestWithdrawal function from INativeStakingVault
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
        require(
            msg.sender == owner || 
            hasRole(STAKING_MANAGER_ROLE, msg.sender),
            "Not authorized"
        );
        
        // Calculate shares to burn
        uint256 shares = previewWithdraw(assets);
        
        // Burn the shares now
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
        
        // Request unstaking from Cosmos via operator
        emit WithdrawalRequested(owner, requestId, assets, shares, unlockTime);
        
        // Reduce the staked assets amount
        if (assets <= _stakedAssets) {
            _stakedAssets -= assets;
        } else {
            _stakedAssets = 0;
        }
        
        // Request unstaking of assets
        emit AssetsUnstaked(assets);
        
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
        require(
            msg.sender == request.owner || 
            hasRole(STAKING_MANAGER_ROLE, msg.sender) || 
            hasRole(OPERATOR_ROLE, msg.sender),
            "Not authorized"
        );
        require(!request.completed, "Already claimed");
        require(block.timestamp >= request.unlockTime, "Still in unbonding period");
        
        request.completed = true;
        assets = request.assets;
        
        // Transfer the tokens to the owner
        IERC20Upgradeable(asset()).safeTransfer(request.owner, assets);
        
        emit WithdrawalClaimed(request.owner, requestId, assets);
        
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
        WithdrawalRequest[] memory result = new WithdrawalRequest[](requestIds.length);
        
        for (uint256 i = 0; i < requestIds.length; i++) {
            result[i] = _withdrawalRequests[requestIds[i]];
        }
        
        return result;
    }
    
    /**
     * @dev Compounds rewards into the vault
     * Only callable by authorized roles (e.g., OPERATOR_ROLE)
     * @param rewardAmount The amount of rewards to compound
     * @return success Boolean indicating if the compound was successful
     */
    function compoundRewards(uint256 rewardAmount) 
        external 
        override 
        whenNotPaused 
        nonReentrant 
        onlyRole(OPERATOR_ROLE) 
        returns (bool success) 
    {
        require(rewardAmount > 0, "Cannot compound 0 rewards");
        
        // Update the staked assets amount
        _stakedAssets += rewardAmount;
        
        emit RewardsCompounded(rewardAmount);
        
        return true;
    }
    
    /**
     * @dev Staking assets on Cosmos
     * Only callable by authorized roles (e.g., OPERATOR_ROLE)
     * @param amount The amount of assets to stake
     * @return success Boolean indicating if the stake was successful
     */
    function stakeAssets(uint256 amount) 
        external 
        whenNotPaused 
        nonReentrant 
        onlyRole(OPERATOR_ROLE) 
        returns (bool success) 
    {
        require(amount > 0, "Cannot stake 0 assets");
        
        uint256 liquidAssets = IERC20Upgradeable(asset()).balanceOf(address(this));
        require(amount <= liquidAssets, "Not enough liquid assets");
        
        // Update the staked assets amount
        _stakedAssets += amount;
        
        emit AssetsStaked(amount);
        
        return true;
    }
    
    /**
     * @dev Helper function to stake excess liquidity
     * Called after deposits to maintain desired liquidity ratio
     */
    function _stakeExcessLiquidity() private {
        uint256 totalAssetsValue = totalAssets();
        uint256 liquidAssets = IERC20Upgradeable(asset()).balanceOf(address(this));
        uint256 maxLiquidity = (totalAssetsValue * maxLiquidityPercent) / 100;
        
        if (liquidAssets > maxLiquidity && liquidAssets > 0) {
            uint256 excessLiquidity = liquidAssets - maxLiquidity;
            _stakedAssets += excessLiquidity;
            
            emit AssetsStaked(excessLiquidity);
        }
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
     * @dev Gets the total staked amount in the vault (both in the contract and on Cosmos)
     * @return The total staked amount with 18 decimals
     */
    function getTotalStaked() 
        external 
        view 
        override 
        returns (uint256) 
    {
        return totalAssets();
    }
    
    /**
     * @dev Sets the maximum percentage of assets that can be liquid
     * @param percent The new maximum liquidity percentage (0-100)
     */
    function setMaxLiquidityPercent(uint256 percent) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(percent > 0 && percent <= 100, "Invalid percentage");
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