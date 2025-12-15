#!/bin/bash
# Run Foundry invariant tests on Noma Protocol
# Usage: ./run_invariants.sh [runs] [depth]
#   runs: Number of invariant test runs (default: 256)
#   depth: Call sequence depth per run (default: 50)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

RUNS="${1:-256}"
DEPTH="${2:-50}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Noma Protocol Invariant Testing${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if fork is running
echo -e "${YELLOW}Checking fork at localhost:8545...${NC}"
if ! curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    http://localhost:8545 > /dev/null 2>&1; then
    echo -e "${RED}Error: No RPC endpoint at localhost:8545${NC}"
    echo "Start with: anvil --fork-url <RPC_URL>"
    exit 1
fi
echo -e "${GREEN}Fork detected!${NC}"
echo ""

# Check .env file
if [ ! -f "$PROJECT_ROOT/.env" ]; then
    echo -e "${RED}Error: .env file not found${NC}"
    echo "Create .env with PRIVATE_KEY and DEPLOYER"
    exit 1
fi

# Load .env
source "$PROJECT_ROOT/.env"

# Check required env vars
if [ -z "$PRIVATE_KEY" ] || [ -z "$DEPLOYER" ]; then
    echo -e "${RED}Error: PRIVATE_KEY and DEPLOYER must be set in .env${NC}"
    exit 1
fi

# Check deployment file
if [ ! -f "$PROJECT_ROOT/deploy_helper/out/out.json" ]; then
    echo -e "${RED}Error: Deployment file not found${NC}"
    echo "Run deployment first to generate deploy_helper/out/out.json"
    exit 1
fi

echo -e "${CYAN}Configuration:${NC}"
echo "  Runs:  $RUNS"
echo "  Depth: $DEPTH"
echo "  Deployer: $DEPLOYER"
echo ""

cd "$PROJECT_ROOT"

echo -e "${YELLOW}Running invariant tests...${NC}"
echo ""

# Run invariant tests with fork
forge test \
    --match-contract VaultInvariantTest \
    --fork-url http://localhost:8545 \
    -vvv \
    --ffi \
    --invariant-runs "$RUNS" \
    --invariant-depth "$DEPTH"

echo ""
echo -e "${GREEN}Invariant testing complete!${NC}"
