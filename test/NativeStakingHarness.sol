// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {NativeStaking} from "../src/NativeStaking.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract NativeStakingHarness is NativeStaking {
    uint256 public constant COMPOUND_PERIOD = 2 weeks;
    // bytes32 public constant override OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    constructor(
        address _oracle,
        address _operator,
        address _emergency
    ) NativeStaking(_oracle, _operator, _emergency) {}
    

    // Expose private functions for testing
    function exposed_convertToShares(
        uint256 assets,
        Math.Rounding rounding
    ) external view returns (uint256) {
        return _convertToShares(assets, rounding);
    }

    function exposed_calculateDelegatedAmount(
        uint256 amount
    ) external view returns (uint256) {
        return _calculateDelegatedAmount(amount);
    }

    function exposed_calculateRewards(
        address user
    ) external view returns (uint256) {
        return _calculateRewards(user);
    }

    function exposed_getNativeTokenPrice() external view returns (uint256) {
        return _getNativeTokenPrice();
    }

    // Expose constants for testing
    // function exposed_DELEGATED_TOKEN_PRICE() external pure returns (uint256) {
    //     return DELEGATED_TOKEN_PRICE;
    // }

    // function exposed_MIN_STAKE() external pure returns (uint256) {
    //     return MIN_STAKE;
    // }

    // function exposed_PRECISION() external pure returns (uint256) {
    //     return PRECISION;
    // }

    // function exposed_COMPOUND_PERIOD() external pure returns (uint256) {
    //     return COMPOUND_PERIOD;
    // }

    // function exposed_SLASH_PENALTY_RATE() external pure returns (uint256) {
    //     return SLASH_PENALTY_RATE;
    // // }

    function operator() external view returns (address) {
        return getRoleMember(OPERATOR_ROLE, 0);
    }
}
