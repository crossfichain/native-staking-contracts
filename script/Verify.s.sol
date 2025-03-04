// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.26;

// import {Script} from "forge-std/Script.sol";
// import {NativeStaking} from "../src/core/NativeStaking.sol";
// import {CrossFiOracle} from "../src/periphery/CrossFiOracle.sol";
// import {MockDIAOracle} from "../test/mocks/MockDIAOracle.sol";
// import {console} from "forge-std/console.sol";

// contract VerifyScript is Script {
//     function run() external {
//         // Addresses from the deployment (replace with your actual deployed addresses)
//         address mockDiaOracle = 0x6BB7eb1996a1F2EdF073886d08d81e3b29f50DfE;
//         address oracle = 0x619Fa7497172Fb48E77B845577c4e83FDFE15490;
//         address staking = 0xDbe735426C7DC01F0F153F9C769582a3b48784EC;

//         // Get constructor arguments
//         address deployer = vm.addr(vm.envUint("DEV_PRIVATE_KEY"));
//         address operator = deployer;
//         address emergency = deployer;

//         // Verify each contract
//         string memory verifyMockDiaOracle = string.concat(
//             "forge verify-contract ",
//             vm.toString(mockDiaOracle),
//             " test/mocks/MockDIAOracle.sol:MockDIAOracle",
//             " --chain-id 4156",
//             " --verifier-url $CROSSFI_VERIFIER_URL",
//             " --compiler-version v0.8.20+commit.a1b79de6"
//         );

//         string memory verifyOracle = string.concat(
//             "forge verify-contract ",
//             vm.toString(oracle),
//             " src/periphery/CrossFiOracle.sol:CrossFiOracle",
//             " --chain-id 4156",
//             " --verifier-url $CROSSFI_VERIFIER_URL",
//             " --compiler-version v0.8.20+commit.a1b79de6",
//             " --constructor-args ",
//             vm.toString(abi.encode(deployer))
//         );

//         string memory verifyStaking = string.concat(
//             "forge verify-contract ",
//             vm.toString(staking),
//             " src/core/NativeStaking.sol:NativeStaking",
//             " --chain-id 4156",
//             " --verifier-url $CROSSFI_VERIFIER_URL",
//             " --compiler-version v0.8.20+commit.a1b79de6",
//             " --constructor-args ",
//             vm.toString(abi.encode(oracle, operator, emergency))
//         );

//         console.log("Verification commands:");
//         console.log("MockDIAOracle:", verifyMockDiaOracle);
//         console.log("\nCrossFiOracle:", verifyOracle);
//         console.log("\nNativeStaking:", verifyStaking);
//     }
// } 