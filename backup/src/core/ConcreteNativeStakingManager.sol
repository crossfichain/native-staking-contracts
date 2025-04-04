// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./NativeStakingManager.sol";

/**
 * @title ConcreteNativeStakingManager
 * @dev Concrete implementation of the abstract NativeStakingManager for production and testing
 */
contract ConcreteNativeStakingManager is NativeStakingManager {
    // Implement required missing methods
    function withdrawAPY(uint256 shares) external override returns (bytes memory) {
        // Implementation for production can be added here
        return bytes("");
    }
    
    function claimWithdrawalAPY(bytes calldata) external override returns (uint256) {
        // Implementation for production can be added here
        return 0;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {
        // No additional logic needed
    }
    
    // Add a receive function to handle native token transfers
    receive() external payable override {
        // Simply accept the native tokens - minimal implementation to save gas
    }
} 