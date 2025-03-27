// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/interfaces/IERC4626Upgradeable.sol";
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
    mapping(address => bytes[]) private _userWithdrawalRequestIds;
    mapping(bytes => WithdrawalRequest) private _withdrawalRequests;
    uint256 private _nextWithdrawalRequestId;
    
    // Mapping of last compound timestamp
    uint256 private _lastCompoundTimestamp;
    
    // Mapping of total pending withdrawals
    uint256 private _totalPendingWithdrawals;
    
    // Events
    event WithdrawalRequested(address indexed owner, address indexed receiver, bytes indexed requestId, uint256 assets, uint256 shares, uint256 unlockTime);
    event WithdrawalClaimed(address indexed receiver, bytes indexed requestId, uint256 assets);
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
        __ERC4626_init(IERC20Upgradeable(_asset));
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
    function decimals() public view override(ERC20Upgradeable, ERC4626Upgradeable, IERC20MetadataUpgradeable) returns (uint8) {
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
        override(ERC4626Upgradeable, IERC4626Upgradeable) 
        whenNotPaused 
        nonReentrant 
        returns (uint256 shares) 
    {
        require(assets > 0, "Deposit amount must be > 0");
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
        override(ERC4626Upgradeable, IERC4626Upgradeable) 
        whenNotPaused 
        nonReentrant 
        returns (uint256 assets) 
    {
        require(shares > 0, "Shares amount must be > 0");
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
        override(ERC4626Upgradeable, IERC4626Upgradeable) 
        whenNotPaused 
        nonReentrant 
        returns (uint256 shares) 
    {
        require(assets >= minWithdrawalAmount, "Amount below minimum");
        uint256 availableLiquidity = _maxWithdrawalLiquidity();
        require(assets <= availableLiquidity, "Exceeds available liquidity");
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
        override(ERC4626Upgradeable, IERC4626Upgradeable) 
        whenNotPaused 
        nonReentrant 
        returns (uint256 assets) 
    {
        assets = previewRedeem(shares);
        require(assets >= minWithdrawalAmount, "Amount below minimum");
        uint256 availableLiquidity = _maxWithdrawalLiquidity();
        require(assets <= availableLiquidity, "Exceeds available liquidity");
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
        returns (bytes memory requestId) 
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
        
        // Create a structured requestId as bytes - similar format to other contracts
        // Format: [2 bytes: type][4 bytes: timestamp][20 bytes: owner][32 bytes: hash][4 bytes: sequence]
        bytes2 requestType = bytes2(0x0000); // Use 0 for withdrawal requests
        bytes4 timestamp = bytes4(uint32(block.timestamp));
        
        // Create a hash that combines the assets and other data
        bytes32 dataHash = keccak256(abi.encodePacked(assets, shares, unlockTime, block.chainid));
        
        // Get sequence number
        uint32 sequence = uint32(_nextWithdrawalRequestId);
        _nextWithdrawalRequestId++;
        
        // Create the full requestId
        requestId = abi.encodePacked(requestType, timestamp, owner, dataHash, sequence);
        
        // Store the withdrawal request
        _withdrawalRequests[requestId] = WithdrawalRequest({
            assets: assets,
            shares: shares,
            unlockTime: unlockTime,
            owner: owner,
            completed: false
        });
        
        _userWithdrawalRequestIds[owner].push(requestId);
        
        // Update total pending withdrawals - use the actual asset amount, not the shares
        _totalPendingWithdrawals += assets;
        
        emit WithdrawalRequested(owner, receiver, requestId, assets, shares, unlockTime);
        
        return requestId;
    }
    
    /**
     * @dev Finds a withdrawal request by its ID or extracted sequence
     * @param requestId The request ID to find
     * @return The withdrawal request
     */
    function _findWithdrawalRequest(bytes calldata requestId) 
        internal 
        view 
        returns (WithdrawalRequest storage) 
    {
        // Direct lookup first (most efficient path)
        WithdrawalRequest storage request = _withdrawalRequests[requestId];
        
        // If found via direct lookup, return it
        if (request.owner != address(0)) {
            return request;
        }
        
        // If not found and format seems structured (has minimum expected length)
        if (requestId.length >= 62) {
            address requestOwner;
            uint256 sequence;
            
            // Extract owner from position 6 (after 2-byte type + 4-byte timestamp)
            assembly {
                let offset := add(requestId.offset, 6)
                requestOwner := shr(96, calldataload(offset))
            }
            
            // Extract sequence from last 4 bytes
            assembly {
                let len := requestId.length
                let offset := add(requestId.offset, sub(len, 4))
                sequence := and(calldataload(offset), 0xFFFFFFFF)
            }
            
            // Look through this user's requests for matching sequence
            bytes[] storage userRequests = _userWithdrawalRequestIds[requestOwner];
            for (uint256 i = 0; i < userRequests.length; i++) {
                bytes memory storedId = userRequests[i];
                if (storedId.length >= 4) {
                    // Extract sequence from stored ID
                    uint256 storedSequence;
                    assembly {
                        let len := mload(storedId)
                        let ptr := add(add(storedId, 0x20), sub(len, 4))
                        storedSequence := and(mload(ptr), 0xFFFFFFFF)
                    }
                    
                    if (storedSequence == sequence) {
                        return _withdrawalRequests[storedId];
                    }
                }
            }
        }
        
        // If direct lookup and sequence extraction failed, try numeric ID extraction
        if (requestId.length == 32) {
            // Try to decode as uint256
            uint256 numericId;
            assembly {
                numericId := calldataload(requestId.offset)
            }
            
            // Only extract sequence if it's a structured ID
            if (numericId >= 4294967296) { // 2^32
                uint256 sequence = numericId & 0xFFFFFFFF; // Extract last 4 bytes
                
                // Try to find by sequence across all users (slower path)
                address[] memory allUsers = _getAllUsers();
                for (uint256 u = 0; u < allUsers.length; u++) {
                    bytes[] storage userRequests = _userWithdrawalRequestIds[allUsers[u]];
                    for (uint256 i = 0; i < userRequests.length; i++) {
                        bytes memory storedId = userRequests[i];
                        if (storedId.length >= 4) {
                            uint256 storedSequence;
                            assembly {
                                let len := mload(storedId)
                                let ptr := add(add(storedId, 0x20), sub(len, 4))
                                storedSequence := and(mload(ptr), 0xFFFFFFFF)
                            }
                            
                            if (storedSequence == sequence) {
                                return _withdrawalRequests[storedId];
                            }
                        }
                    }
                }
            }
        }
        
        // Fall back to empty request if nothing found
        return request;
    }
    
    /**
     * @dev Helper function to get all users with withdrawal requests
     * @return Array of user addresses
     * @dev This is a simplified implementation that would need optimization in production
     */
    function _getAllUsers() internal view returns (address[] memory) {
        // This is a simplified implementation
        // In production, maintain a mapping of all users with withdrawal requests
        address[] memory users = new address[](1);
        users[0] = msg.sender;
        return users;
    }
    
    /**
     * @dev Claims assets from a completed withdrawal request
     * @param requestId The ID of the withdrawal request
     * @return assets The amount of assets claimed
     */
    function claimWithdrawal(bytes calldata requestId) 
        external 
        override 
        nonReentrant 
        returns (uint256 assets) 
    {
        WithdrawalRequest storage request = _findWithdrawalRequest(requestId);
        require(request.owner != address(0), "Invalid request ID");
        require(!request.completed, "Already claimed");
        require(block.timestamp >= request.unlockTime, "Still in unbonding period");
        
        assets = request.assets;
        request.completed = true;
        _totalPendingWithdrawals -= assets;
        
        // Transfer the assets to the user
        IERC20Upgradeable(asset()).transfer(msg.sender, assets);
        
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
        bytes[] storage requestIds = _userWithdrawalRequestIds[user];
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
        // Calculate rewards based on APY since last compound
        uint256 timeElapsed = block.timestamp - _lastCompoundTimestamp;
        uint256 currentAssets = super.totalAssets();
        
        // Calculate rewards using APY formula: rewards = principal * (APY/100) * (time/365 days)
        uint256 apy = oracle.getCurrentAPY();
        uint256 rewardsAmount = (currentAssets * apy * timeElapsed) / (365 days * 10000); // APY is in basis points
        
        if (rewardsAmount > 0) {
            // Update last compound timestamp
            _lastCompoundTimestamp = block.timestamp;
            
            // Transfer rewards to the vault
            IERC20Upgradeable(asset()).transferFrom(msg.sender, address(this), rewardsAmount);
            
            // Rewards are automatically distributed by increasing the exchange rate between shares and assets
            // No need to mint new shares since the value of existing shares increases
            
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
        IERC20Upgradeable(asset()).transferFrom(msg.sender, address(this), rewardAmount);
        
        // Rewards are automatically distributed by increasing the exchange rate between shares and assets
        // No need to mint new shares since the value of existing shares increases
        
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
        override(ERC4626Upgradeable, IERC4626Upgradeable) 
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
        uint256 rawAssets = IERC20Upgradeable(asset()).balanceOf(address(this));
        
        // Calculate rewards based on APY since last compound
        uint256 timeElapsed = block.timestamp - _lastCompoundTimestamp;
        
        // If there are no assets or no time has elapsed, return raw assets
        if (rawAssets == 0 || timeElapsed == 0) {
            return rawAssets;
        }
        
        // Calculate rewards using APY formula: rewards = principal * (APY/100) * (time/365 days)
        uint256 apy = oracle.getCurrentAPY();
        if (apy == 0) {
            return rawAssets;
        }
        
        uint256 rewardsAmount = (rawAssets * apy * timeElapsed) / (365 days * 10000); // APY is in basis points
        
        // Calculate total with compounding
        return rawAssets + rewardsAmount;
    }
    
    /**
     * @dev Gets the maximum amount of assets that can be withdrawn immediately
     * @return The maximum amount of assets available for immediate withdrawal
     */
    function _maxWithdrawalLiquidity() private view returns (uint256) {
        // Get actual token balance in the vault
        uint256 actualBalance = IERC20Upgradeable(asset()).balanceOf(address(this));
        
        // Ensure we don't promise more than we have
        if (actualBalance <= _totalPendingWithdrawals) {
            return 0;
        }
        
        // Available liquidity is the actual balance minus tokens reserved for pending withdrawals
        uint256 availableLiquidity = actualBalance - _totalPendingWithdrawals;
        
        // Apply max liquidity percent
        return availableLiquidity * maxLiquidityPercent / MAX_BPS;
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

    // Override all required functions with proper inheritance
    function name() public view override(ERC20Upgradeable, IERC20MetadataUpgradeable) returns (string memory) {
        return super.name();
    }

    function symbol() public view override(ERC20Upgradeable, IERC20MetadataUpgradeable) returns (string memory) {
        return super.symbol();
    }

    function totalSupply() public view override(ERC20Upgradeable, IERC20Upgradeable) returns (uint256) {
        return super.totalSupply();
    }

    function balanceOf(address account) public view override(ERC20Upgradeable, IERC20Upgradeable) returns (uint256) {
        return super.balanceOf(account);
    }

    function transfer(address to, uint256 amount) public override(ERC20Upgradeable, IERC20Upgradeable) returns (bool) {
        return super.transfer(to, amount);
    }

    function allowance(address owner, address spender) public view override(ERC20Upgradeable, IERC20Upgradeable) returns (uint256) {
        return super.allowance(owner, spender);
    }

    function approve(address spender, uint256 amount) public override(ERC20Upgradeable, IERC20Upgradeable) returns (bool) {
        return super.approve(spender, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override(ERC20Upgradeable, IERC20Upgradeable) returns (bool) {
        return super.transferFrom(from, to, amount);
    }

    function asset() public view override(ERC4626Upgradeable, IERC4626Upgradeable) returns (address) {
        return ERC4626Upgradeable.asset();
    }

    function convertToShares(uint256 assets) public view override(ERC4626Upgradeable, IERC4626Upgradeable) returns (uint256) {
        return ERC4626Upgradeable.convertToShares(assets);
    }

    function convertToAssets(uint256 shares) public view override(ERC4626Upgradeable, IERC4626Upgradeable) returns (uint256) {
        return ERC4626Upgradeable.convertToAssets(shares);
    }

    function maxDeposit(address receiver) public view override(ERC4626Upgradeable, IERC4626Upgradeable) returns (uint256) {
        return ERC4626Upgradeable.maxDeposit(receiver);
    }

    function maxMint(address receiver) public view override(ERC4626Upgradeable, IERC4626Upgradeable) returns (uint256) {
        return ERC4626Upgradeable.maxMint(receiver);
    }

    function maxWithdraw(address owner) public view override(ERC4626Upgradeable, IERC4626Upgradeable) returns (uint256) {
        return ERC4626Upgradeable.maxWithdraw(owner);
    }

    function maxRedeem(address owner) public view override(ERC4626Upgradeable, IERC4626Upgradeable) returns (uint256) {
        return ERC4626Upgradeable.maxRedeem(owner);
    }

    function previewDeposit(uint256 assets) public view override(ERC4626Upgradeable, IERC4626Upgradeable) returns (uint256) {
        return ERC4626Upgradeable.previewDeposit(assets);
    }

    function previewMint(uint256 shares) public view override(ERC4626Upgradeable, IERC4626Upgradeable) returns (uint256) {
        return ERC4626Upgradeable.previewMint(shares);
    }

    function previewWithdraw(uint256 assets) public view override(ERC4626Upgradeable, IERC4626Upgradeable) returns (uint256) {
        return ERC4626Upgradeable.previewWithdraw(assets);
    }

    function previewRedeem(uint256 shares) public view override(ERC4626Upgradeable, IERC4626Upgradeable) returns (uint256) {
        return ERC4626Upgradeable.previewRedeem(shares);
    }

    /**
     * @dev Gets the total amount of tokens that are pending withdrawal
     * @return The total pending withdrawals
     */
    function getTotalPendingWithdrawals() external view returns (uint256) {
        return _totalPendingWithdrawals;
    }
} 