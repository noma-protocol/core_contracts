#!/bin/bash
set -e

if [ -f .env ]; then
  export $(cat .env | sed 's/#.*//g' | xargs)
fi

# Define the output files
DEPLOY_LOG=$(mktemp)
RAW_TMP="$(dirname "$0")/deploy_helper/raw.tmp"

# Step 1: Capture output of the deployment commands
forge script script/deploy/DeployFactory.s.sol -vv --rpc-url="$RPC_URL" --private-key="$PRIVATE_KEY" --gas-price 1000000000 --broadcast --slow --legacy | tee "$DEPLOY_LOG"
forge script script/deploy/DeployVault.s.sol -vv --rpc-url="$RPC_URL" --private-key="$PRIVATE_KEY" --gas-price 1000000000 --broadcast --slow --legacy | tee -a "$DEPLOY_LOG"

# Step 2: Extract relevant logs into a temporary file
awk '
  /== Logs ==/ { in_logs = 1; next } # Start capturing after "== Logs =="
  in_logs && /address:/ { print; next } # Capture lines with "address:"
  in_logs && /^$/ { in_logs = 0 } # Stop capturing after a blank line
' "$DEPLOY_LOG" > "$RAW_TMP"

# Step 3: Extract the addresses and update the deployment file
sh "$(dirname "$0")/deploy_helper/extractFromRaw.sh"
