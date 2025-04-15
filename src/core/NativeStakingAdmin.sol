// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @notice Library imports
 */
import "../libraries/StakingUtils.sol";

/**
 * @notice Contract imports
 */
import "./NativeStakingBase.sol";

/**
 * @title NativeStakingAdmin
 * @dev Administrative functions for NativeStaking
 */
abstract contract NativeStakingAdmin is NativeStakingBase {
    /**
     * @dev Sets validator status
     * @param validatorId The validator identifier
     * @param status The validator status to set
     */
    function setValidatorStatus(
        string calldata validatorId,
        ValidatorStatus status
    ) external onlyRole(MANAGER_ROLE) validValidatorId(validatorId) {
        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );

        if (bytes(_validators[normalizedId].id).length == 0) {
            _validators[normalizedId] = Validator({
                id: normalizedId,
                status: status,
                totalStaked: 0,
                uniqueStakers: 0
            });

            _validatorIds.push(normalizedId);

            emit ValidatorAdded(
                normalizedId,
                status == ValidatorStatus.Enabled
            );
        } else {
            _validators[normalizedId].status = status;

            emit ValidatorStatusUpdated(normalizedId, status);
        }
    }

    /**
     * @dev Pauses staking functionality
     */
    function pauseStaking() external onlyRole(MANAGER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses staking functionality
     */
    function unpauseStaking() external onlyRole(MANAGER_ROLE) {
        _unpause();
    }

    /**
     * @dev Pauses unstaking functionality
     */
    function pauseUnstake() external onlyRole(MANAGER_ROLE) {
        _isUnstakePaused = true;
    }

    /**
     * @dev Unpauses unstaking functionality
     */
    function unpauseUnstake() external onlyRole(MANAGER_ROLE) {
        _isUnstakePaused = false;
    }

    /**
     * @dev Sets the Oracle address
     * @param oracleAddress Address of the oracle contract
     */
    function setOracle(
        address oracleAddress
    ) external onlyRole(MANAGER_ROLE) {
        if (oracleAddress == address(0)) {
            revert ZeroAddress();
        }
        _oracle = IOracle(oracleAddress);
    }

    /**
     * @dev Sets the minimum stake amount
     * @param amount The new minimum stake amount
     */
    function setMinimumStakeAmount(
        uint256 amount
    ) external onlyRole(MANAGER_ROLE) {
        if (amount == 0) {
            revert InvalidAmount(0, 1);
        }
        _minimumStakeAmount = amount;
    }

    /**
     * @dev Sets the minimum time between stakes
     * @param interval The new minimum interval
     */
    function setMinStakeInterval(
        uint256 interval
    ) external onlyRole(MANAGER_ROLE) {
        _minStakeInterval = interval;
    }

    /**
     * @dev Sets the minimum time before unstake
     * @param interval The new minimum interval
     */
    function setMinUnstakeInterval(
        uint256 interval
    ) external onlyRole(MANAGER_ROLE) {
        _minUnstakeInterval = interval;
    }

    /**
     * @dev Sets the minimum time before claim
     * @param interval The new minimum interval
     */
    function setMinClaimInterval(
        uint256 interval
    ) external onlyRole(MANAGER_ROLE) {
        _minClaimInterval = interval;
    }

    /**
     * @dev Sets up a validator migration
     * @param oldValidatorId The source validator identifier
     * @param newValidatorId The destination validator identifier
     */
    function setupValidatorMigration(
        string calldata oldValidatorId,
        string calldata newValidatorId
    )
        external
        onlyRole(MANAGER_ROLE)
        validValidatorId(oldValidatorId)
        validValidatorId(newValidatorId)
        validatorExists(oldValidatorId)
        validatorExists(newValidatorId)
    {
        string memory normalizedOldId = StakingUtils.normalizeValidatorId(
            oldValidatorId
        );
        string memory normalizedNewId = StakingUtils.normalizeValidatorId(
            newValidatorId
        );

        if (
            keccak256(bytes(normalizedOldId)) ==
            keccak256(bytes(normalizedNewId))
        ) {
            revert SameValidator();
        }

        _validators[normalizedOldId].status = ValidatorStatus.Deprecated;

        emit ValidatorStatusUpdated(
            normalizedOldId,
            ValidatorStatus.Deprecated
        );
    }
} 