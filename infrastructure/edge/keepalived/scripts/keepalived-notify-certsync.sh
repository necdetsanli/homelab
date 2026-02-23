#!/usr/bin/env bash
# =============================================================================
# Keepalived notify script — cert sync + audit on VIP transition
#
# Called by Keepalived when VRRP state changes. When this node becomes MASTER:
#   1. Records transition timestamp (audit trail)
#   2. Syncs certs + certsync config to the demoted peer via haproxy-certs-send
#
# This ensures the peer stays current even after a failover. The sync is
# non-blocking (backgrounded) and failures are logged but not fatal.
#
# Deployed to: /usr/local/sbin/keepalived-notify-certsync.sh
# Referenced in: keepalived.conf → vrrp_instance → notify_master
# =============================================================================
set -euo pipefail

TYPE="${1:-}"
NAME="${2:-}"
STATE="${3:-}"
PRIO="${4:-}"

logger -t keepalived-notify "event type=${TYPE} name=${NAME} state=${STATE} prio=${PRIO}"

if [[ "${STATE}" == "MASTER" ]]; then
  # Audit trail
  install -d -m 0750 /var/lib/keepalived
  date -Is > /var/lib/keepalived/certsync.master

  # Give VIP a moment to settle before running rsync
  sleep 3

  # Sync certs + config to peer (non-blocking, failures are non-fatal)
  if [[ -x /usr/local/sbin/haproxy-certs-send ]]; then
    logger -t keepalived-notify "STATE=MASTER -> syncing certs to peer"
    /usr/local/sbin/haproxy-certs-send 2>&1 | logger -t keepalived-certsync &
  else
    logger -t keepalived-notify "haproxy-certs-send not found — skipping cert sync"
  fi
fi
