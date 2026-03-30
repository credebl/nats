# Custom NATS Box

A Docker image extending `natsio/nats-box` with AWS CLI support for JetStream stream backup and restore to/from S3.

## What It Does

- **backup.sh** — lists all JetStream streams, backs them up locally, then uploads to S3 under `s3://<bucket>/jetstream/<timestamp>/`
- **restore.sh** — downloads a backup from S3 by date, deletes existing streams if present, and restores them

## Build

```bash
cd custom-nats-box
docker build -t custom-nats-box .
```

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `NATS_URL` | Yes | NATS server URL e.g. `nats://<hub-ip>:4222` |
| `S3_BUCKET` | Yes | S3 bucket name to store/retrieve backups |
| `NATS_CREDS_FILE` | No | Path to mounted `.creds` file for JWT auth e.g. `/creds/user.creds` |
| `NATS_USER` | No | Username for basic auth (used if `NATS_CREDS_FILE` is not set) |
| `NATS_PASSWORD` | No | Password for basic auth (used if `NATS_CREDS_FILE` is not set) |
| `RESTORE_DATE` | Only for restore | Timestamp folder to restore from e.g. `2024-01-15-10-30-00` |

## AWS Credentials

The container uses the AWS CLI, so credentials must be available via one of:
- IAM role attached to the EC2 instance / ECS task (recommended)
- Environment variables: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`

## Usage

> Copy `.env.example` to `.env` and fill in the values before running.

### Run Backup

```bash
docker run --rm --env-file .env custom-nats-box /backup.sh
```

### Run Restore

```bash
docker run --rm --env-file .env custom-nats-box /restore.sh
```

> The `RESTORE_DATE` in `.env` must match an existing folder under `s3://<bucket>/jetstream/`. List available backups with:
> ```bash
> aws s3 ls s3://<your-s3-bucket>/jetstream/
> ```

### With Creds File (JWT Auth)

Set `NATS_CREDS_FILE=/creds/user.creds` in `.env`, then mount the file:

```bash
docker run --rm --env-file .env \
  -v /path/to/user.creds:/creds/user.creds \
  custom-nats-box /backup.sh
```

### With Username & Password

Set `NATS_USER` and `NATS_PASSWORD` in `.env`, then:

```bash
docker run --rm --env-file .env custom-nats-box /backup.sh
```

## S3 Backup Structure

```
s3://<bucket>/
└── jetstream/
    ├── 2024-01-15-10-30-00/
    │   ├── stream-A/
    │   └── stream-B/
    └── 2024-01-16-08-00-00/
        ├── stream-A/
        └── stream-B/
```

## Switching Between Backup and Restore

The Dockerfile defaults to running `backup.sh`. To switch to restore, update the last line in the Dockerfile:

```dockerfile
# For backup (default)
CMD ["/backup.sh"]

# For restore
CMD ["/restore.sh"]
```

Then rebuild the image.

## Testing

### 1. Verify NATS connectivity

```bash
docker run --rm --env-file .env custom-nats-box \
  nats --server "$NATS_URL" stream ls
```

### 2. Test backup

```bash
docker run --rm --env-file .env custom-nats-box /backup.sh
```

Verify files landed in S3:
```bash
aws s3 ls s3://<your-s3-bucket>/jetstream/ --recursive
```

### 3. Test restore

Set `RESTORE_DATE=<timestamp>` in `.env`, then:

```bash
docker run --rm --env-file .env custom-nats-box /restore.sh
```

Verify streams are restored:
```bash
nats --context hub stream ls
nats --context hub stream report
```
