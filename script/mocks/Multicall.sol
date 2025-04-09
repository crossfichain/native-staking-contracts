// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Multicall3 - Aggregate multiple contract calls into a single transaction
/// @notice A utility contract that enables batching multiple contract calls
/// @dev Implements backwards compatibility with Multicall & Multicall2
/// @custom:security-contact security@crossfi.org
contract Multicall3 {
    /*   STRUCTS   */

    /// @notice Basic call structure for backwards compatibility
    /// @param target The address of the contract to call
    /// @param callData The encoded function call data
    struct Call {
        address target;
        bytes callData;
    }

    /// @notice Enhanced call structure with failure handling
    /// @param target The address of the contract to call
    /// @param allowFailure If true, the call is allowed to fail without reverting the entire transaction
    /// @param callData The encoded function call data
    struct Call3 {
        address target;
        bool allowFailure;
        bytes callData;
    }

    /// @notice Call structure with value transfer support
    /// @param target The address of the contract to call
    /// @param allowFailure If true, the call is allowed to fail without reverting
    /// @param value The amount of ETH to send with the call
    /// @param callData The encoded function call data
    struct Call3Value {
        address target;
        bool allowFailure;
        uint256 value;
        bytes callData;
    }

    /// @notice Result structure for call execution
    /// @param success Whether the call was successful
    /// @param returnData The data returned by the call
    struct Result {
        bool success;
        bytes returnData;
    }

    constructor() {}

    /*   AGGREGATION FUNCTIONS   */

    /// @notice Executes multiple calls in a single transaction
    /// @param calls Array of calls to execute
    /// @return blockNumber Current block number
    /// @return returnData Array of results from each call
    function aggregate(
        Call[] calldata calls
    ) public payable returns (uint256 blockNumber, bytes[] memory returnData) {
        blockNumber = block.number;
        uint256 length = calls.length;
        returnData = new bytes[](length);
        Call calldata call;
        for (uint256 i = 0; i < length; ) {
            bool success;
            call = calls[i];
            (success, returnData[i]) = call.target.call(call.callData);
            require(success, "Multicall3: call failed");
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Executes calls with optional failure handling
    /// @param requireSuccess If true, reverts if any call fails
    /// @param calls Array of calls to execute
    /// @return returnData Array of results from each call
    function tryAggregate(
        bool requireSuccess,
        Call[] calldata calls
    ) public payable returns (Result[] memory returnData) {
        uint256 length = calls.length;
        returnData = new Result[](length);
        Call calldata call;
        for (uint256 i = 0; i < length; ) {
            Result memory result = returnData[i];
            call = calls[i];
            (result.success, result.returnData) = call.target.call(
                call.callData
            );
            if (requireSuccess)
                require(result.success, "Multicall3: call failed");
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Executes calls and returns block information
    /// @param requireSuccess If true, reverts if any call fails
    /// @param calls Array of calls to execute
    /// @return blockNumber Current block number
    /// @return blockHash Current block hash
    /// @return returnData Array of results
    function tryBlockAndAggregate(
        bool requireSuccess,
        Call[] calldata calls
    )
        public
        payable
        returns (
            uint256 blockNumber,
            bytes32 blockHash,
            Result[] memory returnData
        )
    {
        blockNumber = block.number;
        blockHash = blockhash(block.number);
        returnData = tryAggregate(requireSuccess, calls);
    }

    /// @notice Wrapper for tryBlockAndAggregate with required success
    /// @param calls Array of calls to execute
    /// @return blockNumber Current block number
    /// @return blockHash Current block hash
    /// @return returnData Array of results
    function blockAndAggregate(
        Call[] calldata calls
    )
        public
        payable
        returns (
            uint256 blockNumber,
            bytes32 blockHash,
            Result[] memory returnData
        )
    {
        (blockNumber, blockHash, returnData) = tryBlockAndAggregate(
            true,
            calls
        );
    }

    /// @notice Enhanced aggregation with granular failure handling
    /// @param calls Array of Call3 structs
    /// @return returnData Array of results
    function aggregate3(
        Call3[] calldata calls
    ) public payable returns (Result[] memory returnData) {
        uint256 length = calls.length;
        returnData = new Result[](length);
        Call3 calldata calli;
        for (uint256 i = 0; i < length; ) {
            Result memory result = returnData[i];
            calli = calls[i];
            (result.success, result.returnData) = calli.target.call(
                calli.callData
            );
            assembly {
                if iszero(or(calldataload(add(calli, 0x20)), mload(result))) {
                    mstore(
                        0x00,
                        0x08c379a000000000000000000000000000000000000000000000000000000000
                    )
                    mstore(
                        0x04,
                        0x0000000000000000000000000000000000000000000000000000000000000020
                    )
                    mstore(
                        0x24,
                        0x0000000000000000000000000000000000000000000000000000000000000017
                    )
                    mstore(
                        0x44,
                        0x4d756c746963616c6c333a2063616c6c206661696c6564000000000000000000
                    )
                    revert(0x00, 0x64)
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Aggregation with ETH value transfer support
    /// @param calls Array of Call3Value structs
    /// @return returnData Array of results
    function aggregate3Value(
        Call3Value[] calldata calls
    ) public payable returns (Result[] memory returnData) {
        uint256 valAccumulator;
        uint256 length = calls.length;
        returnData = new Result[](length);
        Call3Value calldata calli;
        for (uint256 i = 0; i < length; ) {
            Result memory result = returnData[i];
            calli = calls[i];
            uint256 val = calli.value;
            unchecked {
                valAccumulator += val;
            }
            (result.success, result.returnData) = calli.target.call{value: val}(
                calli.callData
            );
            assembly {
                if iszero(or(calldataload(add(calli, 0x20)), mload(result))) {
                    mstore(
                        0x00,
                        0x08c379a000000000000000000000000000000000000000000000000000000000
                    )
                    mstore(
                        0x04,
                        0x0000000000000000000000000000000000000000000000000000000000000020
                    )
                    mstore(
                        0x24,
                        0x0000000000000000000000000000000000000000000000000000000000000017
                    )
                    mstore(
                        0x44,
                        0x4d756c746963616c6c333a2063616c6c206661696c6564000000000000000000
                    )
                    revert(0x00, 0x84)
                }
            }
            unchecked {
                ++i;
            }
        }
        require(msg.value == valAccumulator, "Multicall3: value mismatch");
    }

    /*   BLOCK INFORMATION FUNCTIONS   */

    /// @notice Gets the hash of a specified block
    /// @param blockNumber The block number to get the hash for
    /// @return blockHash The hash of the specified block
    function getBlockHash(
        uint256 blockNumber
    ) public view returns (bytes32 blockHash) {
        blockHash = blockhash(blockNumber);
    }

    /// @notice Gets the current block number
    /// @return blockNumber The current block number
    function getBlockNumber() public view returns (uint256 blockNumber) {
        blockNumber = block.number;
    }

    /// @notice Gets the current block's coinbase address
    /// @return coinbase The current block's coinbase address
    function getCurrentBlockCoinbase() public view returns (address coinbase) {
        coinbase = block.coinbase;
    }

    /// @notice Gets the current block's difficulty
    /// @return difficulty The current block's difficulty
    function getCurrentBlockDifficulty()
        public
        view
        returns (uint256 difficulty)
    {
        difficulty = block.difficulty;
    }

    /// @notice Gets the current block's gas limit
    /// @return gaslimit The current block's gas limit
    function getCurrentBlockGasLimit() public view returns (uint256 gaslimit) {
        gaslimit = block.gaslimit;
    }

    /// @notice Gets the current block's timestamp
    /// @return timestamp The current block's timestamp
    function getCurrentBlockTimestamp()
        public
        view
        returns (uint256 timestamp)
    {
        timestamp = block.timestamp;
    }

    /// @notice Gets the ETH balance of a specified address
    /// @param addr The address to get the balance for
    /// @return balance The ETH balance of the address
    function getEthBalance(address addr) public view returns (uint256 balance) {
        balance = addr.balance;
    }

    /// @notice Gets the hash of the previous block
    /// @return blockHash The hash of the previous block
    function getLastBlockHash() public view returns (bytes32 blockHash) {
        unchecked {
            blockHash = blockhash(block.number - 1);
        }
    }

    /// @notice Gets the base fee of the current block
    /// @return basefee The base fee of the current block
    function getBasefee() public view returns (uint256 basefee) {
        basefee = block.basefee;
    }

    /// @notice Gets the current chain ID
    /// @return chainid The current chain ID
    function getChainId() public view returns (uint256 chainid) {
        chainid = block.chainid;
    }
}
