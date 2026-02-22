#!/usr/bin/env bash
# =============================================================================
# vault-acme-issue-all.sh — Orchestrate certbot issuance for all edge services
#
# Runs daily via vault-acme-issue-all.timer. Only executes on the Keepalived
# VIP owner (edge-1 or edge-2, whichever holds 192.168.20.22).
#
# For each domain in the list:
#   1. certbot certonly --manual --preferred-challenges dns
#   2. auth.sh creates TXT in acme.home.arpa via Kerberos nsupdate
#   3. Vault ACME validates DNS-01 → issues certificate
#   4. cleanup.sh removes TXT record
#   5. 50-haproxy-deploy hook assembles PEM + reloads HAProxy
#
# After all certs: haproxy-certs-send (ExecStartPost) syncs to edge-2.
#
# Role-scoped ACME endpoints enforce domain restrictions server-side:
#   edge-mgmt-frontend → *.mgmt.home.arpa only
#   edge-app-frontend  → *.app.home.arpa only
#   home-arpa-fqdns    → *.home.arpa (default, infra services)
#
# Deployed to: /usr/local/sbin/vault-acme-issue-all.sh
# =============================================================================
set -euo pipefail
umask 077

# ---------------------------------------------------------------------------
# Role-scoped ACME directory URLs (defense in depth)
# ---------------------------------------------------------------------------
readonly ACME_BASE="https://vault.home.arpa/v1/pki_int/roles"
readonly ACME_MGMT="${ACME_BASE}/edge-mgmt-frontend/acme/directory"
readonly ACME_APP="${ACME_BASE}/edge-app-frontend/acme/directory"
readonly ACME_INFRA="${ACME_BASE}/home-arpa-fqdns/acme/directory"

readonly AUTH_HOOK="/usr/local/lib/certbot-dns01/auth.sh"
readonly CLEAN_HOOK="/usr/local/lib/certbot-dns01/cleanup.sh"
readonly VIP_IP="192.168.20.22"

if ip -4 -o addr show | awk "{print \$4}" | grep -Eq "${VIP_IP}(/|$)"; then
  : # MASTER (VIP owner)
else
  echo "Not VIP owner (${VIP_IP}). Skipping issuance."
  exit 0
fi

# ---------------------------------------------------------------------------
# Domain → role-scoped ACME endpoint mapping
# ---------------------------------------------------------------------------
acme_dir_for_domain() {
  local domain="$1"
  case "${domain}" in
    *.mgmt.home.arpa) echo "${ACME_MGMT}" ;;
    *.app.home.arpa)  echo "${ACME_APP}"  ;;
    *)                echo "${ACME_INFRA}" ;;
  esac
}

domains=(
  "nextcloud.app.home.arpa"
  "opnsense.mgmt.home.arpa"
  "wazuh.mgmt.home.arpa"
  "ipa.mgmt.home.arpa"
  "ipa-cockpit.mgmt.home.arpa"
  "proxmox.mgmt.home.arpa"
  "ilo.mgmt.home.arpa"
  "unifi.mgmt.home.arpa"
  "rancher.mgmt.home.arpa"
  "adguard.mgmt.home.arpa"
  "truenas.mgmt.home.arpa"
  "maltrail.mgmt.home.arpa"
  "netdata.mgmt.home.arpa"
  "ntopng.mgmt.home.arpa"
  "me30.mgmt.home.arpa"
  "argocd.mgmt.home.arpa"
  "longhorn.mgmt.home.arpa"
  "vault.home.arpa"
  "vault.mgmt.home.arpa"
  "haproxy.mgmt.home.arpa"
)

for d in "${domains[@]}"; do
  acme_dir="$(acme_dir_for_domain "${d}")"
  echo "==> Ensuring cert for: ${d} (via ${acme_dir##*/roles/})"
  certbot certonly \
    --cert-name "${d}" \
    --manual \
    --preferred-challenges dns \
    --manual-auth-hook "${AUTH_HOOK}" \
    --manual-cleanup-hook "${CLEAN_HOOK}" \
    --server "${acme_dir}" \
    --key-type rsa --rsa-key-size 2048 \
    --non-interactive \
    --keep-until-expiring \
    -d "${d}"
done
