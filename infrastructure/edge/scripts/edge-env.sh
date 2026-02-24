#!/usr/bin/env bash
# =============================================================================
# edge-env.sh -- Shared constants for all edge-tier scripts
# =============================================================================
# Source this file instead of hardcoding IPs in individual scripts.
# Canonical reference: infrastructure/config/addresses.env
#
# Usage:  source /usr/local/lib/edge-env.sh
# Deployed to: /usr/local/lib/edge-env.sh   (via edge-gitops-sync)
# =============================================================================

# Keepalived VIP (HAProxy frontend)
readonly EDGE_VIP_IP="192.168.20.22"

# FreeIPA DNS server (nsupdate target for ACME challenges)
readonly EDGE_IPA_DNS_SERVER="192.168.50.5"

# ACME / certbot
readonly EDGE_ACME_ZONE="acme.home.arpa"
readonly EDGE_KEYTAB="/etc/letsencrypt/krb5/certbot-dnsupd.keytab"
readonly EDGE_PRINCIPAL="certbot-dnsupd/$(hostname -f)@HOME.ARPA"
