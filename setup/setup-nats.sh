#!/bin/bash

set -e

# Load env file
source .env

# Configuration
ACCOUNT_NAME="app"
OUTPUT_DIR="./nats-output"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== NATS JWT Authentication Setup ===${NC}\n"

# Create output directory
mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

# 1. Create Operator
echo -e "${GREEN}[1/9] Creating operator: $OPERATOR_NAME${NC}"
nsc add operator --generate-signing-key --sys --name "$OPERATOR_NAME"

# 2. Configure Operator
echo -e "${GREEN}[2/9] Configuring operator${NC}"
nsc edit operator --require-signing-keys --account-jwt-server-url "$NATS_SERVER_URL"

# 3. Create Account
echo -e "${GREEN}[3/9] Creating account: $ACCOUNT_NAME${NC}"
nsc add account "$ACCOUNT_NAME"
nsc edit account "$ACCOUNT_NAME" --sk generate

# 4. Configure JetStream
echo -e "${GREEN}[4/9] Configuring JetStream${NC}"
nsc edit account "$ACCOUNT_NAME" --js-disk-storage -1 --js-mem-storage -1 --js-streams -1 --js-consumer -1

# 5. Create Users
echo -e "${GREEN}[5/9] Creating users${NC}"
nsc add user --account "$ACCOUNT_NAME" "$HUB_USERNAME"
nsc add user --account "$ACCOUNT_NAME" "$HUB_WEBSOCKET_USERNAME"

# 6. Configure User Permissions
echo -e "${GREEN}[6/9] Configuring user permissions${NC}"

ALLOW_PUB=""
ALLOW_SUB=""
ALLOW_CONSUMER_CREATE=""
DENY_CONSUMER_CREATE=""

# Build PUB streams from HUB_PUB_STREAMS
IFS=',' read -ra PUB_STREAMS <<< "$HUB_PUB_STREAMS"
for STREAM in "${PUB_STREAMS[@]}"; do
  STREAM=$(echo "$STREAM" | xargs)
  ALLOW_PUB="${ALLOW_PUB:+${ALLOW_PUB},}${STREAM}.>"
done

# Build SUB streams from HUB_SUB_STREAMS
IFS=',' read -ra SUB_STREAMS <<< "$HUB_SUB_STREAMS"
for STREAM in "${SUB_STREAMS[@]}"; do
  STREAM=$(echo "$STREAM" | xargs)
  ALLOW_SUB="${ALLOW_SUB:+${ALLOW_SUB},}${STREAM}.>"
done

# Build ALLOW_CONSUMER_CREATE from HUB_ALLOW_CONSUMER_CREATE_STREAMS
IFS=',' read -ra ALLOW_CONSUMER_STREAMS <<< "$HUB_ALLOW_CONSUMER_CREATE_STREAMS"
for STREAM in "${ALLOW_CONSUMER_STREAMS[@]}"; do
  STREAM=$(echo "$STREAM" | xargs)
  ALLOW_CONSUMER_CREATE="${ALLOW_CONSUMER_CREATE}\$JS.API.CONSUMER.CREATE.${STREAM}.>,"
done

# Build DENY_CONSUMER_CREATE from HUB_DENY_CONSUMER_CREATE_STREAMS
IFS=',' read -ra DENY_STREAMS <<< "$HUB_DENY_CONSUMER_CREATE_STREAMS"
for STREAM in "${DENY_STREAMS[@]}"; do
  STREAM=$(echo "$STREAM" | xargs)
  DENY_CONSUMER_CREATE="${DENY_CONSUMER_CREATE}\$JS.API.CONSUMER.CREATE.${STREAM}.>,"
done

# Add base permissions from env vars
ALLOW_PUB="${HUB_ALLOW_PUB:+${HUB_ALLOW_PUB},}${ALLOW_PUB}"
ALLOW_SUB="${HUB_ALLOW_SUB:+${HUB_ALLOW_SUB},}${ALLOW_SUB}"
ALLOW_CONSUMER_CREATE=${ALLOW_CONSUMER_CREATE%,}
DENY_CONSUMER_CREATE=${DENY_CONSUMER_CREATE%,}

# app_user permissions
nsc edit user "$HUB_USERNAME" --account "$ACCOUNT_NAME" \
  --allow-pubsub '$JS.API.STREAM.>' \
  --allow-pubsub '$JS.API.CONSUMER.>' \
  --allow-pubsub '$JS.ACK.>' \
  --allow-pub "$ALLOW_PUB" \
  --allow-sub "$ALLOW_SUB" \
  ${ALLOW_CONSUMER_CREATE:+--allow-pubsub "$ALLOW_CONSUMER_CREATE"} \
  ${HUB_DENY_PUB:+--deny-pub "$HUB_DENY_PUB"} \
  ${HUB_DENY_SUB:+--deny-sub "$HUB_DENY_SUB"} \
  ${DENY_CONSUMER_CREATE:+--deny-pubsub "$DENY_CONSUMER_CREATE"}

# websocket_user permissions
nsc edit user "$HUB_WEBSOCKET_USERNAME" --account "$ACCOUNT_NAME" \
  --allow-pub "${WEBSOCKET_ALLOW_PUB}" \
  --allow-sub "${WEBSOCKET_ALLOW_SUB}" \
  ${WEBSOCKET_DENY_PUB:+--deny-pub "$WEBSOCKET_DENY_PUB"} \
  ${WEBSOCKET_DENY_SUB:+--deny-sub "$WEBSOCKET_DENY_SUB"} \
  --deny-pubsub '$JS.>'

# 7. Generate Credentials
echo -e "${GREEN}[7/9] Generating credential files${NC}"
nsc generate creds --account "$ACCOUNT_NAME" --name "$HUB_USERNAME" > "${HUB_USERNAME}.creds"
nsc generate creds --account "$ACCOUNT_NAME" --name "$HUB_WEBSOCKET_USERNAME" > "${HUB_WEBSOCKET_USERNAME}.creds"

# 8. Generate Resolver Configuration
echo -e "${GREEN}[8/9] Generating resolver configuration${NC}"
nsc generate config --nats-resolver --sys-account SYS > resolver.conf

# 9. Generate Account JWT
echo -e "${GREEN}[9/9] Generating account JWT${NC}"
ACCOUNT_ID=$(nsc describe account app | awk -F'|' '/Account ID/ {gsub(/ /,"",$3); print $3}')
ACCOUNT_JWT=$(nsc describe account "$ACCOUNT_NAME" --raw)

# Save app.jwt with account ID and JWT
cat > app.jwt << EOF
# Account: $ACCOUNT_NAME
# Account ID: $ACCOUNT_ID
# Generated: $(date)

# ACCOUNT_JWT: $ACCOUNT_JWT
EOF

echo -e "\n${GREEN}✓ Setup completed successfully!${NC}"
echo -e "\n${BLUE}All files generated in: $OUTPUT_DIR${NC}"

# List generated files
echo -e "${BLUE}Generated files:${NC}"

echo -e "\n${BLUE}Next step: Start nats hub server with the generated resolver.conf file. Run 'nsc push -A' to push accounts to NATS server${NC}"
