#!/usr/bin/env bash
# =============================================================================
# Keepalived notify script — certificate sync trigger on VIP transition
#
# Called by Keepalived when VRRP state changes. When this node becomes MASTER,
# touches a trigger file. The actual cert sync is handled by:
#   - vault-acme-issue-all.timer (daily issuance + sync)
#   - haproxy-certs-send (rsync to peer)
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

# When becoming MASTER, touch trigger file for observability / auditing
if [[ "${STATE}" == "MASTER" ]]; then
  logger -t keepalived-notify "STATE=MASTER -> touching trigger file"
  date -Is > /var/lib/keepalived/certsync.master
fi
