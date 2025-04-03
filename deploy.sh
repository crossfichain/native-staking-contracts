#!/bin/bash

# CrossFi Native Staking Deployment Script
# ========================================

# Colors for console output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if .env file exists
if [ ! -f .env ]; then
  echo -e "${RED}Error: .env file not found!${NC}"
  echo -e "Please create a .env file based on .env.example:"
  echo -e "${YELLOW}cp .env.example .env${NC}"
  echo -e "Then edit the file to set your deployment parameters."
  exit 1
fi

# Load environment variables
source .env

# Check required environment variables
REQUIRED_VARS=("PRIVATE_KEY" "ADMIN_ADDRESS" "OPERATOR_ADDRESS" "TREASURY_ADDRESS" "EMERGENCY_ADDRESS")
MISSING_VARS=()

for VAR in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!VAR}" ]; then
    MISSING_VARS+=("$VAR")
  fi
done

if [ ${#MISSING_VARS[@]} -ne 0 ]; then
  echo -e "${RED}Error: The following required environment variables are missing:${NC}"
  for VAR in "${MISSING_VARS[@]}"; do
    echo -e "  - ${VAR}"
  done
  echo -e "Please set these in your .env file."
  exit 1
fi

# Set default values if not provided
NETWORK=${NETWORK:-"development"}
PRODUCTION=${PRODUCTION:-false}
VERBOSE=${VERBOSE:-false}

# Determine RPC URL based on network
if [ "$NETWORK" == "mainnet" ]; then
  RPC_URL=$MAINNET_RPC_URL
  PRODUCTION=true
elif [ "$NETWORK" == "sepolia" ]; then
  RPC_URL=$SEPOLIA_RPC_URL
else
  RPC_URL=${RPC_URL:-"http://localhost:8545"}
fi

# Check if DIA Oracle is provided for production
if [ "$PRODUCTION" == "true" ] && [ -z "$DIA_ORACLE_ADDRESS" ]; then
  echo -e "${RED}Error: Production deployment requires DIA_ORACLE_ADDRESS to be set.${NC}"
  echo -e "Please set DIA_ORACLE_ADDRESS in your .env file."
  exit 1
fi

# Set verbosity for forge
if [ "$VERBOSE" == "true" ]; then
  VERBOSITY="-vvvv"
else
  VERBOSITY="-vv"
fi

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}   CrossFi Native Staking Deployment Script     ${NC}"
echo -e "${BLUE}================================================${NC}"
echo
echo -e "Network:       ${YELLOW}$NETWORK${NC}"
echo -e "Production:    ${YELLOW}$PRODUCTION${NC}"
echo -e "RPC URL:       ${YELLOW}$RPC_URL${NC}"
echo -e "Admin Address: ${YELLOW}$ADMIN_ADDRESS${NC}"
echo -e "Operator:      ${YELLOW}$OPERATOR_ADDRESS${NC}"
echo
echo -e "${GREEN}Starting deployment...${NC}"
echo

# Step 1: Deploy using Master Deployment Script
echo -e "${YELLOW}Step 1/3: Deploying contracts...${NC}"
forge script script/deployment/MasterDeployment.s.sol:MasterDeployment \
  --rpc-url $RPC_URL \
  --broadcast \
  $VERBOSITY \
  -o deployLogs

DEPLOY_EXIT_CODE=$?
if [ $DEPLOY_EXIT_CODE -ne 0 ]; then
  echo -e "${RED}Deployment failed with exit code $DEPLOY_EXIT_CODE${NC}"
  exit $DEPLOY_EXIT_CODE
fi

echo -e "${GREEN}Deployment completed successfully!${NC}"
echo

# Step 2: Verify Deployment
echo -e "${YELLOW}Step 2/3: Verifying deployment...${NC}"
forge script script/deployment/VerifyDeployment.s.sol:VerifyDeployment \
  --rpc-url $RPC_URL \
  $VERBOSITY

VERIFY_EXIT_CODE=$?
if [ $VERIFY_EXIT_CODE -ne 0 ]; then
  echo -e "${RED}Verification failed with exit code $VERIFY_EXIT_CODE${NC}"
  echo -e "This may indicate issues with the deployment."
  echo -e "Check the error message above for details."
  exit $VERIFY_EXIT_CODE
fi

echo -e "${GREEN}Verification completed successfully!${NC}"
echo

# Step 3: Post-Deployment Setup
echo -e "${YELLOW}Step 3/3: Running post-deployment setup...${NC}"
forge script script/deployment/PostDeploymentSetup.s.sol:PostDeploymentSetup \
  --rpc-url $RPC_URL \
  --broadcast \
  $VERBOSITY

SETUP_EXIT_CODE=$?
if [ $SETUP_EXIT_CODE -ne 0 ]; then
  echo -e "${RED}Post-deployment setup failed with exit code $SETUP_EXIT_CODE${NC}"
  echo -e "This may indicate issues with role assignment or configuration."
  echo -e "Check the error message above for details."
  exit $SETUP_EXIT_CODE
fi

echo -e "${GREEN}Post-deployment setup completed successfully!${NC}"
echo

# All steps completed successfully
echo -e "${BLUE}================================================${NC}"
echo -e "${GREEN}All deployment steps completed successfully!${NC}"
echo -e "${BLUE}================================================${NC}"
echo
echo -e "Deployment data has been saved to the deployments directory."
echo -e "You can find the addresses in deployments/$NETWORK-deployment.csv"
echo
echo -e "${YELLOW}Next steps:${NC}"
echo -e "1. Update your .env file with the deployed contract addresses"
echo -e "2. Verify contracts on the block explorer"
echo -e "3. Set up monitoring for the deployed contracts"
echo

exit 0 