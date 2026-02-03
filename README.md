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

### Security Configuration
Credentials in configuration files:
- Hub users: `hub_user`, `exec_user`, `sys`
- Leaf users: `leaf_user`, `sys`
- Route authentication: `route_user`

**⚠️ Important**: Change default passwords before production deployment!

## Deployment

### Hub Deployment 

```bash
cd nats/hub
docker-compose up -d
```

### Leaf Deployment
```bash
cd nats/leaf
docker compose up -d
```

### Verify Deployment
```bash
# Check container status
docker ps

# Check logs
docker logs nats-hub
docker logs nats-leaf-1a
```

## Testing

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
nats stream add -s nats://hub_user:hub_password@nats-hub:4222
```
#### Create Stream on Leaf
```bash
nats stream add -s nats://leaf_user:leaf_password@nats-leaf:4225
```

#### List Streams on Hub
```bash
nats stream ls -s nats://hub_user:hub_password@nats-hub:4222
```

#### List Streams on Leaf
```bash
nats stream ls -s nats://leaf_user:leaf_password@nats-leaf:4225
```

### Aggregate Stream Creation

#### Create Aggregate Stream on Hub (Important: Configure subjects)
```bash
# Create aggregate stream with source and subjects
nats stream add aggregate --source leaf_stream -s nats://hub_user:hub_password@nats-hub:4222
```

### Message Publishing

#### Publish Messages from Leaf (Important: Use subject patterns)
```bash
# Correct: Use subject patterns that match stream configuration
nats pub leaf_stream.test "hello test" --count 10 -s nats://leaf_user:leaf_password@nats-leaf:4225
# Note: leaf_stream is configured to listen to "leaf_stream.*" pattern
```

## Monitoring

### Stream report
```bash
# Check stream report on hub, that messages are getting in hub aggregate stream
nats stream report -s nats://hub_user:hub_password@nats-hub:4222

# Message Flow: leaf_stream (leaf) → aggregate stream (hub)
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

# Leaf connections
curl -s http://nats-hub-1:8222/leafz | jq '.leafnodes'
curl -s http://nats-hub-2:8223/leafz | jq '.leafnodes'
curl -s http://nats-hub-3:8224/leafz | jq '.leafnodes'
```

## Connection Details

### Hub Access Points
**nats-hub-1**: nats://hub_user:hub_password@nats-hub-1:4222
**nats-hub-2**: nats://hub_user:hub_password@nats-hub-2:4223
**nats-hub-3**: nats://hub_user:hub_password@nats-hub-3:4224

### Leaf Access Points
**leaf-1a**: nats://leaf_user:leaf_password@nats-leaf-1a:422
**leaf-1b**: nats://leaf_user:leaf_password@nats-leaf-1b:4226
**leaf-2a**: nats://leaf_user:leaf_password@nats-leaf-2a:4227
**leaf-2b**: nats://leaf_user:leaf_password@nats-leaf-2b:4228

## Service Ports

### Hub Server (nats-hub)
```yaml
hub-1:  4222 (client), 6222 (cluster), 7422 (leafnode), 8222 (monitoring), 8442 (websocket)
hub-2:  4223 (client), 6223 (cluster), 7423 (leafnode), 8223 (monitoring), 8443 (websocket)
hub-3:  4224 (client), 6224 (cluster), 7424 (leafnode), 8224 (monitoring), 8444 (websocket)
```
### Leaf Server (nats-leaf)
```yaml
leaf-1a: 4225 (client), 6225 (cluster), 8225 (monitoring)
leaf-1b: 4226 (client), 6226 (cluster), 8226 (monitoring)
leaf-2a: 4227 (client), 6227 (cluster), 8227 (monitoring)
leaf-2b: 4228 (client), 6228 (cluster), 8228 (monitoring)
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

## Network Connectivity Diagram
```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                           NATS Hub-Leaf Architecture                                │
└─────────────────────────────────────────────────────────────────────────────────────┘

Hub Server                     Leaf Server 
┌─────────────────────────┐                ┌─────────────────────────┐
│     Hub Cluster         │                │      Leaf Nodes         │
│                         │                │                         │
│  ┌─────────────────┐    │                │  ┌─────────────────┐    │
│  │   nats-hub      │    │                │  │  nats-leaf-1a   │    │
│  │   Port: 4222    │    │                │  │  Port: 4225     │    │
│  │   Leafnode:7422 │    │                │  │  Domain: leaf-1 │    │
│  └─────────────────┘    │                │  └─────────────────┘    │
│           │             │                │           │             │
│  ┌─────────────────┐    │                │  ┌─────────────────┐    │
│  │   nats-hub-2    │    │◄──────────────►│  │  nats-leaf-1b   │    │
│  │   Port: 4223    │    │   Leafnode     │  │  Port: 4226     │    │
│  │   Leafnode:7423 │    │   Connection   │  │  Domain: leaf-1 │    │
│  └─────────────────┘    │                │  └─────────────────┘    │
│           │             │                │           │             │
│  ┌─────────────────┐    │                │  ┌─────────────────┐    │
│  │   nats-hub-3    │    │                │  │  nats-leaf-2a   │    │
│  │   Port: 4224    │    │                │  │  Port: 4227     │    │
│  │   Leafnode:7424 │    │                │  │  Domain: leaf-2 │    │
│  └─────────────────┘    │                │  └─────────────────┘    │
│           │             │                │           │             │
│     Cluster Routes      │                │  ┌─────────────────┐    │
│   (6222, 6223, 6224)    │                │  │  nats-leaf-2b   │    │
│                         │                │  │  Port: 4228     │    │
│   JetStream Domain:     │                │  │  Domain: leaf-2 │    │
│        "hub"            │                │  └─────────────────┘    │
└─────────────────────────┘                └─────────────────────────┘
```