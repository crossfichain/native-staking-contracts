// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @notice Library imports
 */
import "../libraries/StakingUtils.sol";
import "../libraries/PriceConverter.sol";

/**
 * @notice Contract imports
 */
import "./NativeStakingUser.sol";

/**
 * @title NativeStakingOperator
 * @dev Operator functions for the NativeStaking contract
 */
abstract contract NativeStakingOperator is NativeStakingUser {
    /**
     * @dev Completes an unstake process
     * @param staker The address of the staker
     * @param validatorId The validator identifier
     * @param amount Amount to unstake
     */
    function completeUnstake(
        address staker,
        string calldata validatorId,
        uint256 amount
    )
        external
        virtual
        onlyRole(OPERATOR_ROLE)
        nonReentrant
        validValidatorId(validatorId)
        validatorExists(validatorId)
    {
        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );
        UserStake storage userStake = _userStakes[staker][normalizedId];

        if (!userStake.inUnstakeProcess) {
            revert NoUnstakeInProcess();
        }
        if (userStake.amount < amount) {
            revert InsufficientStake(amount, userStake.amount);
        }

        uint256 mpxAmountToUnstake = 0;
        if (userStake.amount > 0) {
            mpxAmountToUnstake =
                (userStake.mpxAmount * amount) /
                userStake.amount;
        }

        userStake.amount -= amount;
        userStake.mpxAmount -= mpxAmountToUnstake;
        userStake.inUnstakeProcess = false;
        userStake.unstakeAmount = 0;

        _validators[normalizedId].totalStaked -= amount;
        if (userStake.amount == 0) {
            _validators[normalizedId].uniqueStakers--;
            _removeValidatorFromUserList(staker, normalizedId);
        }

        _userTotalStaked[staker] -= amount;

        emit UnstakeCompleted(staker, normalizedId, amount, mpxAmountToUnstake);

        (bool success, ) = staker.call{value: amount}("");
        if (!success) {
            revert TransferFailed();
        }
    }

    /**
     * @dev Completes a reward claim
     * @param staker The address of the staker
     * @param validatorId The validator identifier
     * @param isInitiatedDueUnstake Whether the claim was initiated due to unstake
     */
    function completeRewardClaim(
        address staker,
        string calldata validatorId,
        bool isInitiatedDueUnstake
    )
        external
        payable
        virtual
        onlyRole(OPERATOR_ROLE)
        nonReentrant
        validValidatorId(validatorId)
        validatorExists(validatorId)
    {
        if (msg.value == 0) {
            revert InsufficientRewards(msg.value, _minStakeAmount);
        }

        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );
        UserStake storage userStake = _userStakes[staker][normalizedId];

        if (userStake.amount == 0) {
            revert NoStakeFound();
        }

        if (userStake.inUnstakeProcess && !isInitiatedDueUnstake) {
            revert UnstakeInProcess();
        }

        uint256 rewardAmount = msg.value;

        (bool success, ) = staker.call{value: rewardAmount}("");
        if (!success) {
            revert TransferFailed();
        }

        emit RewardClaimed(staker, normalizedId, rewardAmount);
    }

    /**
     * @dev Completes emergency withdrawal
     * @param staker The address of the staker
     * @param amount The amount to withdraw
     */
    function completeEmergencyWithdrawal(
        address staker,
        uint256 amount
    ) external virtual onlyRole(OPERATOR_ROLE) nonReentrant {
        if (!_emergencyWithdrawalRequested[staker]) {
            revert NoEmergencyWithdrawalRequested();
        }
        if (amount == 0 || amount > _userTotalStaked[staker]) {
            revert InvalidAmount(amount, _userTotalStaked[staker]);
        }

        _emergencyWithdrawalRequested[staker] = false;

        string[] memory userValidators = _userValidators[staker];

        for (uint256 i = 0; i < userValidators.length; i++) {
            string memory validatorId = userValidators[i];
            UserStake storage userStake = _userStakes[staker][validatorId];

            if (userStake.amount > 0) {
                _validators[validatorId].totalStaked -= userStake.amount;
                _validators[validatorId].uniqueStakers--;

                userStake.amount = 0;
                userStake.stakedAt = 0;
                userStake.mpxAmount = 0;
                userStake.lastClaimInitiatedAt = 0;
                userStake.inUnstakeProcess = false;
                userStake.lastUnstakeInitiatedAt = 0;
            }
        }

        delete _userValidators[staker];
        _userTotalStaked[staker] = 0;

        uint256 mpxAmount = PriceConverter.toMPX(_oracle, amount);

        (bool success, ) = staker.call{value: amount}("");
        if (!success) {
            revert TransferFailed();
        }

        emit EmergencyWithdrawalCompleted(staker, amount, mpxAmount);
    }

    /**
     * @dev Processes both reward claim and unstake in a single transaction
     * @param staker The address of the staker
     * @param validatorId The validator identifier
     * @param unstakeAmount The amount to unstake
     * @param rewardAmount The amount of rewards to claim
     */
    function processRewardAndUnstake(
        address staker,
        string calldata validatorId,
        uint256 unstakeAmount,
        uint256 rewardAmount
    )
        external
        payable
        virtual
        onlyRole(OPERATOR_ROLE)
        nonReentrant
        validValidatorId(validatorId)
        validatorExists(validatorId)
    {
        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );
        UserStake storage userStake = _userStakes[staker][normalizedId];

        if (!userStake.inUnstakeProcess) {
            revert NoUnstakeInProcess();
        }

        if (userStake.amount < unstakeAmount) {
            revert InsufficientStake(unstakeAmount, userStake.amount);
        }

        uint256 mpxAmountToUnstake = 0;
        if (userStake.amount > 0) {
            mpxAmountToUnstake =
                (userStake.mpxAmount * unstakeAmount) /
                userStake.amount;
        }

        if (rewardAmount > 0) {
            if (msg.value != rewardAmount) {
                revert InsufficientRewards(msg.value, rewardAmount);
            }

            emit RewardClaimed(staker, normalizedId, rewardAmount);
        }

        userStake.amount -= unstakeAmount;
        userStake.mpxAmount -= mpxAmountToUnstake;
        userStake.inUnstakeProcess = false;
        userStake.unstakeAmount = 0;

        _validators[normalizedId].totalStaked -= unstakeAmount;
        if (userStake.amount == 0) {
            _validators[normalizedId].uniqueStakers--;
            _removeValidatorFromUserList(staker, normalizedId);
        }

        _userTotalStaked[staker] -= unstakeAmount;

        emit UnstakeCompleted(
            staker,
            normalizedId,
            unstakeAmount,
            mpxAmountToUnstake
        );

        bool transferSuccess = true;

        if (rewardAmount > 0) {
            (bool rewardSuccess, ) = staker.call{value: rewardAmount}("");
            transferSuccess = rewardSuccess;
        }

        if (transferSuccess) {
            (bool unstakeSuccess, ) = staker.call{value: unstakeAmount}("");
            transferSuccess = unstakeSuccess;
        }

        if (!transferSuccess) {
            revert TransferFailed();
        }
    }
} 