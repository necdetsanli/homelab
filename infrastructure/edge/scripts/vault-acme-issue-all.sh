#!/usr/bin/env bash
# =============================================================================
# vault-acme-issue-all.sh — Self-provisioning cert orchestrator for edge tier
#
# Single source of truth: add a domain to the list below → everything else
# is auto-provisioned on the next run:
#   1. CNAME delegation in FreeIPA (_acme-challenge.X → X.acme.home.arpa)
#   2. certbot DNS-01 issuance via Vault ACME
#   3. PEM bundle assembly for HAProxy (privkey + fullchain)
#   4. crt-list.txt + allowlist.txt regeneration
#   5. HAProxy validation + reload
#   6. haproxy-certs-send syncs everything to edge-2 (ExecStartPost)
#
# Runs daily via vault-acme-issue-all.timer. Only executes on the Keepalived
# VIP owner (edge-1 or edge-2, whichever holds 192.168.20.22).
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

readonly LOG_TAG="vault-acme"
log()  { logger -t "${LOG_TAG}" "$*"; echo "$*"; }
warn() { logger -t "${LOG_TAG}" -p user.warning "$*"; echo "WARN: $*" >&2; }

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
# Shared constants (IPs, ACME zone, keytab) — single source of truth
# shellcheck source=edge-env.sh
source /usr/local/lib/edge-env.sh

readonly ACME_BASE="https://vault.home.arpa/v1/pki_int/roles"
readonly ACME_MGMT="${ACME_BASE}/edge-mgmt-frontend/acme/directory"
readonly ACME_APP="${ACME_BASE}/edge-app-frontend/acme/directory"
readonly ACME_INFRA="${ACME_BASE}/home-arpa-fqdns/acme/directory"

readonly AUTH_HOOK="/usr/local/lib/certbot-dns01/auth.sh"
readonly CLEAN_HOOK="/usr/local/lib/certbot-dns01/cleanup.sh"
readonly VIP_IP="${EDGE_VIP_IP}"

readonly IPA_DNS_SERVER="${EDGE_IPA_DNS_SERVER}"
readonly ACME_ZONE="${EDGE_ACME_ZONE}"
readonly KEYTAB="${EDGE_KEYTAB}"
readonly PRINCIPAL="${EDGE_PRINCIPAL}"

readonly CERT_DIR="/etc/haproxy/certs"
readonly SYNC_DIR="/etc/haproxy/certsync"
readonly CRT_LIST="${SYNC_DIR}/crt-list.txt"
readonly ALLOWLIST="${SYNC_DIR}/allowlist.txt"
readonly HAPROXY_BIN="/usr/sbin/haproxy"
readonly HAPROXY_CFG="/etc/haproxy/haproxy.cfg"

# ---------------------------------------------------------------------------
# VIP check — only VIP owner runs issuance
# ---------------------------------------------------------------------------
if ip -4 -o addr show | awk "{print \$4}" | grep -Eq "${VIP_IP}(/|$)"; then
  : # MASTER (VIP owner)
else
  echo "Not VIP owner (${VIP_IP}). Skipping issuance."
  exit 0
fi

# ---------------------------------------------------------------------------
# Domain list — SINGLE SOURCE OF TRUTH
#
# Add new domains here. Everything else (CNAME, crt-list, allowlist, PEM)
# is auto-provisioned. vault.home.arpa is the default bind cert and is
# excluded from crt-list (loaded directly on the bind line in haproxy.cfg).
# ---------------------------------------------------------------------------
domains=(
  "nextcloud.app.home.arpa"
  "meshtastic.app.home.arpa"
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
  "hubble.mgmt.home.arpa"
  "vault.home.arpa"
  "vault.mgmt.home.arpa"
  "haproxy.mgmt.home.arpa"
)

# Domains excluded from crt-list (loaded as default cert on bind line)
readonly DEFAULT_CERT_DOMAIN="vault.home.arpa"

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

# ---------------------------------------------------------------------------
# Phase 0: Kerberos ticket (reused for all CNAME checks)
# ---------------------------------------------------------------------------
readonly KRB5_CCACHE="$(mktemp -p /run/certbot-dnsupd krb5cc.XXXXXX 2>/dev/null || mktemp /tmp/krb5cc.XXXXXX)"
trap 'rm -f "${KRB5_CCACHE}"' EXIT
export KRB5CCNAME="FILE:${KRB5_CCACHE}"
kinit -kt "${KEYTAB}" "${PRINCIPAL}" >/dev/null

# ---------------------------------------------------------------------------
# Phase 1: Ensure CNAME delegation records exist in FreeIPA
# ---------------------------------------------------------------------------
ensure_cname() {
  local domain="$1"
  local expected_target="${domain}.${ACME_ZONE}."
  local cname

  cname="$(dig +time=2 +tries=1 +short CNAME "_acme-challenge.${domain}." @"${IPA_DNS_SERVER}" || true)"

  if [[ "${cname}" == "${expected_target}" ]]; then
    return 0
  fi

  log "Auto-provisioning CNAME: _acme-challenge.${domain} → ${expected_target}"

  # Extract zone and record name from domain
  # e.g. opnsense.mgmt.home.arpa → zone=mgmt.home.arpa, record=_acme-challenge.opnsense
  # e.g. vault.home.arpa → zone=home.arpa, record=_acme-challenge.vault
  local zone record_name
  case "${domain}" in
    *.*.home.arpa)
      # subdomain.zone.home.arpa (e.g. opnsense.mgmt.home.arpa)
      zone="${domain#*.}"          # mgmt.home.arpa
      record_name="_acme-challenge.${domain%%.*}"  # _acme-challenge.opnsense
      ;;
    *.home.arpa)
      # direct.home.arpa (e.g. vault.home.arpa)
      zone="home.arpa"
      record_name="_acme-challenge.${domain%%.*}"  # _acme-challenge.vault
      ;;
    *)
      warn "Cannot determine zone for ${domain} — skipping CNAME auto-provision"
      return 1
      ;;
  esac

  # Use nsupdate (same Kerberos principal as TXT records) to add CNAME
  # nsupdate can manage CNAMEs in zones the principal has write access to
  if nsupdate -g <<NSU
server ${IPA_DNS_SERVER} 53
zone ${zone}.
update delete _acme-challenge.${domain}. CNAME
update add _acme-challenge.${domain}. 3600 CNAME ${expected_target}
send
NSU
  then
    log "CNAME created: _acme-challenge.${domain} → ${expected_target}"
    # Wait for DNS propagation
    sleep 2
  else
    warn "Failed to create CNAME for ${domain} via nsupdate — manual intervention required"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Phase 2: Issue/renew certificate via Vault ACME + assemble PEM
# ---------------------------------------------------------------------------
issue_and_deploy() {
  local domain="$1"
  local acme_dir
  acme_dir="$(acme_dir_for_domain "${domain}")"

  log "==> Ensuring cert for: ${domain} (via ${acme_dir##*/roles/})"

  if certbot certonly \
    --cert-name "${domain}" \
    --manual \
    --preferred-challenges dns \
    --manual-auth-hook "${AUTH_HOOK}" \
    --manual-cleanup-hook "${CLEAN_HOOK}" \
    --server "${acme_dir}" \
    --key-type rsa --rsa-key-size 2048 \
    --non-interactive \
    --keep-until-expiring \
    -d "${domain}"; then

    # Always ensure PEM bundle exists (handles initial issuance where
    # the renewal-hooks/deploy/ hook does NOT fire)
    assemble_pem "${domain}"
    return 0
  else
    warn "certbot failed for ${domain}"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Assemble PEM bundle for HAProxy (idempotent — skips if already current)
# ---------------------------------------------------------------------------
assemble_pem() {
  local domain="$1"
  local lineage="/etc/letsencrypt/live/${domain}"
  local dest="${CERT_DIR}/${domain}.pem"

  if [[ ! -d "${lineage}" ]]; then
    warn "No certbot lineage found for ${domain} — skipping PEM assembly"
    return 1
  fi

  local src_key="${lineage}/privkey.pem"
  local src_chain="${lineage}/fullchain.pem"

  if [[ ! -r "${src_key}" || ! -r "${src_chain}" ]]; then
    warn "Missing key or chain for ${domain}"
    return 1
  fi

  # Skip if PEM already exists and is current (key+chain haven't changed)
  if [[ -f "${dest}" ]]; then
    local expected
    expected="$(cat "${src_key}" "${src_chain}" | sha256sum | awk '{print $1}')"
    local actual
    actual="$(sha256sum "${dest}" | awk '{print $1}')"
    if [[ "${expected}" == "${actual}" ]]; then
      return 0
    fi
  fi

  install -d -m 0750 -o root -g haproxy "${CERT_DIR}"

  local tmp
  tmp="$(mktemp "${dest}.XXXXXX")"
  cat "${src_key}" "${src_chain}" > "${tmp}"
  chown root:haproxy "${tmp}"
  chmod 0640 "${tmp}"
  mv -f "${tmp}" "${dest}"

  log "PEM assembled: ${dest}"
}

# ---------------------------------------------------------------------------
# Phase 3: Generate crt-list.txt + allowlist.txt from domain list
# ---------------------------------------------------------------------------
generate_haproxy_cert_config() {
  log "Generating crt-list.txt + allowlist.txt from domain list"

  install -d -m 0750 -o root -g haproxy "${SYNC_DIR}"

  # ── crt-list.txt ──
  local crt_tmp
  crt_tmp="$(mktemp "${CRT_LIST}.XXXXXX")"
  cat > "${crt_tmp}" <<'HEADER'
# =============================================================================
# HAProxy crt-list — SNI-based certificate selection
#
# AUTO-GENERATED by vault-acme-issue-all.sh — DO NOT EDIT MANUALLY.
# Add new domains to the domains array in vault-acme-issue-all.sh.
#
# Format: <PEM path> [SNI filter]
#
# The vault.home.arpa.pem is loaded as the default cert on the bind line
# in haproxy.cfg, so it does NOT appear here.
#
# Deployed to: /etc/haproxy/certsync/crt-list.txt
# =============================================================================
HEADER

  for d in "${domains[@]}"; do
    [[ "${d}" == "${DEFAULT_CERT_DOMAIN}" ]] && continue
    printf '/etc/haproxy/certs/%-40s %s\n' "${d}.pem" "${d}" >> "${crt_tmp}"
  done

  chown root:haproxy "${crt_tmp}"
  chmod 0640 "${crt_tmp}"
  mv -f "${crt_tmp}" "${CRT_LIST}"

  # ── allowlist.txt ──
  local allow_tmp
  allow_tmp="$(mktemp "${ALLOWLIST}.XXXXXX")"
  cat > "${allow_tmp}" <<'HEADER'
# =============================================================================
# Allowlist — PEM filenames permitted for rsync to edge-2
#
# AUTO-GENERATED by vault-acme-issue-all.sh — DO NOT EDIT MANUALLY.
# Add new domains to the domains array in vault-acme-issue-all.sh.
#
# Deployed to: /etc/haproxy/certsync/allowlist.txt
# =============================================================================
HEADER

  for d in "${domains[@]}"; do
    echo "${d}.pem" >> "${allow_tmp}"
  done

  chown root:haproxy "${allow_tmp}"
  chmod 0640 "${allow_tmp}"
  mv -f "${allow_tmp}" "${ALLOWLIST}"

  log "Generated crt-list ($(grep -c '\.pem' "${CRT_LIST}") entries) + allowlist ($(grep -c '\.pem' "${ALLOWLIST}") entries)"
}

# ---------------------------------------------------------------------------
# Phase 4: Validate + reload HAProxy
# ---------------------------------------------------------------------------
reload_haproxy() {
  # Pre-flight: check all PEMs referenced in crt-list actually exist
  local missing=0
  while IFS= read -r line; do
    [[ "${line}" =~ ^#.*$ || -z "${line}" ]] && continue
    local pem_path
    pem_path="$(echo "${line}" | awk '{print $1}')"
    if [[ ! -f "${pem_path}" ]]; then
      warn "Missing PEM: ${pem_path} (HAProxy will fail to start)"
      missing=$((missing + 1))
    fi
  done < "${CRT_LIST}"

  if [[ "${missing}" -gt 0 ]]; then
    warn "${missing} PEM(s) missing — skipping HAProxy reload"
    return 1
  fi

  log "Validating HAProxy config..."
  if "${HAPROXY_BIN}" -c -f "${HAPROXY_CFG}" >/dev/null 2>&1; then
    log "HAProxy config valid — reloading"
    systemctl reload haproxy
  else
    warn "HAProxy config INVALID — attempting restart for new crt-list entries"
    if "${HAPROXY_BIN}" -c -f "${HAPROXY_CFG}"; then
      systemctl restart haproxy
    else
      warn "HAProxy config still invalid — manual fix required"
      return 1
    fi
  fi
}

# =============================================================================
# Main orchestration
# =============================================================================
main() {
  log "=== vault-acme-issue-all starting ==="

  local issued=0 failed=0 skipped=0

  for d in "${domains[@]}"; do
    # Phase 1: Ensure CNAME exists
    if ! ensure_cname "${d}"; then
      warn "Skipping ${d} — CNAME provisioning failed"
      failed=$((failed + 1))
      continue
    fi

    # Phase 2: Issue cert + assemble PEM
    if issue_and_deploy "${d}"; then
      issued=$((issued + 1))
    else
      failed=$((failed + 1))
    fi
  done

  # Phase 3: Regenerate crt-list + allowlist
  generate_haproxy_cert_config

  # Phase 4: Validate + reload HAProxy
  reload_haproxy || true

  log "=== vault-acme-issue-all complete: ${issued} ok, ${failed} failed ==="
}

main "$@"