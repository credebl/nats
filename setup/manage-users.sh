#!/bin/bash

set -e

source .env

ACCOUNT_NAME="$HUB_ACCOUNT_NAME"
OUTPUT_DIR="./nats-output"
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

read -rp "Current NATS Hub server URL: ${NATS_SERVER_URL} — Continue? [Y/n]: " URL_CONFIRM
if [ "$URL_CONFIRM" == "n" ] || [ "$URL_CONFIRM" == "N" ]; then
  read -rp "Enter new NATS Hub server URL: " NATS_SERVER_URL
  nsc edit operator --require-signing-keys --account-jwt-server-url "$NATS_SERVER_URL"
  echo -e "${GREEN}✓ Operator URL updated to $NATS_SERVER_URL${NC}"
fi

echo -e "${BLUE}What do you want to do?${NC}"
echo "1) Create user"
echo "2) Remove user"
read -rp "Enter choice [1/2]: " CHOICE

if [ "$CHOICE" == "1" ]; then
  read -rp "Enter username: " USERNAME

  echo -e "${GREEN}Creating user: $USERNAME${NC}"
  nsc add user --account "$ACCOUNT_NAME" "$USERNAME"
  nsc add user --account "$ACCOUNT_NAME" "exec_${USERNAME}"

  ALLOW_PUB=""
  ALLOW_SUB=""
  ALLOW_CONSUMER_CREATE=""
  DENY_CONSUMER_CREATE=""

  # Build PUB streams from LEAF_PUB_STREAMS
  IFS=',' read -ra PUB_STREAMS <<< "$LEAF_PUB_STREAMS"
  for STREAM in "${PUB_STREAMS[@]}"; do
    STREAM=$(echo "$STREAM" | xargs)
    ALLOW_PUB="${ALLOW_PUB:+${ALLOW_PUB},}${STREAM}.>"
  done

  # Build SUB streams from LEAF_SUB_STREAMS
  IFS=',' read -ra SUB_STREAMS <<< "$LEAF_SUB_STREAMS"
  for STREAM in "${SUB_STREAMS[@]}"; do
    STREAM=$(echo "$STREAM" | xargs)
    ALLOW_SUB="${ALLOW_SUB:+${ALLOW_SUB},}${STREAM}.>"
  done

  # Build ALLOW_CONSUMER_CREATE from LEAF_ALLOW_CONSUMER_CREATE_STREAMS
  IFS=',' read -ra ALLOW_CONSUMER_STREAMS <<< "$LEAF_ALLOW_CONSUMER_CREATE_STREAMS"
  for STREAM in "${ALLOW_CONSUMER_STREAMS[@]}"; do
    STREAM=$(echo "$STREAM" | xargs)
    ALLOW_CONSUMER_CREATE="${ALLOW_CONSUMER_CREATE}\$JS.API.CONSUMER.CREATE.${STREAM}.>,"
  done

  # Build DENY_CONSUMER_CREATE from LEAF_DENY_CONSUMER_CREATE_STREAMS
  IFS=',' read -ra DENY_STREAMS <<< "$LEAF_DENY_CONSUMER_CREATE_STREAMS"
  for STREAM in "${DENY_STREAMS[@]}"; do
    STREAM=$(echo "$STREAM" | xargs)
    DENY_CONSUMER_CREATE="${DENY_CONSUMER_CREATE}\$JS.API.CONSUMER.CREATE.${STREAM}.>,"
  done

  # Add base permissions from env vars
  ALLOW_PUB="${LEAF_ALLOW_PUB:+${LEAF_ALLOW_PUB},}${ALLOW_PUB}"
  ALLOW_SUB="${LEAF_ALLOW_SUB:+${LEAF_ALLOW_SUB},}${ALLOW_SUB}"
  ALLOW_CONSUMER_CREATE=${ALLOW_CONSUMER_CREATE%,}
  DENY_CONSUMER_CREATE=${DENY_CONSUMER_CREATE%,}

  echo -e "${GREEN}Configuring permissions for $USERNAME${NC}"
  nsc edit user "$USERNAME" --account "$ACCOUNT_NAME" \
    --allow-pubsub '$JS.API.>' \
    --allow-pubsub '$JS.ACK.>' \
    --allow-pub "$ALLOW_PUB" \
    --allow-sub "$ALLOW_SUB" \
    ${ALLOW_CONSUMER_CREATE:+--allow-pub "$ALLOW_CONSUMER_CREATE"} \
    ${LEAF_DENY_PUB:+--deny-pub "$LEAF_DENY_PUB"} \
    ${LEAF_DENY_SUB:+--deny-sub "$LEAF_DENY_SUB"} \
    ${DENY_CONSUMER_CREATE:+--deny-pub "$DENY_CONSUMER_CREATE"}

  echo -e "${GREEN}Generating credentials${NC}"
  mkdir -p "${OUTPUT_DIR}/${USERNAME}"
  nsc generate creds --account "$ACCOUNT_NAME" --name "$USERNAME" > "${OUTPUT_DIR}/${USERNAME}/${USERNAME}.creds"
  nsc generate creds --account "$ACCOUNT_NAME" --name "exec_${USERNAME}" > "${OUTPUT_DIR}/${USERNAME}/exec_${USERNAME}.creds"

  echo -e "${GREEN}✓ User $USERNAME and exec_${USERNAME} created${NC}"
  echo -e "${GREEN}✓ Creds saved to ${OUTPUT_DIR}/${USERNAME}/${NC}"

elif [ "$CHOICE" == "2" ]; then
  echo -e "${BLUE}Available users:${NC}"
  nsc list users --account "$ACCOUNT_NAME"

  read -rp "Enter username to remove: " USERNAME
  nsc delete user --account "$ACCOUNT_NAME" --name "$USERNAME"
  nsc delete user --account "$ACCOUNT_NAME" --name "exec_${USERNAME}" 2>/dev/null && echo -e "${GREEN}✓ User exec_${USERNAME} removed${NC}" || echo -e "exec_${USERNAME} not found, skipping"
  echo -e "${GREEN}✓ User $USERNAME removed${NC}"

else
  echo "Invalid choice"; exit 1
fi

read -rp "Push accounts to NATS server now? (nsc push -A) [y/N]: " PUSH
if [ "$PUSH" == "y" ] || [ "$PUSH" == "Y" ]; then
  nsc push -A --account "$ACCOUNT_NAME" -u "$NATS_SERVER_URL"
  echo -e "${GREEN}✓ Pushed to $NATS_SERVER_URL${NC}"
fi
