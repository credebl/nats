# NATS Hub-Leaf Cluster with IP-Based Communication

This setup provides a high-availability NATS cluster with IP-based communication and automatic failover between hub and leaf nodes.

## Architecture

### Hub Cluster
- **3-node clustered hub** for high availability
- **JetStream enabled** with domain: hub
- **Ports**: 4222 (hub), 4223 (hub-2), 4224 (hub-3)
- **Cluster Routes**:
  - hub-1: Routes to nats-hub-2:6224 and nats-hub-3:6225
  - hub-2: Routes to nats-hub-1:6222 and nats-hub-2:6225
  - hub-3: Routes to nats-hub-1:6222 and nats-hub-2:6224

### Leaf Nodes 
- **2 independent leaf nodes** for each leaf with automatic hub failover
- **JetStream enabled** with domain leaf and 
- **Ports**: 4221 (leaf), 4226 (leaf-2), 4223 (del), 4227 (del-2)
- **Leaf_cluster_ports**: 6231 (leaf-blr), 6232 (leaf-blr-2), 6233 (leaf-del), 6234 (leaf-del-2)

## Deployment

### Hub Deployment 

```bash
cd /home/rohit/Desktop/nats-bun-ws-gateway/nats/nats-hub
docker-compose up -d
```

### Leaf Deployment
```bash
cd /home/ayanworks/Desktop/nats-bun-ws-gateway/nats/nats-leaf
docker compose up -d
```

## Testing Commands

### NATS Box Setup

#### On Hub Server 
```bash
docker run --rm -it --network=host natsio/nats-box
```

#### On Leaf Server 
```bash
docker run --rm -it --network=host natsio/nats-box
```

### Stream Management

#### Create Stream on Hub
```bash
nats stream add -s nats://app_user:app_password@nats-hub:4222
```
#### Create Stream on Leaf
```bash
nats stream add -s nats://leaf_user:leaf_password@nats-leaf:4221
```

#### List Streams on Hub
```bash
nats stream ls -s nats://app_user:app_password@nats-hub:4222
```

#### List Streams on Leaf
```bash
nats stream ls -s nats://leaf_user:leaf_password@nats-leaf:4221
```

### Aggregate Stream Creation

#### Create Aggregate Stream on Hub (Important: Configure subjects)
```bash
# Create aggregate stream with source and subjects
nats stream add aggregate --source leaf_stream -s nats://app_user:app_password@nats-hub:4222
```

### Message Publishing

#### Publish Messages from Leaf (Important: Use subject patterns)
```bash
# Correct: Use subject patterns that match stream configuration
nats pub leaf_stream.test "hello test" --count 10 -s nats://leaf_user:leaf_password@nats-leaf:4221
# Note: leaf_stream is configured to listen to "leaf_stream.*" pattern
```

### Monitoring

#### Check Message Flow with HTTP Endpoints (nats-top has issues in containers)
```bash
# Check leaf node stats
curl -s http://nats-leaf:8221/varz | jq ".server_name, .connections, .in_msgs, .out_msgs"
curl -s http://nats-leaf:8223/varz | jq ".server_name, .connections, .in_msgs, .out_msgs"

# Check hub node stats  
curl -s http://nats-hub:8222/varz | jq ".server_name, .connections, .in_msgs, .out_msgs"
```

#### Check Cluster Status
```bash
# Hub cluster routes
curl -s http://nats-hub:8222/routez | jq '.num_routes'
curl -s http://nats-hub-2:8224/routez | jq '.num_routes'
curl -s http://nats-hub-3:8225/routez | jq '.num_routes'

# Leaf connections
curl -s http://nats-hub:8222/leafz | jq '.leafnodes'
curl -s http://nats-hub-2:8224/leafz | jq '.leafnodes'
curl -s http://nats-hub-3:8225/leafz | jq '.leafnodes'
```

## Connection Details

### Hub Access Points
**nats-hub-1**: nats://app_user:app_password@nats-hub:4222
**nats-hub-2**: nats://app_user:app_password@nats-hub-2:4224
**nats-hub-3**: nats://app_user:app_password@nats-hub-3:4225

### Leaf Access Points
**Bangalore**: nats://leaf_user:leaf_password@nats-leaf-blr:4221
**Bangalore-2**: nats://leaf_user:leaf_password@nats-leaf-blr-2:4226
**Delhi**: nats://leaf_user:leaf_password@nats-leaf-del:4223
**Delhi-2**: nats://leaf_user:leaf_password@nats-leaf-del-2:4227

## Service Ports

### Hub Server (nats-hub)
```yaml
hub:    4222 (client), 6222 (cluster), 7422 (leafnode), 8222 (monitoring)
hub-2:  4224 (client), 6224 (cluster), 7424 (leafnode), 8224 (monitoring)
hub-3:  4225 (client), 6225 (cluster), 7425 (leafnode), 8225 (monitoring)
```
### Leaf Server (nats-leaf)
```yaml
leaf-blr:   4221 (client), 8221 (monitoring)
leaf-blr-2: 4226 (client), 8226 (monitoring)
leaf-del:   4223 (client), 8223 (monitoring)
leaf-del-2: 4227 (client), 8227 (monitoring)
```

### Expected Behavior
**Hub failure**: Leaves automatically connect to available hub nodes
**Reconnection time**: ~2 seconds
**No message loss**: JetStream maintains persistence during failover

## Key Features

### Log Analysis
**"Leafnode connection created"**: Successful connection
**"JetStream using domains"**: Domain mapping working
**"Error trying to connect"**: Normal during failover process
**"Route connection created"**: Hub cluster formation successful

## Network Connectivity Diagram
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                           NATS Hub-Leaf HA Architecture                            │
└─────────────────────────────────────────────────────────────────────────────────────┘

Hub Server                     Leaf Server 
┌─────────────────────────┐                ┌─────────────────────────┐
│     Hub Cluster         │                │      Leaf Nodes        │
│                         │                │                         │
│  ┌─────────────────┐    │                │  ┌─────────────────┐    │
│  │   nats-hub      │    │◄──────────────►│  │  nats-leaf-blr  │    │
│  │   Port: 4222    │    │   Leafnode     │  │   Port: 4221    │    │
│  │   Leafnode:7422 │    │   Connection   │  │   Domain: blr   │    │
│  └─────────────────┘    │                │  └─────────────────┘    │
│           │              │                │           │             │
│  ┌─────────────────┐    │                │  ┌─────────────────┐    │
│  │   nats-hub-2    │    │◄──────────────►│  │ nats-leaf-blr-2 │    │
│  │   Port: 4224    │    │   Failover     │  │   Port: 4226    │    │
│  │   Leafnode:7424 │    │   URLs         │  │   Domain: blr   │    │
│  └─────────────────┘    │                │  └─────────────────┘    │
│           │              │                │           │             │
│  ┌─────────────────┐    │                │  ┌─────────────────┐    │
│  │   nats-hub-3    │    │◄──────────────►│  │  nats-leaf-del  │    │
│  │   Port: 4225    │    │   Automatic    │  │   Port: 4223    │    │
│  │   Leafnode:7425 │    │   Reconnect    │  │   Domain: del   │    │
│  └─────────────────┘    │                │  └─────────────────┘    │
│           │              │                │           │             │
│     Cluster Routes       │                │  ┌─────────────────┐    │
│   (6222, 6224, 6225)    │                │  │ nats-leaf-del-2 │    │
│                         │                │  │   Port: 4227    │    │
│   JetStream Domain:     │                │  │   Domain: del   │    │
│        "hub"            │                │  └─────────────────┘    │
└─────────────────────────┘                └─────────────────────────┘

Failover Flow:
1. Leaf connects to primary hub (7422)
2. If hub fails → automatic failover to hub-2 (7424)  
3. If hub-2 fails → automatic failover to hub-3 (7425)
4. Reconnection time: ~1 second
5. No message loss during failover

Message Flow:
leaf_stream (leaf) → aggregate stream (hub) → cross-domain replication