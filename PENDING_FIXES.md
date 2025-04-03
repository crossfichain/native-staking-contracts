# Pending Fixes for Native Staking Contracts

This document outlines the remaining issues found during testing and the necessary changes to fix them.

## APRStaking Contract Issues

### Request ID Handling

The primary issue is with the request ID format and handling in `APRStaking.requestUnstake` and related functions:

1. **Current Implementation**:
   - Request IDs are encoded as bytes with a mixed format
   - The original implementation includes random components that make it difficult to extract in tests
   - The structure lacks a clear mapping between bytes requestIds and numeric requestIds used internally

2. **Suggested Fixes**:
   ```solidity
   // In APRStaking.sol
   
   // Add a mapping to track structured IDs
   mapping(bytes => uint256) private _requestIdToLegacyId;
   mapping(uint256 => bytes) private _legacyIdToRequestId;
   
   function requestUnstake(address user, uint256 amount, string calldata validator) external override whenNotPaused nonReentrant {
       // Existing validation logic...
       
       // Create a simpler, deterministic requestId
       uint32 sequenceValue = uint32(_nextUnstakeRequestId);
       uint256 legacyRequestId = _nextUnstakeRequestId;
       _nextUnstakeRequestId++;
       
       // Create a structured requestId without the random component
       bytes memory requestId = abi.encodePacked(
           uint16(0),                // Request type (0 for unstake)
           uint32(block.timestamp),  // Timestamp
           sequenceValue             // Sequence counter (deterministic)
       );
       
       // Store mappings between IDs
       _requestIdToLegacyId[requestId] = legacyRequestId;
       _legacyIdToRequestId[legacyRequestId] = requestId;
       
       // Store the request
       _unstakeRequests[requestId] = IAPRStaking.UnstakeRequest({
           user: user,
           amount: amount,
           validator: validator,
           timestamp: block.timestamp,
           claimed: false
       });
       
       emit UnstakeRequested(user, amount, validator, requestId);
   }
   
   // Add helper functions for ID conversion
   function getNumericIdFromBytesId(bytes calldata requestId) public view returns (uint256) {
       return _requestIdToLegacyId[requestId];
   }
   
   function getBytesIdFromNumericId(uint256 legacyId) public view returns (bytes memory) {
       return _legacyIdToRequestId[legacyId];
   }
   ```

## NativeStakingManager Contract Issues

### Native Token Transfer Issues

The native token operations have issues with balance handling:

1. **Current Implementation**:
   - The contract attempts to withdraw ETH from the WXFI contract with limited gas
   - ETH transfer failures aren't properly handled in the tests

2. **Suggested Fixes**:
   ```solidity
   // In NativeStakingManager.sol
   
   function claimRewardsAPRNative() external override nonReentrant returns (uint256 amount) {
       // Existing validation logic...
       
       // Add explicit check for contract ETH balance
       uint256 ethBalance = address(this).balance;
       require(ethBalance >= amount, "Insufficient ETH in contract");
       
       // Try to unwrap WXFI to native
       try wxfi.withdraw(amount) {
           // Successful unwrap, now transfer to user with 
           // proper error handling and gas management
           (bool success, ) = msg.sender.call{value: amount}("");
           require(success, "Native token transfer failed");
       } catch {
           // Fallback to regular token transfer on failure
           bool transferred = IERC20(wxfi).transfer(msg.sender, amount);
           require(transferred, "Token transfer failed");
           
           // Emit a different event for fallback behavior
           emit RewardsClaimedAPRToken(msg.sender, amount);
           return amount;
       }
       
       // Convert XFI to MPX for the event
       uint256 rewardsMpxAmount = oracle.convertXFItoMPX(amount);
       emit RewardsClaimedAPRNative(msg.sender, amount, rewardsMpxAmount);
       
       return amount;
   }
   ```

## MockWXFI Contract Issues

### ETH Transfer Improvements

1. **Current Implementation**:
   - The withdraw function used a restrictive gas limit that works poorly in tests
   - Error handling could be improved

2. **Suggested Fixes**:
   ```solidity
   // In MockWXFI.sol
   
   function withdraw(uint256 wad) public {
       require(balanceOf(msg.sender) >= wad, "WXFI: insufficient balance");
       
       // First burn the tokens
       _burn(msg.sender, wad);
       
       // Check contract balance
       require(address(this).balance >= wad, "WXFI: insufficient ETH balance");
       
       // Then send the ETH without restrictive gas limit
       (bool success, ) = msg.sender.call{value: wad}("");
       
       // If the transfer fails, mint tokens back
       if (!success) {
           _mint(msg.sender, wad);
           revert("WXFI: ETH transfer failed");
       }
       
       emit Withdrawal(msg.sender, wad);
   }
   
   // Add a function to check ETH balance
   function getETHBalance() external view returns (uint256) {
       return address(this).balance;
   }
   ```

## Test Improvements

### Proper Setup for Native Token Tests

1. **Current Issues**:
   - Test contracts aren't properly funded with ETH
   - Balance expectations don't account for initial balances

2. **Suggested Fixes**:
   ```solidity
   // In E2ETestBase.sol setup:
   
   function setUp() public virtual {
       // Existing setup...
       
       // Ensure contracts have ETH for native operations
       vm.deal(address(xfi), 100 ether);
       vm.deal(address(manager), 100 ether);
       vm.deal(address(aprContract), 100 ether);
       
       // Verify balances
       assert(address(xfi).balance >= 50 ether);
       assert(address(manager).balance >= 50 ether);
   }
   ```

## Implementation Strategy

1. Start with the `APRStaking` contract improvements to fix the request ID handling
2. Then update the `MockWXFI` contract to better handle native token operations
3. Finally, enhance the `NativeStakingManager` to handle native token transfers more robustly
4. After these core changes, revisit the skipped tests and update them to work with the improved contracts

## Priority Order

1. Request ID handling in APRStaking
2. Native token support in WXFI
3. Error handling in NativeStakingManager
4. Test improvements and fixes 