// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import "../src/core/NativeStaking.sol";
import "../src/periphery/UnifiedOracle.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MockDIAOracle} from "./mocks/MockDiaOracle.sol";

/**
 * @title DeployNativeStakingDev
 * @dev Script to deploy the NativeStaking contracts for development environment
 */
contract DeployNativeStakingDev is Script {
    /**
     * @dev Role addresses
     */
    address constant ADMIN_ADDRESS = 0x2D2bA91B7c0EA2dB570a5Df61304B690FD1A3918;
    address constant MANAGER_ADDRESS = 0x1C89357aF4f15B351F1Ba8a478d944DFa3f45715;
    address constant OPERATOR_ADDRESS = 0x6Ff2Da7EB2DF14dB66f3F25a0AcE6a28e5f15CD9;

    /**
     * @dev Default values for delays (30 seconds for testing)
     */
    uint256 constant MIN_STAKE_INTERVAL = 30;
    uint256 constant MIN_UNSTAKE_INTERVAL = 30;
    uint256 constant MIN_CLAIM_INTERVAL = 30;
    
    /**
     * @dev Minimum stake amount 
     */
    uint256 constant MINIMUM_STAKE_AMOUNT = 1 ether; // 1 XFI

    /**
     * @dev List of validator IDs to initialize
     */
    string[] validatorIds;

    /**
     * @dev Constructor to initialize validator IDs
     */
    constructor() {
        validatorIds.push("mxvaloper1gza5y94kal25eawsenl56th8kdyujszmcsxcgs");
        validatorIds.push("mxvaloper1jp0m7ynwtvrknzlmdzargmd59mh8n9gkh9yfwm");
        validatorIds.push("mxvaloper1rfza8qfktwy46ujrundtx5s5th6dq8vfnwscp3");
        validatorIds.push("mxvaloper12w023r3vjjmhk8nss9u59np22mjsj8ykwrlxs7");
        validatorIds.push("mxvaloper1zgrx9jjqrfye8swylcmrxq3k92e9j872s9amqu");
        validatorIds.push("mxvaloper1kjr5gh0w3hrxw9r7e4pjw6vz5kywupm79t58n4");
        validatorIds.push("mxvaloper1lthswtdl3dzkppq3ee3kn4jm6dkxdp79t8xq63");
        validatorIds.push("mxvaloper1w0m48j6zejl65pwrt8d8f88jdsjfpne4g7qr5j");
        validatorIds.push("mxvaloper1qj452fr5c8r59dtv5ullke776e07x5pk6umlh4");
        validatorIds.push("mxvaloper1wsgm3jlgcxq7vftldz7hfmwfgq98hruj9yjgr5");
    }

    /**
     * @dev Main deployment function
     */
    function run() public {
        uint256 deployerKey = vm.envUint("DEV_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerKey);
        console.log("Deployer address:", deployerAddress);

        uint256 minStakeInterval = vm.envOr("MIN_STAKE_INTERVAL", MIN_STAKE_INTERVAL);
        uint256 minUnstakeInterval = vm.envOr("MIN_UNSTAKE_INTERVAL", MIN_UNSTAKE_INTERVAL);
        uint256 minClaimInterval = vm.envOr("MIN_CLAIM_INTERVAL", MIN_CLAIM_INTERVAL);

        vm.startBroadcast(deployerKey);

        console.log("Deploying MockDiaOracle...");
        MockDIAOracle mockDiaOracle = new MockDIAOracle();
        console.log("MockDiaOracle deployed at:", address(mockDiaOracle));

        uint128 xfiPrice = 9_000_0000; // $0.90 with 8 decimals
        mockDiaOracle.setPrice("XFI/USD", xfiPrice);
        console.log("Set XFI price to:", xfiPrice);

        console.log("Deploying Oracle implementation...");
        UnifiedOracle oracleImpl = new UnifiedOracle();
        console.log("Oracle implementation deployed at:", address(oracleImpl));

        console.log("Deploying NativeStaking implementation...");
        NativeStaking nativeStakingImpl = new NativeStaking();
        console.log("NativeStaking implementation deployed at:", address(nativeStakingImpl));

        console.log("Deploying ProxyAdmin...");
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        console.log("ProxyAdmin deployed at:", address(proxyAdmin));

        console.log("Deploying Oracle Proxy...");
        bytes memory oracleInitData = abi.encodeWithSelector(
            UnifiedOracle.initialize.selector,
            address(mockDiaOracle),
            deployerAddress
        );
        TransparentUpgradeableProxy oracleProxy = new TransparentUpgradeableProxy(
            address(oracleImpl),
            address(proxyAdmin),
            oracleInitData
        );
        console.log("Oracle Proxy deployed at:", address(oracleProxy));

        UnifiedOracle oracle = UnifiedOracle(address(oracleProxy));
        
        uint256 xfiPriceInOracle = 9 * 10**16; // $0.09 with 18 decimals
        oracle.setPrice("XFI", xfiPriceInOracle);
        console.log("Set XFI fallback price in Oracle to:", xfiPriceInOracle);

        console.log("Deploying NativeStaking Proxy...");
        bytes memory nativeStakingInitData = abi.encodeWithSelector(
            NativeStaking.initialize.selector,
            deployerAddress,
            MINIMUM_STAKE_AMOUNT,
            address(oracle)
        );
        TransparentUpgradeableProxy nativeStakingProxy = new TransparentUpgradeableProxy(
            address(nativeStakingImpl),
            address(proxyAdmin),
            nativeStakingInitData
        );
        console.log("NativeStaking Proxy deployed at:", address(nativeStakingProxy));

        NativeStaking nativeStaking = NativeStaking(payable(address(nativeStakingProxy)));
        
        nativeStaking.setMinStakeInterval(minStakeInterval);
        console.log("Set min stake interval to:", minStakeInterval);
        
        nativeStaking.setMinUnstakeInterval(minUnstakeInterval);
        console.log("Set min unstake interval to:", minUnstakeInterval);
        
        nativeStaking.setMinClaimInterval(minClaimInterval);
        console.log("Set min claim interval to:", minClaimInterval);

        uint256 mpxPrice = 2 * 10**16; // $0.02 with 18 decimals
        oracle.setMPXPrice(mpxPrice);
        console.log("Set MPX price to:", mpxPrice);

        bytes32 managerRole = nativeStaking.MANAGER_ROLE();
        bytes32 operatorRole = nativeStaking.OPERATOR_ROLE();
        bytes32 adminRole = nativeStaking.DEFAULT_ADMIN_ROLE();
        
        console.log("Granting roles to addresses...");
        
        nativeStaking.grantRole(managerRole, ADMIN_ADDRESS);
        nativeStaking.grantRole(managerRole, MANAGER_ADDRESS);
        nativeStaking.grantRole(managerRole, OPERATOR_ADDRESS);
        
        nativeStaking.grantRole(operatorRole, ADMIN_ADDRESS);
        nativeStaking.grantRole(operatorRole, MANAGER_ADDRESS);
        nativeStaking.grantRole(operatorRole, OPERATOR_ADDRESS);
        
        nativeStaking.grantRole(adminRole, ADMIN_ADDRESS);
        nativeStaking.grantRole(adminRole, MANAGER_ADDRESS);
        nativeStaking.grantRole(adminRole, OPERATOR_ADDRESS);

        oracle.grantRole(oracle.DEFAULT_ADMIN_ROLE(), ADMIN_ADDRESS);
        oracle.grantRole(oracle.DEFAULT_ADMIN_ROLE(), MANAGER_ADDRESS);
        oracle.grantRole(oracle.DEFAULT_ADMIN_ROLE(), OPERATOR_ADDRESS);
        
        oracle.grantRole(oracle.ORACLE_UPDATER_ROLE(), ADMIN_ADDRESS);
        oracle.grantRole(oracle.ORACLE_UPDATER_ROLE(), MANAGER_ADDRESS);
        oracle.grantRole(oracle.ORACLE_UPDATER_ROLE(), OPERATOR_ADDRESS);

        nativeStaking.grantRole(nativeStaking.DEFAULT_ADMIN_ROLE(), ADMIN_ADDRESS);
        nativeStaking.grantRole(nativeStaking.DEFAULT_ADMIN_ROLE(), MANAGER_ADDRESS);
        nativeStaking.grantRole(nativeStaking.DEFAULT_ADMIN_ROLE(), OPERATOR_ADDRESS);

        console.log("Adding validators...");
        for (uint i = 0; i < validatorIds.length; i++) {
            nativeStaking.setValidatorStatus(validatorIds[i], INativeStaking.ValidatorStatus.Enabled);
            console.log("Added validator:", validatorIds[i]);
        }
        console.log("Added all validators. Count:", validatorIds.length);

        console.log("\n--- Deployment Summary ---");
        console.log("MockDiaOracle address:", address(mockDiaOracle));
        console.log("Oracle implementation address:", address(oracleImpl));
        console.log("NativeStaking implementation address:", address(nativeStakingImpl));
        console.log("ProxyAdmin address:", address(proxyAdmin));
        console.log("Oracle Proxy address:", address(oracleProxy));
        console.log("NativeStaking Proxy address:", address(nativeStakingProxy));
        console.log("Admin address:", ADMIN_ADDRESS);
        console.log("Manager address:", MANAGER_ADDRESS);
        console.log("Operator address:", OPERATOR_ADDRESS);
        console.log("Min stake interval:", minStakeInterval);
        console.log("Min unstake interval:", minUnstakeInterval);
        console.log("Min claim interval:", minClaimInterval);
        console.log("Minimum stake amount:", MINIMUM_STAKE_AMOUNT);
        console.log("XFI price (8 decimals):", xfiPrice);
        console.log("MPX price (18 decimals):", mpxPrice);
        console.log("Number of validators:", validatorIds.length);
        console.log("-------------------------");

        vm.stopBroadcast();
    }
}





