// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {NativeStaking} from "../src/NativeStaking.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract NativeStakingHarness is NativeStaking {
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

    function exposed_convertToAssets(
        uint256 shares,
        Math.Rounding rounding
    ) external view returns (uint256) {
        return _convertToAssets(shares, rounding);
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

    function exposed_compoundPositionRewards(
        address user,
        uint256 totalRewards
    ) external {
        _compoundPositionRewards(user, totalRewards);
    }

    // Constants getters
    function DELEGATED_TOKEN_PRICE() external pure returns (uint256) {
        return 0.04 ether;
    }

    function MIN_STAKE() external pure returns (uint256) {
        return 50 ether;
    }

    function PRECISION() external pure returns (uint256) {
        return 1e18;
    }

    function COMPOUND_PERIOD() external pure returns (uint256) {
        return 2 weeks;
    }

    function SLASH_PENALTY_RATE() external pure returns (uint256) {
        return 500;
    }

    function operator() external view returns (address) {
        return getRoleMember(OPERATOR_ROLE, 0);
    }
}
