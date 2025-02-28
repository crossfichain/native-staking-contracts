// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {NativeStaking} from "../src/NativeStaking.sol";
import {UnifiedOracle} from "../src/UnifiedOracle.sol";
import {MockDIAOracle} from "../test/mocks/MockDIAOracle.sol";
import {console} from "forge-std/console.sol";

contract DeployScript is Script {
    function setUp() public {
        // Optional: Configure RPC URLs here if needed
        // vm.createSelectFork(vm.rpcUrl("crossfi"));
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Get the current nonce
        uint64 nonce = vm.getNonce(deployer);
        console.log("Deploying with account:", deployer);
        console.log("Starting nonce:", nonce);

        // vm.startBroadcast(deployerPrivateKey);

        try this.deploy() returns (
            address mockDiaOracle,
            address unifiedOracle,
            address staking
        ) {
            console.log("Deployment successful!");
            console.log("Deployed contracts:");
            console.log("MockDIAOracle:", mockDiaOracle);
            console.log("UnifiedOracle:", unifiedOracle);
            console.log("NativeStaking:", staking);
        } catch Error(string memory reason) {
            console.log("Deployment failed!");
            console.log("Error:", reason);
        }

        // vm.stopBroadcast();
    }

    function deploy() external returns (
        address mockDiaOracle,
        address unifiedOracle,
        address staking
    ) {
        uint256 deployerPrivateKey = vm.envUint("DEV_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        // Deploy mock DIA Oracle for testing
        MockDIAOracle _mockDiaOracle = new MockDIAOracle();
        _mockDiaOracle.setPrice("XFI/USD", 1e8); // Set initial price in 8 decimals

        // Deploy UnifiedOracle
        address admin = deployer;
        UnifiedOracle _unifiedOracle = new UnifiedOracle(admin);
        _unifiedOracle.setDIAOracle(address(_mockDiaOracle));

        // Deploy NativeStaking with operator and emergency roles
        address operator = msg.sender; // Using same key for testing
        address emergency = msg.sender; // Using same key for testing
        NativeStaking _staking = new NativeStaking(
            address(_unifiedOracle),
            operator,
            emergency
        );
        vm.stopBroadcast();

        return (address(_mockDiaOracle), address(_unifiedOracle), address(_staking));
    }
} 