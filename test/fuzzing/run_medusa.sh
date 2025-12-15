#!/bin/bash
# Run Medusa fuzzing on Noma Protocol
# Usage: ./run_medusa.sh [harness]
#   harness: VaultSolvencyFuzz (default), LendingFuzz, StakingFuzz, TokenFuzz

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default values
HARNESS="${1:-VaultSolvencyFuzz}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Noma Protocol Medusa Fuzzing${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if medusa is installed
if ! command -v medusa &> /dev/null; then
    echo -e "${RED}Error: medusa is not installed${NC}"
    echo "Install from: https://github.com/crytic/medusa"
    echo "  go install github.com/crytic/medusa@latest"
    exit 1
fi

# Check if forge is available for compilation
if ! command -v forge &> /dev/null; then
    echo -e "${RED}Error: forge (foundry) is not installed${NC}"
    exit 1
fi

# Check if fork is running
echo -e "${YELLOW}Checking if forked chain is running on localhost:8545...${NC}"
if ! curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    http://localhost:8545 > /dev/null 2>&1; then
    echo -e "${RED}Error: No RPC endpoint found at localhost:8545${NC}"
    echo "Start the forked chain first with:"
    echo "  anvil --fork-url <YOUR_RPC_URL>"
    exit 1
fi
echo -e "${GREEN}Fork detected!${NC}"
echo ""

# Build contracts first
echo -e "${YELLOW}Building contracts...${NC}"
cd "$PROJECT_ROOT"
forge build --silent

# Map harness name to contract
case "$HARNESS" in
    "VaultSolvencyFuzz"|"vault"|"solvency")
        TARGET_CONTRACT="VaultSolvencyFuzz"
        ;;
    "LendingFuzz"|"lending")
        TARGET_CONTRACT="LendingFuzz"
        ;;
    "StakingFuzz"|"staking")
        TARGET_CONTRACT="StakingFuzz"
        ;;
    "TokenFuzz"|"token")
        TARGET_CONTRACT="TokenFuzz"
        ;;
    *)
        echo -e "${RED}Unknown harness: $HARNESS${NC}"
        echo "Available: VaultSolvencyFuzz, LendingFuzz, StakingFuzz, TokenFuzz"
        exit 1
        ;;
esac

# Update medusa.json with target contract
cd "$SCRIPT_DIR"
TMP_CONFIG=$(mktemp)
jq --arg contract "$TARGET_CONTRACT" \
   '.fuzzing.deploymentOrder = [$contract] | .fuzzing.targetContracts = [$contract]' \
   medusa.json > "$TMP_CONFIG"
mv "$TMP_CONFIG" medusa.json

echo -e "${GREEN}Running Medusa...${NC}"
echo "  Target: $TARGET_CONTRACT"
echo ""

# Run medusa from project root
cd "$PROJECT_ROOT"
medusa fuzz --config "$SCRIPT_DIR/medusa.json"

echo ""
echo -e "${GREEN}Medusa fuzzing complete!${NC}"
