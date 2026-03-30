#!/usr/bin/env bash
set -euo pipefail

: "${NATS_URL:?NATS_URL is required}"
: "${S3_BUCKET:?S3_BUCKET is required}"
: "${RESTORE_DATE:?RESTORE_DATE is required}"

if [ -n "${NATS_CREDS_FILE:-}" ]; then
  NATS_AUTH="--creds ${NATS_CREDS_FILE}"
elif [ -n "${NATS_USER:-}" ] && [ -n "${NATS_PASSWORD:-}" ]; then
  NATS_AUTH="--user ${NATS_USER} --password ${NATS_PASSWORD}"
else
  NATS_AUTH=""
fi

RESTORE_DIR="/restore/${RESTORE_DATE}"
S3_PREFIX="jetstream"

echo "Starting JetStream restore..."
echo "Restore date: ${RESTORE_DATE}"
echo "Restore dir: ${RESTORE_DIR}"

# Validate backup exists
if ! aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}/${RESTORE_DATE}/" >/dev/null 2>&1; then
  echo "ERROR: Backup not found in S3 at s3://${S3_BUCKET}/${S3_PREFIX}/${RESTORE_DATE}/"
  exit 1
fi

mkdir -p "${RESTORE_DIR}"

# Download backup
echo "Downloading backup from S3..."
aws s3 sync "s3://${S3_BUCKET}/${S3_PREFIX}/${RESTORE_DATE}" "${RESTORE_DIR}"

# Restore streams
for stream_dir in "${RESTORE_DIR}"/*; do
  [ -d "${stream_dir}" ] || continue

  STREAM_NAME=$(basename "${stream_dir}")
  echo "Restoring stream: ${STREAM_NAME}"

  # Delete existing stream if present
  if nats --server "${NATS_URL}" ${NATS_AUTH} stream info "${STREAM_NAME}" >/dev/null 2>&1; then
    echo "Stream ${STREAM_NAME} already exists, deleting..."
    nats --server "${NATS_URL}" ${NATS_AUTH} stream rm "${STREAM_NAME}" -f
  fi

  nats --server "${NATS_URL}" ${NATS_AUTH} stream restore "${stream_dir}"
done

echo "JetStream restore completed successfully"
