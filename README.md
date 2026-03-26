# NATS Hub-Leaf Cluster with IP-Based Communication

This setup provides a high-availability NATS cluster with IP-based communication and automatic failover between hub and leaf nodes.

## Architecture

### Hub Cluster
- **3-node clustered hub** for high availability
- **JetStream enabled** with domain: hub
- **Ports**: 4222 (hub), 4223 (hub-2), 4224 (hub-3)
- **Cluster Routes**:
  - hub-1: Routes to nats-hub-2:6223 and nats-hub-3:6224
  - hub-2: Routes to nats-hub-1:6222 and nats-hub-3:6224
  - hub-3: Routes to nats-hub-1:6222 and nats-hub-2:6223

### Leaf Nodes 
- **2 independent leaf nodes** for each leaf
- **JetStream enabled** with domains leaf-1 and leaf-2
- **Ports**: 4225 (leaf-1a), 4226 (leaf-1b), 4227 (leaf-2a), 4228 (leaf-2b)
- **Leaf_cluster_ports**: 6235 (leaf-1a), 6236 (leaf-1b), 6237 (leaf-2a), 6238 (leaf-2b)

## Prerequisites

- Docker and Docker Compose installed

## NATS Security Model: Operator, Account & User

NATS uses a **3-tier JWT-based security hierarchy** managed by NSC:

```
Operator
└── Account (e.g., hub-account, leaf-1-account)
    └── User (e.g., exec-user, main-user)
```

- **Operator** — the root trust anchor. A single operator signs and governs all accounts. The operator JWT is embedded in every NATS server config to establish trust. Created once during initial setup.

- **Account** — an isolated namespace within the operator. Subjects, streams, and permissions are scoped per account. Each leaf node gets its own account so it is fully isolated from other leaves. Accounts are pushed to the hub resolver so the hub can validate JWTs.

- **User** — a client identity within an account. A user gets a `.creds` file (JWT + private key) used to authenticate against the NATS server. Per leaf node, two users are created:
  - **exec user** — authenticates the leaf NATS server itself when connecting outbound to the hub
  - **main user** — used by the leaf side services running to publish/subscribe on the leaf NATS server

---

## NSC & NATS CLI Setup

### Install NATS CLI

```bash
go install github.com/nats-io/natscli/nats@latest
```

### Install NSC CLI

```bash
curl -L https://raw.githubusercontent.com/nats-io/nsc/master/install.py | python
echo 'export PATH="$PATH:/home/sahil-kamble/.nsccli/bin"' >> $HOME/.bashrc
source $HOME/.bashrc
```

Verify installations:
```bash
nats --version
nsc --version
```

---
## Configuration

```bash
# Update hub and leaf IP/HOST in config files before deployment

# Hub configuration
HUB_HOST_1=<hub-node-1-ip>
HUB_HOST_2=<hub-node-2-ip>
HUB_HOST_3=<hub-node-3-ip>

# Leaf configuration
LEAF_HOST_1=<leaf-node-1-ip>
LEAF_HOST_2=<leaf-node-2-ip>
```

## .env Configuration Reference

Copy `setup/.env.example` to `setup/.env`.

### Operator & Server

| Variable | Description |
|---|---|
| `OPERATOR_NAME` | Name of the NSC operator to create. Used as the root trust anchor for all accounts.(In case of cluster get the URL of any one hub node) |
| `NATS_SERVER_URL` | URL of any one hub NATS node or load balancer. e.g. `nats://10.0.0.101:4222` |
| `HUB_USERNAME` | Name of the hub app user created by `setup-nats.sh`. Used by hub-side services. e.g. `app_user` |
| `HUB_WEBSOCKET_USERNAME` | Name of the hub websocket user created by `setup-nats.sh`. Used by WebSocket clients. e.g. `websocket_user` |
| `HUB_ACCOUNT_NAME` | Name of the NSC account created. e.g. `app` |

### JetStream Subject Wildcards

Before configuring permissions, understand the key JetStream internal subjects:

```
$JS.API.STREAM.>
- Manage streams — create, update, delete, fetch stream info
```

```
$JS.API.CONSUMER.>
- Manage consumers — fetch consumer info, pull/push operations
```

```
$JS.ACK.>
- Send acknowledgements for messages. Required for message processing reliability
```

```
$JS.API.CONSUMER.CREATE.<stream>.>
- Create consumers specifically on `<stream>`
- Use `ALLOW_CONSUMER_CREATE_STREAMS` / `DENY_CONSUMER_CREATE_STREAMS` to control this per stream
```

```
_INBOX.>
- NATS internal subject used for request-reply messaging
- Any user that needs to send requests or receive replies must have _INBOX.> in both allow-pub and allow-sub
- Always include _INBOX.> in HUB_ALLOW_PUB, HUB_ALLOW_SUB, LEAF_ALLOW_PUB, LEAF_ALLOW_SUB
```

### Hub — app_user permissions

`app_user` is created on the hub account and used by hub-side services. Stream names are appended with `.>` automatically by the script.

| Variable | Description | Example |
|---|---|---|
| `HUB_PUB_STREAMS` | Streams app_user can publish to. Script builds `<stream>.>` for each. | `streamA` |
| `HUB_SUB_STREAMS` | Streams app_user can subscribe to. Script builds `<stream>.>` for each. | `aggregate,streamA` |
| `HUB_ALLOW_CONSUMER_CREATE_STREAMS` | Streams where `$JS.API.CONSUMER.CREATE.<stream>.>` is allowed. | `aggregate` |
| `HUB_DENY_CONSUMER_CREATE_STREAMS` | Streams where `$JS.API.CONSUMER.CREATE.<stream>.>` is denied. | `streamA` |
| `HUB_ALLOW_PUB` | Extra base subjects always added to allow-pub. | `_INBOX.>` |
| `HUB_ALLOW_SUB` | Extra base subjects always added to allow-sub. | `_INBOX.>` |
| `HUB_DENY_PUB` | Subjects to explicitly block publishing. Leave empty if none. | `orders.internal.>` |
| `HUB_DENY_SUB` | Subjects to explicitly block subscribing. Leave empty if none. | |

**Deny example:**
```env
HUB_DENY_PUB=orders.internal.>
```
👉 Even if `orders.>` is allowed, `orders.internal.*` is blocked ❌

### Hub — websocket_user permissions

`websocket_user` is created on the hub account for WebSocket clients. `$JS.>` is always fully denied for this user regardless of other settings.

| Variable | Description | Example |
|---|---|---|
| `WEBSOCKET_PUB_STREAMS` | Streams websocket_user can publish to. Script builds `<stream>.>` for each. | `user-events` |
| `WEBSOCKET_SUB_STREAMS` | Streams websocket_user can subscribe to. Script builds `<stream>.>` for each. | `did-notify` |
| `WEBSOCKET_ALLOW_CONSUMER_CREATE_STREAMS` | Streams where `$JS.API.CONSUMER.CREATE.<stream>.>` is allowed. Leave empty if none. | |
| `WEBSOCKET_DENY_CONSUMER_CREATE_STREAMS` | Streams where `$JS.API.CONSUMER.CREATE.<stream>.>` is denied. | `did-notify` |
| `WEBSOCKET_ALLOW_PUB` | Extra base subjects always added to allow-pub. | `user.ack,_INBOX.>` |
| `WEBSOCKET_ALLOW_SUB` | Extra base subjects always added to allow-sub. | `_INBOX.>` |
| `WEBSOCKET_DENY_PUB` | Subjects to explicitly block publishing. Leave empty if none. | |
| `WEBSOCKET_DENY_SUB` | Subjects to explicitly block subscribing. Leave empty if none. | |

### Leaf — user permissions

Per leaf node, `manage-users.sh` creates two users:
- `exec_<username>` — connects the leaf NATS server to the hub
- `<username>` — used by the verifier/service on the leaf side

Stream names are appended with `.>` automatically by the script.

| Variable | Description | Example |
|---|---|---|
| `LEAF_PUB_STREAMS` | Streams leaf user can publish to. Script builds `<stream>.>` for each. | `StreamB,StreamC` |
| `LEAF_SUB_STREAMS` | Streams leaf user can subscribe to. Script builds `<stream>.>` for each. | `StreamB,StreamC` |
| `LEAF_ALLOW_CONSUMER_CREATE_STREAMS` | Streams where `$JS.API.CONSUMER.CREATE.<stream>.>` is allowed. Leave empty if none. | |
| `LEAF_DENY_CONSUMER_CREATE_STREAMS` | Streams where `$JS.API.CONSUMER.CREATE.<stream>.>` is denied. | `StreamB,StreamC` |
| `LEAF_ALLOW_PUB` | Extra base subjects always added to allow-pub. | `_INBOX.>` |
| `LEAF_ALLOW_SUB` | Extra base subjects always added to allow-sub. | `_INBOX.>` |
| `LEAF_DENY_PUB` | Subjects to explicitly block publishing. Leave empty if none. | |
| `LEAF_DENY_SUB` | Subjects to explicitly block subscribing. Leave empty if none. | |

**Deny example:**
```env
LEAF_DENY_CONSUMER_CREATE_STREAMS=StreamB,StreamC
```
Leaf user cannot create consumers on `StreamB` or `StreamC` streams — blocks `$JS.API.CONSUMER.CREATE.StreamB.>` and `$JS.API.CONSUMER.CREATE.StreamC.>`

---
## Hub Security Setup (NSC-based JWT Auth)

### Step 1: Check .env file

```bash
# Direct node URL
NATS_URL=nats://<hub-node-1-ip>:4222

# Or via load balancer (VPC-internal only)
NATS_URL=nats://<load-balancer-ip>:4222

OPERATOR_NAME=myoperator
```

### Step 2: Run Initial Hub Setup

```bash
cd setup
./setup-nats.sh
```

This creates the operator, system account, and initial accounts/users.

All files are generated in `setup/nats-output/`:

| File | Used In |
|---|---|
| `resolver.conf` | Copy `operator`, `system_account`, and `resolver_preload` blocks into all 3 hub node config files (`hub-1.conf`, `hub-2.conf`, `hub-3.conf`) |
| `<HUB_USERNAME>.creds` | Used by hub-side services to connect to the hub NATS server |
| `<HUB_WEBSOCKET_USERNAME>.creds` | Used by WebSocket clients to connect to the hub NATS server |
| `<HUB_ACCOUNT_NAME>.jwt` | Contains account ID and account JWT — used to update leaf node config (`resolver_preload`) |

### Step 3: Update Hub NATS Config

After running `setup.sh`, copy the following blocks from the generated `resolver.conf` into each of the 3 hub node config files (`nats-hub-1.conf`, `nats-hub-2.conf`, `nats-hub-3.conf`):

```
operator: <operator-jwt>

system_account: <system-account-id>

resolver_preload: {
  <system-account-id>: <system-jwt>
  ...
}
```

> Reference the nats config file(hub.conf) in the repo for the exact placement of these blocks.

Repeat for all 3 hub node config files.

### Step 4: Start Hub Nodes

```bash
cd nats/hub
docker-compose up -d

docker logs -f nats-hub-1 # Check logs of service if everything is working fine.
```

### Step 5: Push Accounts to Hub

After hub nodes are running, push all accounts and users from the NSC server:

```bash
nsc push -A
```

> **Note:** If you get an error while pushing, check that the NATS endpoint configured in the operator is correct. If the hub IP has changed, update it and retry:
> ```bash
> nsc edit operator --account-jwt-server-url "nats://<hub-node-ip>:4222"
> nsc push -A
> ```

---

> **⚠️ Important: Backup NSC Server**
> Always keep a backup of the NSC server data (typically `~/.nsc` and `~/.local/share/nats/nsc`). If the NSC server is lost or crashes, you will **not** be able to create or remove users/accounts. However, the existing NATS infrastructure (hub + leaf nodes) will continue to work fine since they operate on already-issued JWTs.

## Leaf Node User Management

### Create a User for a Leaf Node

Use the `manage-user.sh` script. When prompted, choose **create**:

```bash
./manage-user.sh
# Select: create
# Provide: leaf node name (e.g., leaf_blr)
```

This creates **two users** per leaf node:
- **exec_leaf_blr user** — used for connecting the leaf node to the hub
- **leaf_blr user** — used by the verifier service on the leaf

### Push New Accounts to Hub

After creating a user, push to hub before deploying the leaf:

```bash
nsc push -A
```

> **Note:** If you get an error while pushing, check that the NATS endpoint configured in the operator is correct. If the hub IP has changed, update it and retry:
> ```bash
> nsc edit operator --account-jwt-server-url "nats://<hub-node-ip>:4222"
> nsc push -A
> ```

### Get Account JWT and Account ID for Leaf Config

After pushing, retrieve the account JWT and account ID from the NSC-generated files under nats username folder and update the leaf node's NATS config.

Update the leaf node config with:
```
operator: <operator-jwt>
system_account: <system-account-public-key>
resolver_preload: {
  <account-id>: <account-jwt>
}
```

### User Credentials for Leaf

- **leaf_exec user creds** → used in leaf node config to connect to hub
- **leaf main user creds** → used by the service connected to the leaf NATS server

### Leaf Deployment
```bash
cd nats/leaf
docker compose up -d
```

### Update Aggregate Stream on Hub for New Leaf Domain

When a new leaf node is added with a new JetStream domain (e.g. `leaf-3`), the aggregate stream on the hub must be updated to include the new domain as a source.

**Step 1: Export current aggregate stream config**
```bash
nats --context hub stream info aggregate --json > aggregate.json
```

**Step 2: Edit `aggregate.json` — add the new leaf domain to the `sources` array**
```json
{
  "name": "<stream-name>",
  "external": {
    "api": "$JS.leaf-3.API",
    "deliver": ""
  }
}
```

The full `sources` array should list all leaf domains including the new one:
```json
"sources": [
  {
    "name": "<stream-name>",
    "external": { "api": "$JS.leaf-1.API", "deliver": "" }
  },
  {
    "name": "<stream-name>",
    "external": { "api": "$JS.leaf-2.API", "deliver": "" }
  },
  {
    "name": "<stream-name>",
    "external": { "api": "$JS.leaf-3.API", "deliver": "" }
  }
]
```

**Step 3: Apply the updated config**
```bash
nats --context hub stream edit aggregate --config aggregate.json
```

**Step 4: Verify the stream now shows all sources**
```bash
nats --context hub stream info aggregate
```

> **Note:** Exporting and re-applying the full config is the safest approach — it preserves all existing sources and settings without accidentally overwriting them.

### Remove a User

```bash
./manage-user.sh
# Select: remove
# Provide: leaf node name to remove
```

After removal, push changes to hub:
```bash
nsc push -A
```

### Updating User Permissions

To add or change permissions for an existing user:

```bash
# Add specific pub/sub subjects
nsc edit user --account app <username> --allow-pub 'subject.>' --allow-sub 'subject.>'

# Deny specific subjects
nsc edit user --account app <username> --deny-pub 'subject.>' --deny-sub 'subject.>'

# Grant full access (no restrictions)
nsc edit user --account app <username> --allow-pub '>' --allow-sub '>'
```

After updating permissions, regenerate the creds file and redeploy it to the service using it:

```bash
# Regenerate creds
nsc generate creds --account app --name <username> > <username>.creds

# Push updated account to hub
nsc push -A
```

> **Important:** After replacing the creds file, restart the service that uses it so it picks up the new credentials.

---

## Deployment

### Verify Deployment
```bash
# Check container status
docker ps

# Check logs for hub
docker logs nats-hub-1
docker logs nats-hub-2
docker logs nats-hub-3

# Check logs for hub
docker logs nats-leaf-1a
docker logs nats-leaf-1b
```

## Testing

### NATS Context Setup (using creds file)

Before running any NATS CLI commands, save a context with your creds file so you don't need to pass `--server` and `--creds` every time.

### NATS Box Setup

#### For Hub Server
```bash
docker run --rm -it --network=host natsio/nats-box
```

#### For Leaf Server
```bash
docker run --rm -it --network=host natsio/nats-box
```

#### Hub context
```bash
nats context save hub \
  --server=nats://<hub-node-ip>:4222 \
  --creds=<path-to-exec-user.creds> \
  --description="hub server exec user"
```

#### Leaf context
```bash
nats context save leaf-1 \
  --server=nats://<leaf-node-ip>:4225 \
  --creds=<path-to-leaf-main-user.creds> \
  --description="leaf-1 main user"
```

Use a saved context with any command:
```bash
nats --context hub stream ls
nats --context leaf-1 stream ls
```

### NATS Box Setup

#### For Hub Server
```bash
docker run --rm -it --network=host natsio/nats-box
```

#### For Leaf Server
```bash
docker run --rm -it --network=host natsio/nats-box
```

### Stream Management

#### Create Stream on Hub
```bash
nats --context hub stream add
```

#### Create Stream on Leaf
```bash
nats --context leaf-1 stream add
```

#### List Streams on Hub
```bash
nats --context hub stream ls
```

#### List Streams on Leaf
```bash
nats --context leaf-1 stream ls
```

## Monitoring

### Stream report
```bash
# Check stream report on hub, that messages are getting in hub aggregate stream
nats --context hub stream report
```

### HTTP Monitoring Endpoints
```bash
# Check leaf node stats
curl -s http://nats-leaf-1:8225/varz | jq ".server_name, .connections, .in_msgs, .out_msgs"
curl -s http://nats-leaf-2:8226/varz | jq ".server_name, .connections, .in_msgs, .out_msgs"

# Check hub node stats  
curl -s http://nats-hub:8222/varz | jq ".server_name, .connections, .in_msgs, .out_msgs"
```

### Cluster Status
```bash
# Hub cluster routes
curl -s http://nats-hub-1:8222/routez | jq '.num_routes'
curl -s http://nats-hub-2:8223/routez | jq '.num_routes'
curl -s http://nats-hub-3:8224/routez | jq '.num_routes'
```

## Troubleshooting

### Expected Behavior
- **Hub failure**: Leaves automatically connect to available hub nodes
- **Reconnection time**: ~2 seconds
- **No message loss**: JetStream maintains persistence during failover

### Log Analysis
- **"Leafnode connection created"**: Successful connection
- **"JetStream using domains"**: Domain mapping working
- **"Error trying to connect"**: Normal during failover process
- **"Route connection created"**: Hub cluster formation successful

### Common Issues
1. **Connection refused**: Check firewall settings and port availability
2. **Authentication failed**: Verify credentials in configuration files
3. **Cluster formation issues**: Ensure all nodes can reach each other