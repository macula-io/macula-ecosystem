# MaculaOS Guide

MaculaOS is a Linux-based operating system designed for edge deployment of
Macula mesh nodes.

## Overview

MaculaOS provides:

- **Immutable infrastructure** - Read-only root filesystem
- **A/B updates** - Atomic, rollback-capable system updates
- **BEAM-optimized** - Tuned for Erlang/Elixir workloads
- **Mesh integration** - Pre-configured for Macula networking
- **Minimal footprint** - ~1GB ISO, runs on 1GB RAM

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                        MaculaOS                                 │
├────────────────────────────────────────────────────────────────┤
│  ┌──────────────────┐  ┌──────────────────┐                    │
│  │   Partition A    │  │   Partition B    │   A/B Updates      │
│  │  (Active Root)   │  │  (Standby Root)  │                    │
│  └──────────────────┘  └──────────────────┘                    │
├────────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    Data Partition                         │  │
│  │   /var/lib/maculaos/  - Persistent application data      │  │
│  │   /var/log/           - System and application logs       │  │
│  └──────────────────────────────────────────────────────────┘  │
├────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    BEAM Runtime                          │   │
│  │   Erlang/OTP 26+, Elixir 1.15+, Pre-tuned schedulers    │   │
│  └─────────────────────────────────────────────────────────┘   │
├────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                  Embedded Services                       │   │
│  │   soft-serve (git), WireGuard, node-exporter, fluent-bit│   │
│  └─────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────┘
```

## Installation

### Download

Get the latest ISO from GitHub releases:

```bash
wget https://github.com/macula-io/macula-os/releases/latest/download/maculaos-amd64.iso
```

### Boot Options

1. **Live mode** - Run from USB without installing
2. **Install mode** - Install to disk

### Installation

Boot from the ISO and run the installer:

```bash
sudo maculaos install
```

The installer will:
1. Detect available disks
2. Create partition layout (A/B + data)
3. Install MaculaOS
4. Configure bootloader
5. Set up initial user

### Configuration

Create `/var/lib/maculaos/config.yaml`:

```yaml
maculaos:
  hostname: edge-node-01

  network:
    interfaces:
      - name: eth0
        dhcp: true
      # Static IP example:
      # - name: eth0
      #   address: 192.168.1.100/24
      #   gateway: 192.168.1.1

  mesh:
    realm: io.mycompany
    role: peer              # peer | gateway | bootstrap
    bootstrap_nodes:
      - bootstrap.macula.io:4433

  ssh:
    authorized_keys:
      - ssh-ed25519 AAAA... user@example.com

  ntp:
    servers:
      - pool.ntp.org
```

## System Management

### The `maculaos` CLI

MaculaOS includes a management CLI:

```bash
# System information
maculaos info

# Check mesh status
maculaos mesh status

# View logs
maculaos logs

# Health check
maculaos health

# Upgrade system
maculaos upgrade

# Rollback to previous version
maculaos rollback
```

### Updates

MaculaOS uses A/B partitioning for atomic updates:

```bash
# Check for updates
maculaos upgrade --check

# Download and stage update
maculaos upgrade --download

# Apply update (requires reboot)
maculaos upgrade --apply
sudo reboot
```

If an update fails to boot, the system automatically rolls back.

### Manual Rollback

```bash
# Rollback to previous partition
maculaos rollback
sudo reboot
```

## Mesh Integration

MaculaOS comes pre-configured for Macula mesh participation.

### Mesh Roles

Configure the node's role in `config.yaml`:

**Peer Node** (default):
```yaml
mesh:
  role: peer
  bootstrap_nodes:
    - bootstrap.macula.io:4433
```

**Bootstrap Node** (DHT seed):
```yaml
mesh:
  role: bootstrap
  advertise_address: "203.0.113.10:4433"
```

**Gateway Node** (relay for NAT traversal):
```yaml
mesh:
  role: gateway
  stun_port: 3478
  turn_port: 3479
```

### Service Deployment

Deploy services using the built-in service manager:

```bash
# Deploy a service from OCI registry
maculaos deploy ghcr.io/mycompany/myservice:latest

# Deploy from local release
maculaos deploy /path/to/myservice.tar.gz

# List running services
maculaos services

# View service logs
maculaos logs myservice

# Stop a service
maculaos stop myservice
```

### Auto-Discovery

Services automatically register with the mesh DHT on startup:

```elixir
# In your service's application.ex
def start(_type, _args) do
  children = [
    # Start mesh client
    {MaculaClient, realm: Application.get_env(:my_app, :realm)},
    # Your application supervisor
    MyApp.Supervisor
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

## Storage

### Partition Layout

| Partition | Size | Mount | Purpose |
|-----------|------|-------|---------|
| Boot | 512MB | /boot | Bootloader, kernel |
| Root A | 4GB | / | Active system |
| Root B | 4GB | - | Standby system |
| Data | Remaining | /var | Persistent data |

### Persistent Data

Only `/var` survives updates. Store application data there:

```yaml
# In your service configuration
volumes:
  - /var/lib/maculaos/myservice:/app/data
```

### Data Backup

```bash
# Backup data partition
maculaos backup /mnt/usb/backup.tar.gz

# Restore from backup
maculaos restore /mnt/usb/backup.tar.gz
```

## Embedded Services

MaculaOS includes several embedded services:

### soft-serve (Git Server)

Local Git server for offline GitOps:

```bash
# Clone from local git server
git clone ssh://git@localhost:23231/myrepo.git
```

### WireGuard (VPN)

Secure mesh communication overlay:

```yaml
mesh:
  wireguard:
    enabled: true
    private_key: "${WIREGUARD_PRIVATE_KEY}"
    peers:
      - public_key: "abc..."
        endpoint: "peer1.example.com:51820"
```

### node-exporter (Metrics)

Prometheus metrics for monitoring:

```
http://localhost:9100/metrics
```

### fluent-bit (Logging)

Log aggregation and forwarding:

```yaml
logging:
  forward_to: logs.example.com:24224
  format: json
```

## Recovery

### Recovery Mode

Boot into recovery mode from GRUB or by pressing `R` during boot:

```bash
# In recovery mode
maculaos repair     # Attempt automatic repair
maculaos shell      # Drop to maintenance shell
maculaos factory    # Factory reset (WARNING: erases data)
```

### Factory Reset

Reset to default state (preserves network config):

```bash
maculaos factory --keep-network
```

Full factory reset:

```bash
maculaos factory --full
```

## Hardware Support

### Tested Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| x86_64 generic | Supported | Any 64-bit x86 |
| Raspberry Pi 4 | Supported | ARM64 build |
| Intel NUC | Supported | Recommended |
| Protectli Vault | Supported | Firewall appliance |

### Requirements

- **CPU**: 64-bit x86 or ARM64
- **RAM**: 1GB minimum, 2GB recommended
- **Storage**: 16GB minimum
- **Network**: Ethernet or WiFi

### GPIO Support (Raspberry Pi)

```elixir
# Access GPIO from your service
{:ok, gpio} = Circuits.GPIO.open(17, :output)
Circuits.GPIO.write(gpio, 1)
```

## Security

### Immutable Root

The root filesystem is read-only. This prevents:
- Runtime tampering
- Persistent malware
- Accidental modifications

### Secure Boot (Optional)

Enable secure boot for verified boot chain:

```yaml
security:
  secure_boot: true
  enrollment_key: /var/lib/maculaos/keys/MOK.der
```

### Firewall

Default firewall rules allow only mesh traffic:

```bash
# View current rules
maculaos firewall show

# Allow additional port
maculaos firewall allow 8080/tcp
```

### Automatic Updates

Configure automatic security updates:

```yaml
updates:
  automatic: true
  schedule: "04:00"      # 4 AM daily
  auto_reboot: true
  notify: admin@example.com
```

## Monitoring

### Health Dashboard

Access the local health dashboard:

```
http://localhost:9090
```

Shows:
- System resources (CPU, RAM, disk)
- Mesh connectivity status
- Service health
- Recent events

### Remote Monitoring

Export metrics to Prometheus:

```yaml
monitoring:
  prometheus:
    enabled: true
    port: 9100
    path: /metrics
```

### Alerting

Configure alerts via mesh pub/sub:

```yaml
alerts:
  - name: disk_full
    condition: disk_usage > 90%
    topic: io.mycompany.alerts.disk_full
```

## Troubleshooting

### Boot Issues

```bash
# Check boot logs
journalctl -b

# Check previous boot
journalctl -b -1

# View GRUB menu
# Hold SHIFT during boot
```

### Network Issues

```bash
# Check network status
maculaos network status

# Test mesh connectivity
maculaos mesh ping bootstrap.macula.io

# View network logs
maculaos logs network
```

### Service Issues

```bash
# Check service status
maculaos service status myservice

# View service logs
maculaos logs myservice

# Restart service
maculaos restart myservice
```

### Recovery from Failed Update

If the system fails to boot after an update:

1. Wait 3 failed boot attempts
2. System automatically rolls back
3. If still failing, boot into recovery mode
4. Run `maculaos repair`

## Next Steps

- [Architecture Guide](architecture.md) - Understand the ecosystem
- [Mesh Networking Guide](mesh-networking.md) - Configure mesh connectivity
- [Getting Started](getting-started.md) - Deploy your first service
