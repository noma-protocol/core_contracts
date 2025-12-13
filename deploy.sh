#!/bin/bash
set -e

# Parse command-line arguments
NETWORKS=""
NO_RESET=false
DEPLOY_VAULT=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --networks)
      NETWORKS="$2"
      shift 2
      ;;
    --no-reset)
      NO_RESET=true
      shift
      ;;
    --deploy-vault)
      DEPLOY_VAULT=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Default to a single network deployment if --networks not provided
if [ -z "$NETWORKS" ]; then
  NETWORKS="[default]"
fi

if [ -f .env ]; then
  export $(cat .env | sed 's/#.*//g' | xargs)
fi

OUT="$(dirname "$0")/deploy_helper/out"

if [ ! -d "$OUT" ]; then
  mkdir -p "$OUT"
fi

# Define the output files
DEPLOY_LOG=$(mktemp)
RAW_TMP="$(dirname "$0")/deploy_helper/raw.tmp"
DEPLOYMENT_FILE="$OUT/deployment.json"

# Initialize deployment.json with empty object if deploying to multiple networks
if [ "$NETWORKS" != "[default]" ]; then
  if [ "$NO_RESET" = false ]; then
    echo "{}" > "$DEPLOYMENT_FILE"
  fi
  export MULTI_NETWORK_MODE="true"
else
  export MULTI_NETWORK_MODE="false"
fi

# Parse networks array [1337,143] to iterate
NETWORK_LIST=$(echo "$NETWORKS" | tr -d '[]' | tr ',' ' ')

# If default, use current RPC_URL from .env
if [ "$NETWORKS" = "[default]" ]; then
  NETWORK_LIST="default"
fi

# Deploy to the first network only (or default RPC_URL)
PRIMARY_NETWORK=$(echo "$NETWORK_LIST" | awk '{print $1}')
echo "Deploying to primary network: $PRIMARY_NETWORK"

# Set RPC_URL based on network (you may need to adjust this logic)
if [ "$PRIMARY_NETWORK" != "default" ]; then
  # Look for RPC_URL_<NETWORK> in .env, e.g., RPC_URL_1337, RPC_URL_143
  NETWORK_RPC_VAR="RPC_URL_${PRIMARY_NETWORK}"
  NETWORK_RPC_URL="${!NETWORK_RPC_VAR}"

  if [ -z "$NETWORK_RPC_URL" ]; then
    echo "Warning: RPC_URL_${PRIMARY_NETWORK} not found in .env, using default RPC_URL"
    NETWORK_RPC_URL="$RPC_URL"
  fi

  export RPC_URL="$NETWORK_RPC_URL"
fi

# Step 1: Capture output of the deployment commands
forge script script/deploy/DeployFactory.s.sol -vvvv --rpc-url="$RPC_URL" --private-key="$PRIVATE_KEY" --gas-price 50000000000 --broadcast --slow --optimize | tee "$DEPLOY_LOG"
awk '
  /== Logs ==/ { in_logs = 1; next } # Start capturing after "== Logs =="
  in_logs && /address:/ { print; next } # Capture lines with "address:"
  in_logs && /^$/ { in_logs = 0 } # Stop capturing after a blank line
' "$DEPLOY_LOG" > "$RAW_TMP"

# # Step 5: Extract the addresses and update the deployment file
sh "$(dirname "$0")/deploy_helper/extractFromRaw.sh"

forge script script/deploy/DeployVaultUpgrade1.s.sol -vvvv --rpc-url="$RPC_URL" --private-key="$PRIVATE_KEY" --gas-price 50000000000 --broadcast --slow --optimize | tee "$DEPLOY_LOG"

awk '
  /== Logs ==/ { in_logs = 1; next } # Start capturing after "== Logs =="
  in_logs && /address:/ { print; next } # Capture lines with "address:"
  in_logs && /^$/ { in_logs = 0 } # Stop capturing after a blank line
' "$DEPLOY_LOG" > "$RAW_TMP"

# # Step 5: Extract the addresses and update the deployment file
sh "$(dirname "$0")/deploy_helper/extractFromRaw.sh"

forge script script/deploy/DeployVaultUpgrade2.s.sol -vvvv --rpc-url="$RPC_URL" --private-key="$PRIVATE_KEY" --gas-price 50000000000 --broadcast --slow --optimize | tee "$DEPLOY_LOG"

awk '
  /== Logs ==/ { in_logs = 1; next } # Start capturing after "== Logs =="
  in_logs && /address:/ { print; next } # Capture lines with "address:"
  in_logs && /^$/ { in_logs = 0 } # Stop capturing after a blank line
' "$DEPLOY_LOG" > "$RAW_TMP"

# # Step 5: Extract the addresses and update the deployment file
sh "$(dirname "$0")/deploy_helper/extractFromRaw.sh"

forge script script/deploy/DeploySatellite.s.sol -vvvv  --rpc-url="$RPC_URL" --private-key="$PRIVATE_KEY" --gas-price 50000000000 --broadcast --slow --optimize | tee -a "$DEPLOY_LOG"

awk '
  /== Logs ==/ { in_logs = 1; next } # Start capturing after "== Logs =="
  in_logs && /address:/ { print; next } # Capture lines with "address:"
  in_logs && /^$/ { in_logs = 0 } # Stop capturing after a blank line
' "$DEPLOY_LOG" > "$RAW_TMP"

# # Step 5: Extract the addresses and update the deployment file
sh "$(dirname "$0")/deploy_helper/extractFromRaw.sh"

forge script script/deploy/ConfigureFactory.s.sol -vvvv --rpc-url="$RPC_URL" --private-key="$PRIVATE_KEY" --gas-price 50000000000 --broadcast --slow --optimize | tee "$DEPLOY_LOG"

awk '
  /== Logs ==/ { in_logs = 1; next } # Start capturing after "== Logs =="
  in_logs && /address:/ { print; next } # Capture lines with "address:"
  in_logs && /^$/ { in_logs = 0 } # Stop capturing after a blank line
' "$DEPLOY_LOG" > "$RAW_TMP"

# # Step 5: Extract the addresses and update the deployment file
sh "$(dirname "$0")/deploy_helper/extractFromRaw.sh"

# Step 6: Deploy the Vault contract (optional)
if [ "$DEPLOY_VAULT" = true ]; then
  forge script script/deploy/DeployVault.s.sol -vvvv --rpc-url="$RPC_URL" --private-key="$PRIVATE_KEY" --gas-price 50000000000 --broadcast --slow --optimize | tee -a "$DEPLOY_LOG"

  # Step 2: Extract relevant logs into a temporary file
  awk '
    /== Logs ==/ { in_logs = 1; next } # Start capturing after "== Logs =="
    in_logs && /address:/ { print; next } # Capture lines with "address:"
    in_logs && /^$/ { in_logs = 0 } # Stop capturing after a blank line
  ' "$DEPLOY_LOG" > "$RAW_TMP"

  # # Step 5: Extract the addresses and update the deployment file
  sh "$(dirname "$0")/deploy_helper/extractFromRaw.sh"
fi

echo "Completed deployment for network: $PRIMARY_NETWORK"

# If multi-network mode, copy addresses to other networks
if [ "$MULTI_NETWORK_MODE" = "true" ]; then
  export COPY_NETWORKS="$NETWORKS"
  sh "$(dirname "$0")/deploy_helper/copyToNetworks.sh"
fi

echo "All deployments completed!"

