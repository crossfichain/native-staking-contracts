#!/bin/bash

echo "Fixing OpenZeppelin libraries for CrossFi Native Staking..."

# Install OpenZeppelin contracts
forge install OpenZeppelin/openzeppelin-contracts --no-commit

# Install OpenZeppelin contracts upgradeable
forge install OpenZeppelin/openzeppelin-contracts-upgradeable --no-commit

# Update forge.toml remappings
cat > foundry.toml << 'EOL'
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc = "0.8.20"
remappings = [
    "@openzeppelin/contracts=lib/openzeppelin-contracts/contracts",
    "@openzeppelin/contracts-upgradeable=lib/openzeppelin-contracts-upgradeable/contracts"
]

[rpc_endpoints]
local = "http://localhost:8545"

[etherscan]
mainnet = { key = "${ETHERSCAN_API_KEY}" }

[fmt]
line_length = 120
tab_width = 4
bracket_spacing = true
EOL

echo "Library fixes completed!"
echo "You can now run 'forge build' to compile the contracts." 