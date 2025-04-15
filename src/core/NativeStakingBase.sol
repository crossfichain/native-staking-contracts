// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @notice External imports
 */
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @notice Interface imports
 */
import "../interfaces/INativeStaking.sol";
import "../interfaces/IOracle.sol";

/**
 * @notice Library imports
 */
import "../libraries/StakingUtils.sol";

/**
 * @title NativeStakingBase
 * @dev Base contract with state variables, storage, and modifiers for NativeStaking
 */
abstract contract NativeStakingBase is
    Initializable,
    INativeStaking,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    /**
     * @dev State variables
     */
    // Role definitions
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // Bond duration constant
    uint256 public constant AVG_BOND_DURATION = 15 days;

    // Oracle contract for price conversion
    IOracle internal _oracle;

    // Validator mappings
    mapping(string => Validator) internal _validators;
    string[] internal _validatorIds;

    // User stake mappings
    mapping(address user => mapping(string validatorId => UserStake))
        internal _userStakes;
    mapping(address user => string[] validators) internal _userValidators;
    mapping(address user => uint256 totalStaked) internal _userTotalStaked;
    mapping(address user => bool emergencyWithdrawalRequested)
        internal _emergencyWithdrawalRequested;

    // Time-based restrictions
    uint256 internal _minStakeInterval;
    uint256 internal _minUnstakeInterval;
    uint256 internal _minClaimInterval;
    bool internal _isUnstakePaused;

    // Contract settings
    uint256 internal _minimumStakeAmount;
    uint256 internal _minClaimAmount;

    /**
     * @dev Initializes the contract base state
     * @param admin Address of the admin who will have DEFAULT_ADMIN_ROLE
     * @param minimumStakeAmount The minimum amount required for staking
     * @param oracle Address of the oracle for price conversions
     */
    function __NativeStakingBase_init(
        address admin,
        uint256 minimumStakeAmount,
        address oracle
    ) internal onlyInitializing {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, admin);

        _minimumStakeAmount = minimumStakeAmount;
        _oracle = IOracle(oracle);

        _minStakeInterval = 1 days;
        _minUnstakeInterval = 1 days;
        _minClaimInterval = 1 days;
    }

    /**
     * @dev Utility function to remove validator from user's list
     */
    function _removeValidatorFromUserList(
        address staker,
        string memory validatorId
    ) internal virtual {
        string[] storage userValidators = _userValidators[staker];

        for (uint256 i = 0; i < userValidators.length; i++) {
            if (
                keccak256(bytes(userValidators[i])) ==
                keccak256(bytes(validatorId))
            ) {
                userValidators[i] = userValidators[userValidators.length - 1];
                userValidators.pop();
                break;
            }
        }
    }

    /**
     * @dev Modifiers
     */

    /**
     * @dev Modifier to check if validator ID is valid
     */
    modifier validValidatorId(string calldata validatorId) {
        if (!StakingUtils.validateValidatorId(validatorId)) {
            revert InvalidValidatorId(validatorId);
        }
        _;
    }

    /**
     * @dev Modifier to check if validator exists and is enabled
     */
    modifier validatorEnabled(string calldata validatorId) {
        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );
        if (bytes(_validators[normalizedId].id).length == 0) {
            revert ValidatorDoesNotExist(normalizedId);
        }
        if (_validators[normalizedId].status != ValidatorStatus.Enabled) {
            revert ValidatorNotEnabled(normalizedId);
        }
        _;
    }

    /**
     * @dev Modifier to check if validator exists
     */
    modifier validatorExists(string calldata validatorId) {
        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );
        if (bytes(_validators[normalizedId].id).length == 0) {
            revert ValidatorDoesNotExist(normalizedId);
        }
        _;
    }

    /**
     * @dev Modifier to check if enough time has passed since last stake and last unstake
     */
    modifier stakeTimeRestriction(string calldata validatorId) {
        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );
        UserStake storage userStake = _userStakes[msg.sender][normalizedId];
        if (userStake.stakedAt > 0) {
            if (block.timestamp < userStake.stakedAt + _minStakeInterval) {
                revert TimeTooShort(
                    _minStakeInterval,
                    block.timestamp - userStake.stakedAt
                );
            }
        }
        if (block.timestamp < userStake.lastUnstakeInitiatedAt + _minStakeInterval) {
            revert TimeTooShort(
                _minStakeInterval,
                block.timestamp - userStake.lastUnstakeInitiatedAt
            );
        }
        _;
    }

    /**
     * @dev Modifier to check if enough time has passed since last stake to allow unstake
     */
    modifier unstakeTimeRestriction(string calldata validatorId) {
        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );
        UserStake storage userStake = _userStakes[msg.sender][normalizedId];
        if (userStake.amount == 0) {
            revert NoStakeFound();
        }
        if (block.timestamp < userStake.stakedAt + _minUnstakeInterval) {
            revert TimeTooShort(
                _minUnstakeInterval,
                block.timestamp - userStake.stakedAt
            );
        }

        uint256 lastTimeCheck = userStake.lastUnstakeInitiatedAt > 0
            ? userStake.lastUnstakeInitiatedAt
            : userStake.stakedAt;
        if (block.timestamp < lastTimeCheck + _minUnstakeInterval) {
            revert TimeTooShort(
                _minUnstakeInterval,
                block.timestamp - lastTimeCheck
            );
        }
        _;
    }

    /**
     * @dev Modifier to check if enough time has passed since last stake, last unstake or last claim to allow reward claim
     */
    modifier claimTimeRestriction(string calldata validatorId) {
        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );
        UserStake storage userStake = _userStakes[msg.sender][normalizedId];
        if (userStake.amount == 0) {
            revert NoStakeFound();
        }
        if (block.timestamp < userStake.stakedAt + _minClaimInterval) {
            revert TimeTooShort(
                _minClaimInterval,
                block.timestamp - userStake.stakedAt
            );
        }

        uint256 lastTimeCheck = userStake.lastUnstakeInitiatedAt > 0
            ? userStake.lastUnstakeInitiatedAt
            : userStake.stakedAt;
        if (block.timestamp < lastTimeCheck + _minClaimInterval) {
            revert TimeTooShort(
                _minClaimInterval,
                block.timestamp - lastTimeCheck
            );
        }

        lastTimeCheck = userStake.lastClaimInitiatedAt > 0
            ? userStake.lastClaimInitiatedAt
            : userStake.stakedAt;
        if (block.timestamp < lastTimeCheck + _minClaimInterval) {
            revert TimeTooShort(
                _minClaimInterval,
                block.timestamp - lastTimeCheck
            );
        }
        _;
    }

    /**
     * @dev Modifier to prevent actions on stake with active unstake process
     */
    modifier notInUnstakeProcess(string calldata validatorId) {
        string memory normalizedId = StakingUtils.normalizeValidatorId(
            validatorId
        );
        UserStake storage userStake = _userStakes[msg.sender][normalizedId];
        if (userStake.inUnstakeProcess) {
            revert UnstakeInProcess();
        }
        _;
    }
} 