#!/usr/bin/env bash
# =============================================================================
# edge-gitops-sync.sh — GitOps config sync for edge nodes
#
# Pulls the homelab repo on a schedule (systemd timer) and deploys changed
# files to system paths with correct ownership/permissions. Each edge node
# pulls independently — no cross-node config push required (certs still sync
# via the existing certsync pipeline).
#
# Workflow:
#   1. git pull (sparse checkout: infrastructure/edge/ only)
#   2. Compare HEAD vs last-deployed commit
#   3. Deploy only changed files to system paths
#   4. Reload affected services (HAProxy, Keepalived, systemd)
#   5. Record deployed commit
#
# Self-updating: the script + its own systemd units are in the manifest,
# so pushing a fix to edge-gitops-sync.sh auto-deploys it next cycle.
#
# Initial bootstrap (one-time, run as root on each edge node):
#   git clone --depth 1 --filter=blob:none --sparse \
#     git@github.com:necdetsanli/homelab.git /var/lib/edge-gitops/homelab
#   cd /var/lib/edge-gitops/homelab && git sparse-checkout set infrastructure/edge
#   cp infrastructure/edge/gitops/edge-gitops-sync.sh /usr/local/sbin/
#   cp infrastructure/edge/gitops/edge-gitops-sync.service /etc/systemd/system/
#   cp infrastructure/edge/gitops/edge-gitops-sync.timer /etc/systemd/system/
#   chmod 0750 /usr/local/sbin/edge-gitops-sync.sh
#   systemctl daemon-reload && systemctl enable --now edge-gitops-sync.timer
#
# Deployed to: /usr/local/sbin/edge-gitops-sync.sh
# =============================================================================
set -euo pipefail
umask 027

readonly LOG_TAG="edge-gitops-sync"
readonly REPO_DIR="/var/lib/edge-gitops/homelab"
readonly STATE_FILE="/var/lib/edge-gitops/last-deployed-commit"
readonly EDGE_DIR="infrastructure/edge"
readonly HOSTNAME="$(hostname -s)"   # edge-1 or edge-2

log()  { logger -t "${LOG_TAG}" "$*"; echo "$*"; }
warn() { logger -t "${LOG_TAG}" -p user.warning "$*"; echo "WARN: $*" >&2; }
fail() { logger -t "${LOG_TAG}" -p user.err "$*"; echo "ERROR: $*" >&2; exit 1; }

# =============================================================================
# File manifest — repo path (relative to infrastructure/edge/) mapped to
# system path, ownership, mode, and service tag for reload decisions.
#
# Format: src|dest|owner:group|mode|service_tag
#
# service_tag groups: haproxy, keepalived, systemd, gitops
# Node-specific files use {HOSTNAME} placeholder.
# =============================================================================
read_manifest() {
  cat <<'MANIFEST'
haproxy/haproxy.cfg|/etc/haproxy/haproxy.cfg|root:haproxy|0640|haproxy
haproxy/certsync/crt-list.txt|/etc/haproxy/certsync/crt-list.txt|root:haproxy|0640|haproxy
haproxy/certsync/allowlist.txt|/etc/haproxy/certsync/allowlist.txt|root:haproxy|0640|haproxy
scripts/vault-acme-issue-all.sh|/usr/local/sbin/vault-acme-issue-all.sh|root:root|0750|none
scripts/haproxy-certs-send|/usr/local/sbin/haproxy-certs-send|root:root|0750|none
scripts/haproxy-certs-recv|/usr/local/sbin/haproxy-certs-recv|root:root|0750|none
certbot/dns01/auth.sh|/usr/local/lib/certbot-dns01/auth.sh|root:root|0750|none
certbot/dns01/cleanup.sh|/usr/local/lib/certbot-dns01/cleanup.sh|root:root|0750|none
certbot/hooks/deploy/50-haproxy-deploy|/etc/letsencrypt/renewal-hooks/deploy/50-haproxy-deploy|root:root|0750|none
certbot/systemd/vault-acme-issue-all.timer|/etc/systemd/system/vault-acme-issue-all.timer|root:root|0644|systemd
certbot/systemd/vault-acme-issue-all.service|/etc/systemd/system/vault-acme-issue-all.service|root:root|0644|systemd
certbot/systemd/vault-acme-issue-all.service.d/20-certsync.conf|/etc/systemd/system/vault-acme-issue-all.service.d/20-certsync.conf|root:root|0644|systemd
keepalived/scripts/keepalived-notify-certsync.sh|/usr/local/sbin/keepalived-notify-certsync.sh|root:root|0750|none
gitops/edge-gitops-sync.sh|/usr/local/sbin/edge-gitops-sync.sh|root:root|0750|gitops
gitops/edge-gitops-sync.service|/etc/systemd/system/edge-gitops-sync.service|root:root|0644|systemd
gitops/edge-gitops-sync.timer|/etc/systemd/system/edge-gitops-sync.timer|root:root|0644|systemd
MANIFEST
}

# Node-specific keepalived config (different source file per hostname)
read_manifest_node_specific() {
  case "${HOSTNAME}" in
    edge-1) echo "keepalived/edge-1-keepalived.conf|/etc/keepalived/keepalived.conf|root:root|0640|keepalived" ;;
    edge-2) echo "keepalived/edge-2-keepalived.conf|/etc/keepalived/keepalived.conf|root:root|0640|keepalived" ;;
    *)      warn "Unknown hostname '${HOSTNAME}' — skipping node-specific keepalived config" ;;
  esac
}

# =============================================================================
# Git operations
# =============================================================================
git_pull() {
  if [[ ! -d "${REPO_DIR}/.git" ]]; then
    fail "Repo not found at ${REPO_DIR}. Run initial bootstrap first (see script header)."
  fi

  cd "${REPO_DIR}"
  git fetch --depth 1 origin main 2>&1 | while read -r line; do log "git: ${line}"; done
  git reset --hard origin/main >/dev/null 2>&1
}

get_head_commit() {
  git -C "${REPO_DIR}" rev-parse HEAD
}

get_last_deployed() {
  if [[ -f "${STATE_FILE}" ]]; then
    cat "${STATE_FILE}"
  else
    echo "none"
  fi
}

save_deployed_commit() {
  local commit="$1"
  install -d -m 0750 "$(dirname "${STATE_FILE}")"
  echo "${commit}" > "${STATE_FILE}"
}

# Returns 0 if file changed between two commits (or if first deploy)
file_changed() {
  local file="$1" old_commit="$2" new_commit="$3"

  # First deployment — everything is "changed"
  if [[ "${old_commit}" == "none" ]]; then
    return 0
  fi

  git -C "${REPO_DIR}" diff --name-only "${old_commit}" "${new_commit}" -- "${file}" | grep -q .
}

# =============================================================================
# Deploy a single file
# =============================================================================
deploy_file() {
  local src="$1" dest="$2" ownership="$3" mode="$4"
  local src_full="${REPO_DIR}/${EDGE_DIR}/${src}"

  if [[ ! -f "${src_full}" ]]; then
    warn "Source file missing in repo: ${src}"
    return 1
  fi

  # Skip if destination content is identical (idempotent)
  if [[ -f "${dest}" ]] && cmp -s "${src_full}" "${dest}"; then
    return 0
  fi

  # Ensure destination directory exists
  local dest_dir
  dest_dir="$(dirname "${dest}")"
  install -d -m 0755 "${dest_dir}"

  # Atomic copy: temp file → rename
  local tmp
  tmp="$(mktemp "${dest}.gitops.XXXXXX")"
  trap "rm -f '${tmp}' 2>/dev/null || true" RETURN

  cp "${src_full}" "${tmp}"
  chown "${ownership}" "${tmp}"
  chmod "${mode}" "${tmp}"
  mv -f "${tmp}" "${dest}"

  log "deployed: ${src} → ${dest}"
  return 0
}

# =============================================================================
# Service reload helpers
# =============================================================================
reload_haproxy() {
  # Pre-flight: check all PEMs referenced in crt-list actually exist
  local crt_list="/etc/haproxy/certsync/crt-list.txt"
  if [[ -f "${crt_list}" ]]; then
    local missing=0
    while IFS= read -r line; do
      [[ "${line}" =~ ^#.*$ || -z "${line}" ]] && continue
      local pem_path
      pem_path="$(echo "${line}" | awk '{print $1}')"
      if [[ ! -f "${pem_path}" ]]; then
        warn "Missing PEM: ${pem_path} — run vault-acme-issue-all.sh to issue"
        missing=$((missing + 1))
      fi
    done < "${crt_list}"
    if [[ "${missing}" -gt 0 ]]; then
      warn "${missing} PEM(s) missing — skipping HAProxy reload (run: sudo /usr/local/sbin/vault-acme-issue-all.sh)"
      return 1
    fi
  fi

  log "Validating HAProxy config..."
  if /usr/sbin/haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null 2>&1; then
    log "HAProxy config valid — reloading"
    systemctl reload haproxy || {
      log "Reload failed — attempting restart for new crt-list entries"
      systemctl restart haproxy
    }
  else
    warn "HAProxy config INVALID — skipping reload (manual fix required)"
    /usr/sbin/haproxy -c -f /etc/haproxy/haproxy.cfg 2>&1 | while read -r line; do
      warn "haproxy -c: ${line}"
    done
    return 1
  fi
}

reload_keepalived() {
  log "Reloading Keepalived"
  systemctl reload keepalived
}

reload_systemd() {
  log "Reloading systemd daemon"
  systemctl daemon-reload
}

# =============================================================================
# Main
# =============================================================================
main() {
  log "=== edge-gitops-sync starting on ${HOSTNAME} ==="

  local old_commit new_commit
  old_commit="$(get_last_deployed)"

  git_pull
  new_commit="$(get_head_commit)"

  if [[ "${old_commit}" == "${new_commit}" ]]; then
    log "Already at ${new_commit:0:8} — nothing to deploy"
    exit 0
  fi

  log "Deploying: ${old_commit:0:8} → ${new_commit:0:8}"

  # Track which service groups need reloading
  local need_haproxy=false
  local need_keepalived=false
  local need_systemd=false
  local deployed_count=0
  local failed_count=0

  # Process shared manifest
  while IFS='|' read -r src dest ownership mode tag; do
    [[ -z "${src}" || "${src}" == \#* ]] && continue

    if file_changed "${EDGE_DIR}/${src}" "${old_commit}" "${new_commit}"; then
      if deploy_file "${src}" "${dest}" "${ownership}" "${mode}"; then
        deployed_count=$((deployed_count + 1))
        case "${tag}" in
          haproxy)    need_haproxy=true ;;
          keepalived) need_keepalived=true ;;
          systemd)    need_systemd=true ;;
          gitops)     need_systemd=true ;;
        esac
      else
        failed_count=$((failed_count + 1))
      fi
    fi
  done < <(read_manifest; read_manifest_node_specific)

  log "Deployed ${deployed_count} file(s), ${failed_count} failed"

  # ── Service reloads (order matters: systemd first, then services) ──
  if "${need_systemd}"; then
    reload_systemd
  fi

  if "${need_haproxy}"; then
    reload_haproxy || true
  fi

  if "${need_keepalived}"; then
    reload_keepalived || true
  fi

  # ── Sync config + certs to edge-2 (VIP owner only) ──
  # Uses haproxy-certs-send which handles allowlist enforcement, SSH transport,
  # and syncs both certsync config files and PEM bundles to edge-2.
  if "${need_haproxy}" && [[ -x /usr/local/sbin/haproxy-certs-send ]]; then
    local vip_ip="192.168.20.22"
    if ip -4 -o addr show | awk '{print $4}' | grep -Eq "${vip_ip}(/|$)"; then
      log "VIP owner — syncing to peer via haproxy-certs-send"
      /usr/local/sbin/haproxy-certs-send || warn "certsync send failed (peer will pick up on next ACME run)"
    fi
  fi

  # ── Record successful deployment ──
  save_deployed_commit "${new_commit}"
  log "=== edge-gitops-sync complete: ${new_commit:0:8} ==="
}

main "$@"
