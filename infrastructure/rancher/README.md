# Rancher / RKE2 Infrastructure Configuration

Reference copies of Rancher-managed cluster configuration and Cilium Helm value
overrides. These files are **not applied by ArgoCD** — they exist for version
tracking, documentation, and public showcase.

> **Source of truth:** Rancher UI → Cluster Management → k8s-home-arpa → Edit YAML

## Files

| File                         | Description                                                                          |
| ---------------------------- | ------------------------------------------------------------------------------------ |
| `cluster-k8s-home-arpa.yaml` | Sanitized `provisioning.cattle.io/v1 Cluster` resource (no secrets, UIDs, or status) |
| `cilium-values.yaml`         | Cilium Helm value overrides with detailed rationale for every setting                |

## Architecture Overview

```
┌──────────────────────────────┐
│  HAProxy Edge VMs            │
│  edge-1 (192.168.20.20)     │      VIP: 192.168.20.22 (Keepalived)
│  edge-2 (192.168.20.21)     │──┐   TLS termination, rate limiting
└──────────────────────────────┘  │
                                  │  HTTP (port 80)
                                  ▼
┌──────────────────────────────────────────────────────────────────┐
│  Kubernetes Cluster — k8s-home-arpa                              │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐     │
│  │  Cilium Gateway API (embedded Envoy)                    │     │
│  │  VIP: 192.168.20.201 (LB-IPAM + L2 announcement)       │     │
│  │  Listener: HTTP :80 → hostname-based routing            │     │
│  └──────────────┬──────────────────────────────────────────┘     │
│                 │  HTTPRoute per service                         │
│                 ▼                                                │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                       │
│  │ Longhorn │  │ Hubble   │  │ Future   │  Backend Services     │
│  │ Frontend │  │ UI       │  │ Apps     │                       │
│  └──────────┘  └──────────┘  └──────────┘                       │
│                                                                  │
│  BGP: AS 64501 ──peer──▶ OPNsense AS 64500 (192.168.20.1)       │
└──────────────────────────────────────────────────────────────────┘
```

## Key Design Decisions

### Pure eBPF Datapath (Zero iptables)

| Feature         | Setting                          | Purpose                                                           |
| --------------- | -------------------------------- | ----------------------------------------------------------------- |
| Native routing  | `routingMode: native`            | No VXLAN encapsulation overhead                                   |
| eBPF masquerade | `bpf.masquerade: true`           | Replaces iptables MASQUERADE chain                                |
| eBPF tproxy     | `bpf.tproxy: true`               | Proxy traffic handled in eBPF — fixes Envoy socket mark conflicts |
| Socket LB       | `socketLB.enabled: true`         | Service load balancing at `connect()` syscall                     |
| Bandwidth mgr   | `bandwidthManager.enabled: true` | EDT-based fair queuing + BBR congestion control                   |
| No kube-proxy   | `kubeProxyReplacement: true`     | Cilium handles all Service/NodePort/LB                            |

### Cilium-Native IP Management (Replaces MetalLB)

| Component                    | Replacement                      |
| ---------------------------- | -------------------------------- |
| MetalLB `IPAddressPool`      | `CiliumLoadBalancerIPPool` CRD   |
| MetalLB `L2Advertisement`    | `CiliumL2AnnouncementPolicy` CRD |
| MetalLB controller + speaker | Cilium agent (already running)   |

Benefits: Fewer CRDs, no extra pods, L2 handled in eBPF datapath, native
integration with BGP control plane for mixed L2/BGP advertisement.

### Observability Integration

| Tool           | Integration Point                                                                       | Notes                                                                                            |
| -------------- | --------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| **Prometheus** | `:9962` (agent), `:9963` (operator), `:9964` (envoy), `:9965` (hubble), `:9966` (relay) | All enabled, OpenMetrics format                                                                  |
| **Grafana**    | `dashboards.enabled: true`                                                              | ConfigMaps with `grafana_dashboard: "1"` label, auto-discovered by sidecar                       |
| **Hubble UI**  | `:12000` (ClusterIP)                                                                    | Real-time service map, expose via Gateway HTTPRoute or port-forward                              |
| **ELK / Loki** | `hubble.dropEventEmitter` → K8s events                                                  | Collect events with Filebeat/Promtail. Optional: enable `hubble.export.static` for raw flow logs |
| **Zabbix**     | Prometheus endpoints                                                                    | Use Zabbix HTTP agent items to scrape Cilium metrics                                             |

### Security

- **CIS Profile**: RKE2 CIS 1.8 hardened (`profile: cis`, `protect-kernel-defaults: true`)
- **PSA**: `rancher-restricted` template enforced cluster-wide
- **Network Policies**: Default-deny ingress on all platform namespaces
- **Node Drain**: Enabled for both control-plane and worker upgrades

## Companion CRDs (Managed by ArgoCD)

These CRDs are deployed by ArgoCD Applications, not by Rancher:

| CRD                          | Location                       | ArgoCD Application |
| ---------------------------- | ------------------------------ | ------------------ |
| `CiliumBGPClusterConfig`     | `clusters/.../cilium-bgp/`     | `cilium-bgp`       |
| `CiliumBGPPeerConfig`        | `clusters/.../cilium-bgp/`     | `cilium-bgp`       |
| `CiliumBGPAdvertisement`     | `clusters/.../cilium-bgp/`     | `cilium-bgp`       |
| `CiliumLoadBalancerIPPool`   | `clusters/.../cilium-lb/`      | `cilium-lb` (TODO) |
| `CiliumL2AnnouncementPolicy` | `clusters/.../cilium-lb/`      | `cilium-lb` (TODO) |
| `Gateway` / `HTTPRoute`      | `clusters/.../gateway-config/` | `gateway-config`   |
| Gateway API CRDs             | `vendor/gateway-api/v1.4.1/`   | `gateway-api-crds` |

## Updating Configuration

1. Edit the Cilium overrides in `cilium-values.yaml`
2. Copy the values into the Rancher cluster YAML under `spec.rkeConfig.chartValues.rke2-cilium`
3. Apply via Rancher UI → Cluster → Edit YAML, or update `cluster-k8s-home-arpa.yaml` and apply via Rancher API
4. Rancher triggers a rolling restart of the Cilium DaemonSet
