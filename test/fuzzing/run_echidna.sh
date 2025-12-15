#!/bin/bash
# Run Echidna fuzzing on Noma Protocol
# Usage: ./run_echidna.sh [harness] [config]
#   harness: VaultSolvencyFuzz (default), LendingFuzz, StakingFuzz, TokenFuzz
#   config: echidna.yaml (default)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default values
HARNESS="${1:-VaultSolvencyFuzz}"
CONFIG="${2:-echidna.yaml}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Noma Protocol Echidna Fuzzing${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if echidna is installed
if ! command -v echidna &> /dev/null; then
    echo -e "${RED}Error: echidna is not installed${NC}"
    echo "Install with: pip3 install echidna"
    echo "Or: brew install echidna (macOS)"
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

# Map harness name to file
case "$HARNESS" in
    "VaultSolvencyFuzz"|"vault"|"solvency")
        HARNESS_FILE="VaultSolvencyFuzz.sol"
        HARNESS_CONTRACT="VaultSolvencyFuzz"
        ;;
    "LendingFuzz"|"lending")
        HARNESS_FILE="LendingFuzz.sol"
        HARNESS_CONTRACT="LendingFuzz"
        ;;
    "StakingFuzz"|"staking")
        HARNESS_FILE="StakingFuzz.sol"
        HARNESS_CONTRACT="StakingFuzz"
        ;;
    "TokenFuzz"|"token")
        HARNESS_FILE="TokenFuzz.sol"
        HARNESS_CONTRACT="TokenFuzz"
        ;;
    *)
        echo -e "${RED}Unknown harness: $HARNESS${NC}"
        echo "Available: VaultSolvencyFuzz, LendingFuzz, StakingFuzz, TokenFuzz"
        exit 1
        ;;
esac

echo -e "${GREEN}Running Echidna...${NC}"
echo "  Harness: $HARNESS_CONTRACT"
echo "  Config:  $CONFIG"
echo ""

# Run echidna
cd "$SCRIPT_DIR"
echidna "$HARNESS_FILE" \
    --contract "$HARNESS_CONTRACT" \
    --config "$CONFIG" \
    --crytic-args "--foundry-out-directory $PROJECT_ROOT/out"

echo ""
echo -e "${GREEN}Echidna fuzzing complete!${NC}"
