#!/usr/bin/env bash
set -euo pipefail

: "${NATS_URL:?NATS_URL is required}"
: "${S3_BUCKET:?S3_BUCKET is required}"

DATE=$(date +"%Y-%m-%d-%H-%M-%S")
BACKUP_DIR="/backup/${DATE}"

echo "Starting JetStream backup..."
echo "NATS_URL=${NATS_URL}"
echo "S3_BUCKET=${S3_BUCKET}"

mkdir -p "${BACKUP_DIR}"

# List streams and back them up
# Get stream list safely
STREAMS=$(nats --server "${NATS_URL}" stream ls --json | jq -r '.[]')

if [ -z "${STREAMS}" ]; then
  echo "No JetStream streams found. Exiting."
  exit 0
fi

for stream in ${STREAMS}; do
  echo "Backing up stream: ${stream}"
  nats --server "${NATS_URL}" stream backup "${stream}" "${BACKUP_DIR}/${stream}"
done

# Upload to S3
echo "Uploading backups to S3..."
aws s3 sync "${BACKUP_DIR}" "s3://${S3_BUCKET}/jetstream/${DATE}"

echo "JetStream backup completed successfully"