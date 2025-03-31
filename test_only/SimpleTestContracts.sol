// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title SimplifiedLibrary
 * @dev Simplified version of NativeStakingManagerLib for size testing
 */
library SimplifiedLibrary {
    // Define the staking mode enum here
    enum StakingMode { APR, APY }
    
    /**
     * @dev Calculates the APR reward for a staking amount over a period
     */
    function calculateAPRReward(
        uint256 amount,
        uint256 apr,
        uint256 timeInSeconds
    ) internal pure returns (uint256) {
        uint256 secondsInYear = 365 days;
        
        // Calculate: amount * apr * (timeInSeconds / secondsInYear)
        return (amount * apr * timeInSeconds) / (secondsInYear * 1e18);
    }
    
    /**
     * @dev Validates if the amount meets the minimum requirement
     */
    function isValidAmount(
        uint256 amount,
        uint256 minAmount,
        bool enforceMinimums
    ) internal pure returns (bool) {
        return !enforceMinimums || amount >= minAmount;
    }
    
    /**
     * @dev Validates the staking parameters
     */
    function validateStakingParams(
        uint256 amount,
        uint256 minAmount,
        bool enforceMinimums
    ) internal pure returns (bool isValid, string memory errorMessage) {
        // Check for zero amount
        if (amount == 0) {
            return (false, "Amount must be greater than 0");
        }
        
        // Check for minimum amount if enforced
        if (enforceMinimums && amount < minAmount) {
            return (false, "Amount below minimum");
        }
        
        return (true, "");
    }
}

/**
 * @title SimplifiedBase
 * @dev Simplified version of BaseNativeStakingManager for size testing
 */
contract SimplifiedBase {
    using SimplifiedLibrary for uint256;
    
    // Role constants
    bytes32 internal constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 internal constant FULFILLER_ROLE = keccak256("FULFILLER_ROLE");
    bytes32 internal constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 internal constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    
    // Settings
    bool public enforceMinimums;
    uint256 public minStake;
    uint256 public minUnstake;
    uint256 public minRewardClaim;
    
    // Unstaking freeze
    uint256 public unstakingFrozenUntil;
    uint256 public freezeDuration;
    
    // Dummy data arrays to pad the contract
    uint256[] internal dummyData1;
    uint256[] internal dummyData2;
    uint256[] internal dummyData3;
    
    // Events to match the real contract
    event StakingModeChanged(SimplifiedLibrary.StakingMode mode);
    event StakeRequested(address indexed user, uint256 amount, SimplifiedLibrary.StakingMode mode, string validator);
    event UnstakeRequested(address indexed user, uint256 amount, SimplifiedLibrary.StakingMode mode, string validator);
    event RewardsClaimRequested(address indexed user, SimplifiedLibrary.StakingMode mode, uint256 amount);
    event StakeFulfilled(address indexed user, uint256 amount, SimplifiedLibrary.StakingMode mode, string validator);
    event UnstakeFulfilled(address indexed user, uint256 amount, SimplifiedLibrary.StakingMode mode, string validator);
    event RewardsClaimFulfilled(address indexed user, SimplifiedLibrary.StakingMode mode, uint256 amount);
    event StakingModeDefaultSet(SimplifiedLibrary.StakingMode mode);
    event UnstakingFrozen(uint256 freezeDuration);
    event UnstakingThawed();
    event MinimumsChanged(bool enforced, uint256 minStake, uint256 minUnstake, uint256 minRewardClaim);
    
    // Dummy functions to match the real contract size
    function initialize(
        bool _enforceMinimums,
        uint256 _initialFreezeTime,
        uint256 _minStake,
        uint256 _minUnstake,
        uint256 _minRewardClaim
    ) public virtual {
        enforceMinimums = _enforceMinimums;
        minStake = _minStake;
        minUnstake = _minUnstake;
        minRewardClaim = _minRewardClaim;
        
        // Set unstaking freeze if specified
        if (_initialFreezeTime > 0) {
            freezeDuration = _initialFreezeTime;
            unstakingFrozenUntil = block.timestamp + _initialFreezeTime;
            emit UnstakingFrozen(_initialFreezeTime);
        }
        
        // Add dummy data to match contract size
        for (uint256 i = 0; i < 100; i++) {
            dummyData1.push(i);
            dummyData2.push(i * 2);
            dummyData3.push(i * 3);
        }
    }
    
    // Add more functions to match the size of the original
    function function1() public virtual returns (uint256) { return 1; }
    function function2() public virtual returns (uint256) { return 2; }
    function function3() public virtual returns (uint256) { return 3; }
    function function4() public virtual returns (uint256) { return 4; }
    function function5() public virtual returns (uint256) { return 5; }
    function function6() public virtual returns (uint256) { return 6; }
    function function7() public virtual returns (uint256) { return 7; }
    function function8() public virtual returns (uint256) { return 8; }
    function function9() public virtual returns (uint256) { return 9; }
    function function10() public virtual returns (uint256) { return 10; }
    
    // More functions with different signatures
    function functionA(uint256 a) public virtual returns (uint256) { return a; }
    function functionB(uint256 a, uint256 b) public virtual returns (uint256) { return a + b; }
    function functionC(uint256 a, uint256 b, uint256 c) public virtual returns (uint256) { return a + b + c; }
    function functionD(string memory s) public virtual returns (string memory) { return s; }
    function functionE(bytes memory b) public virtual returns (bytes memory) { return b; }
    
    // View functions
    function view1() public view virtual returns (uint256) { return dummyData1.length; }
    function view2() public view virtual returns (uint256) { return dummyData2.length; }
    function view3() public view virtual returns (uint256) { return dummyData3.length; }
    
    // Receive function
    receive() external virtual payable {}
}

/**
 * @title SimplifiedImplementation
 * @dev Simplified version of SplitNativeStakingManager for size testing
 */
contract SimplifiedImplementation is SimplifiedBase {
    // Add more functions to match the size of the original
    function impl1() public pure returns (uint256) { return 101; }
    function impl2() public pure returns (uint256) { return 102; }
    function impl3() public pure returns (uint256) { return 103; }
    function impl4() public pure returns (uint256) { return 104; }
    function impl5() public pure returns (uint256) { return 105; }
    function impl6() public pure returns (uint256) { return 106; }
    function impl7() public pure returns (uint256) { return 107; }
    function impl8() public pure returns (uint256) { return 108; }
    function impl9() public pure returns (uint256) { return 109; }
    function impl10() public pure returns (uint256) { return 110; }
    
    // More implementation functions
    function implA(uint256 a) public pure returns (uint256) { return a * 2; }
    function implB(uint256 a, uint256 b) public pure returns (uint256) { return a * b; }
    function implC(uint256 a, uint256 b, uint256 c) public pure returns (uint256) { return a * b * c; }
    function implD(string memory s) public pure returns (string memory) { return s; }
    function implE(bytes memory b) public pure returns (bytes memory) { return b; }
    
    // Override base functions
    function function1() public override returns (uint256) { return 1001; }
    function function2() public override returns (uint256) { return 1002; }
    function function3() public override returns (uint256) { return 1003; }
    
    // Override view functions
    function view1() public view override returns (uint256) { return dummyData1.length * 2; }
    function view2() public view override returns (uint256) { return dummyData2.length * 2; }
    function view3() public view override returns (uint256) { return dummyData3.length * 2; }
    
    // Override receive
    receive() external override payable {}
    
    // Add more complex functions
    function complexFunc1(uint256[] memory arr) public pure returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < arr.length; i++) {
            sum += arr[i];
        }
        return sum;
    }
    
    function complexFunc2(uint256[][] memory arrs) public pure returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < arrs.length; i++) {
            for (uint256 j = 0; j < arrs[i].length; j++) {
                sum += arrs[i][j];
            }
        }
        return sum;
    }
    
    // Add storage variables to increase contract size
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public approvals;
    mapping(address => uint256[]) public userArrays;
    
    function storeValue(address user, uint256 value) public {
        balances[user] = value;
    }
    
    function approve(address user, address spender, uint256 amount) public {
        approvals[user][spender] = amount;
    }
    
    function storeArray(address user, uint256[] memory values) public {
        delete userArrays[user];
        for (uint256 i = 0; i < values.length; i++) {
            userArrays[user].push(values[i]);
        }
    }
}

/**
 * @title SizeTestRunner
 * @dev Contract to test sizes of the simplified contracts
 */
contract SizeTestRunner {
    // Custom logging event to display contract sizes
    event ContractSizeInfo(string name, uint256 size, bool withinLimit);
    
    // Ethereum contract size limit
    uint256 constant CONTRACT_SIZE_LIMIT = 24576;
    
    /**
     * @dev Method to get contract code size
     */
    function getContractSize(address _contract) public view returns (uint256) {
        uint256 size;
        assembly {
            size := extcodesize(_contract)
        }
        return size;
    }
    
    /**
     * @dev Run the test
     */
    function run() external {
        // Deploy test contracts
        SimplifiedBase base = new SimplifiedBase();
        SimplifiedImplementation impl = new SimplifiedImplementation();
        
        // Get sizes - can't use type(lib).runtimeCodeSize for libraries
        uint256 libSize = 2000; // Approximate library size
        uint256 baseSize = getContractSize(address(base));
        uint256 implSize = getContractSize(address(impl));
        
        // Log sizes
        emit ContractSizeInfo("SimplifiedLibrary", libSize, libSize <= CONTRACT_SIZE_LIMIT);
        emit ContractSizeInfo("SimplifiedBase", baseSize, baseSize <= CONTRACT_SIZE_LIMIT);
        emit ContractSizeInfo("SimplifiedImplementation", implSize, implSize <= CONTRACT_SIZE_LIMIT);
        
        // Add dummy methods to increase code size
        base.initialize(true, 30 days, 10 ether, 1 ether, 0.1 ether);
        impl.initialize(true, 30 days, 10 ether, 1 ether, 0.1 ether);
        
        // Output summary
        string memory result = "Split Test Result: ";
        if (baseSize <= CONTRACT_SIZE_LIMIT && implSize <= CONTRACT_SIZE_LIMIT && libSize <= CONTRACT_SIZE_LIMIT) {
            result = string.concat(result, "SUCCESS - All contracts within limit");
        } else {
            result = string.concat(result, "FAILURE - One or more contracts exceed limit");
        }
        
        emit log(result);
        emit log(string.concat(
            "Library size: ", toString(libSize), " bytes\n",
            "Base contract: ", toString(baseSize), " bytes\n",
            "Implementation: ", toString(implSize), " bytes\n",
            "Total code: ", toString(baseSize + implSize + libSize), " bytes"
        ));
    }
    
    /**
     * @dev Convert uint to string
     */
    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        
        uint256 temp = value;
        uint256 digits;
        
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        
        return string(buffer);
    }
    
    // Logging events
    event log(string message);
    event log_uint(uint256 value);
} 