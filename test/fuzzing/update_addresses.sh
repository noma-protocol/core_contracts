#!/bin/bash
# Update deployed addresses in FuzzSetup.sol from deploy_helper/out/out.json
# Usage: ./update_addresses.sh [network_id]
#   network_id: 1337 (default, local fork)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

NETWORK_ID="${1:-1337}"
JSON_FILE="$PROJECT_ROOT/deploy_helper/out/out.json"
SETUP_FILE="$SCRIPT_DIR/FuzzSetup.sol"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Update Fuzzing Addresses${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed${NC}"
    echo "Install with: apt install jq (Linux) or brew install jq (macOS)"
    exit 1
fi

# Check if JSON file exists
if [ ! -f "$JSON_FILE" ]; then
    echo -e "${RED}Error: Deployment file not found: $JSON_FILE${NC}"
    echo "Run deployment first to generate this file"
    exit 1
fi

# Read addresses from JSON
echo -e "${YELLOW}Reading addresses from $JSON_FILE (network $NETWORK_ID)...${NC}"

IDO_HELPER=$(jq -r ".[\"$NETWORK_ID\"].IDOHelper // empty" "$JSON_FILE")
MODEL_HELPER=$(jq -r ".[\"$NETWORK_ID\"].ModelHelper // empty" "$JSON_FILE")
EXCHANGE_HELPER=$(jq -r ".[\"$NETWORK_ID\"].ExchangeHelper // empty" "$JSON_FILE")
PROXY=$(jq -r ".[\"$NETWORK_ID\"].Proxy // empty" "$JSON_FILE")
FACTORY=$(jq -r ".[\"$NETWORK_ID\"].Factory // empty" "$JSON_FILE")
RESOLVER=$(jq -r ".[\"$NETWORK_ID\"].Resolver // empty" "$JSON_FILE")

# Validate addresses
if [ -z "$IDO_HELPER" ] || [ "$IDO_HELPER" == "null" ]; then
    echo -e "${RED}Error: IDOHelper address not found for network $NETWORK_ID${NC}"
    exit 1
fi

echo "  IDO_HELPER:      $IDO_HELPER"
echo "  MODEL_HELPER:    $MODEL_HELPER"
echo "  EXCHANGE_HELPER: $EXCHANGE_HELPER"
echo "  NOMA_PROXY:      $PROXY"
echo "  FACTORY:         $FACTORY"
echo "  RESOLVER:        $RESOLVER"
echo ""

# Update FuzzSetup.sol
echo -e "${YELLOW}Updating $SETUP_FILE...${NC}"

# Use sed to replace addresses
sed -i.bak \
    -e "s|address constant IDO_HELPER = 0x[a-fA-F0-9]\{40\};|address constant IDO_HELPER = $IDO_HELPER;|" \
    -e "s|address constant MODEL_HELPER = 0x[a-fA-F0-9]\{40\};|address constant MODEL_HELPER = $MODEL_HELPER;|" \
    -e "s|address constant EXCHANGE_HELPER = 0x[a-fA-F0-9]\{40\};|address constant EXCHANGE_HELPER = $EXCHANGE_HELPER;|" \
    -e "s|address constant NOMA_PROXY = 0x[a-fA-F0-9]\{40\};|address constant NOMA_PROXY = $PROXY;|" \
    -e "s|address constant FACTORY = 0x[a-fA-F0-9]\{40\};|address constant FACTORY = $FACTORY;|" \
    -e "s|address constant RESOLVER = 0x[a-fA-F0-9]\{40\};|address constant RESOLVER = $RESOLVER;|" \
    "$SETUP_FILE"

# Remove backup file
rm -f "$SETUP_FILE.bak"

echo -e "${GREEN}Addresses updated successfully!${NC}"
echo ""
echo "Next steps:"
echo "  1. Make sure forked chain is running: anvil --fork-url <RPC_URL>"
echo "  2. Run fuzzing: ./run_echidna.sh or ./run_medusa.sh"
