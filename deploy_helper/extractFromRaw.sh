#!/bin/bash
set -e

if [ -f .env ]; then
  export $(cat .env | sed 's/#.*//g' | xargs)
fi

RAW_TMP="$(dirname "$0")/raw.tmp"
DEPLOYMENT_FILE="$(dirname "$0")/out/deployment.json"
OUT_FILE="$(dirname "$0")/out/out.json"
DAPP_PATH="../noma-home/src/assets/"

# Fetch network ID from the RPC URL
NETWORK_ID=$(curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' \
  "$RPC_URL" | grep -o '"result":"[^"]*' | grep -o '[^"]*$')

# Validate NETWORK_ID
if [ -z "$NETWORK_ID" ]; then
  echo "Error: Failed to fetch network ID."
  exit 1
fi

# Start fresh: Initialize deployment.json
echo "{ \"$NETWORK_ID\": {" > "$DEPLOYMENT_FILE"

# Read raw.tmp line by line and append to JSON
while IFS= read -r line; do
  key=$(echo "$line" | awk -F: '{print $1}' | awk '{print $1}')
  address=$(echo "$line" | awk -F: '{print $2}' | xargs)

  if [ -n "$key" ] && [ -n "$address" ]; then
    echo "  \"$key\": \"$address\"," >> "$DEPLOYMENT_FILE"
  fi
done < "$RAW_TMP"

# Remove the trailing comma and finalize JSON structure
sed -i '$ s/,$//' "$DEPLOYMENT_FILE"
echo "}}" >> "$DEPLOYMENT_FILE"

# Create out.json with specific keys
echo "{ \"$NETWORK_ID\": {" > "$OUT_FILE"
for key in "IDOHelper" "ModelHelper" "Proxy"; do
  address=$(grep -o "\"$key\": \".*\"" "$DEPLOYMENT_FILE" | awk -F: '{print $2}' | xargs)
  if [ -n "$address" ]; then
    echo "  \"$key\": \"$address\"," >> "$OUT_FILE"
  fi
done
sed -i '$ s/,$//' "$OUT_FILE"
echo "}}" >> "$OUT_FILE"

# Update .env file to be in the root directory of the project
ENV_FILE="$(cd "$(dirname "$0")"/.. && pwd)/.env"

# Process individual environment variables
for env_var in "MODEL_HELPER_ADDRESS=ModelHelper" "POOL_ADDRESS=Pool" "VAULT_ADDRESS=Vault"; do
  env_name=$(echo "$env_var" | awk -F= '{print $1}')
  json_key=$(echo "$env_var" | awk -F= '{print $2}')
  address=$(grep -o "\"$json_key\": \".*\"" "$DEPLOYMENT_FILE" | awk -F: '{print $2}' | xargs)

  if [ -n "$address" ]; then
    # Check if the variable exists in the .env file and replace it
    if grep -q "^$env_name=" "$ENV_FILE"; then
      sed -i "s/^$env_name=.*/$env_name=$address/" "$ENV_FILE"
    else
      # Append the variable to the .env file
      echo "$env_name=$address" >> "$ENV_FILE"
    fi
  fi
done

# Display the resulting files
echo "Deployment addresses saved to $DEPLOYMENT_FILE and $OUT_FILE:"
cat "$DEPLOYMENT_FILE"
cat "$OUT_FILE"
echo ".env updated with selected addresses:"
cat "$ENV_FILE"
cp "$DEPLOYMENT_FILE" "$DAPP_PATH/deployment.json"