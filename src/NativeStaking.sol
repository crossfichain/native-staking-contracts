// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @notice Core imports
 */
import "./core/NativeStakingOperator.sol";

/**
 * @title NativeStaking
 * @dev Main implementation of native XFI staking to validators
 */
contract NativeStaking is NativeStakingOperator {
    /**
     * @dev Initializes the contract
     * @param admin Address of the admin who will have DEFAULT_ADMIN_ROLE
     * @param minStakeAmount The min amount required for staking
     * @param oracle Address of the oracle for price conversions
     */
    function initialize(
        address admin,
        uint256 minStakeAmount,
        address oracle
    ) external initializer {
        __nativeStakingBase_init(admin, minStakeAmount, oracle);
    }

    /**
     * @dev Fallback function to receive ETH
     */
    receive() external payable {}
} 