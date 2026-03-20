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
nsc add user --account "$ACCOUNT_NAME" app_user
nsc add user --account "$ACCOUNT_NAME" websocket_user

# 6. Configure User Permissions
echo -e "${GREEN}[6/9] Configuring user permissions${NC}"

# app_user permissions
nsc edit user app_user --account "$ACCOUNT_NAME" \
  --allow-pubsub '$JS.API.STREAM.>' \
  --allow-pubsub '$JS.API.CONSUMER.>' \
  --allow-pub "did-notify.>,_INBOX.>" \
  --allow-sub "aggregate.>,did-notify.>,_INBOX.>"

nsc edit user app_user --account "$ACCOUNT_NAME" \
  --allow-pubsub '$JS.API.CONSUMER.CREATE.aggregate.>' \
  --allow-pubsub '$JS.ACK.>' \
  --deny-pub "aggregate.>"

# websocket_user permissions
nsc edit user websocket_user --account "$ACCOUNT_NAME" \
  --allow-pub "user.ack,_INBOX.>" \
  --allow-sub "did.>,_INBOX.>" \
  --deny-pubsub '$JS.>'

# 7. Generate Credentials
echo -e "${GREEN}[7/9] Generating credential files${NC}"
nsc generate creds --account "$ACCOUNT_NAME" --name app_user > app_user.creds
nsc generate creds --account "$ACCOUNT_NAME" --name websocket_user > websocket_user.creds

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
