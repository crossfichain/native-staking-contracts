#!/bin/bash

# Colors for console output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default to localhost if no RPC URL provided
NETWORK=${1:-"crossfi_dev"}
VERIFY=${2:-"true"}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   CrossFi Native Staking Deployment   ${NC}"
echo -e "${BLUE}========================================${NC}"
echo
echo -e "Network: ${YELLOW}$NETWORK${NC}"
echo -e "Verify:  ${YELLOW}$VERIFY${NC}"
echo

# Create the deployments directory
mkdir -p deployments

# Build the verification flag
VERIFY_FLAG=""
if [ "$VERIFY" == "true" ]; then
  VERIFY_FLAG="--verify"
  echo -e "${YELLOW}Contract verification is enabled.${NC}"
fi

# Run the deployment script
echo -e "${GREEN}Running deployment...${NC}"
forge script script/dev/SimpleDeploy.s.sol:SimpleDeploy --rpc-url $NETWORK --broadcast -vvv $VERIFY_FLAG --delay 5 --slow

# Check if it was successful
if [ $? -eq 0 ]; then
  echo -e "${GREEN}Deployment completed successfully!${NC}"
  echo 
  echo -e "You can load the environment variables with:"
  echo -e "${YELLOW}source deployments/dev.env${NC}"
  echo
else
  echo -e "${RED}Deployment failed. Check the error messages above.${NC}"
  exit 1
fi 