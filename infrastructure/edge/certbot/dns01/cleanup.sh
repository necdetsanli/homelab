#!/usr/bin/env bash
# =============================================================================
# Certbot DNS-01 ACME cleanup hook — FreeIPA nsupdate (GSS-TSIG / Kerberos)
#
# Called by certbot after DNS-01 challenge validation completes (success or fail).
# Removes the TXT record from the delegated acme.home.arpa zone.
#
# Deployed to: /usr/local/lib/certbot-dns01/cleanup.sh
# =============================================================================
set -euo pipefail
umask 077

# Shared constants (IPs, ACME zone, keytab) -- single source of truth
# shellcheck source=../../scripts/edge-env.sh
source /usr/local/lib/edge-env.sh

readonly IPA_DNS_SERVER="${EDGE_IPA_DNS_SERVER}"
readonly ACME_ZONE="${EDGE_ACME_ZONE}."
readonly KEYTAB="${EDGE_KEYTAB}"
readonly PRINCIPAL="${EDGE_PRINCIPAL}"

readonly DOMAIN="${CERTBOT_DOMAIN:?CERTBOT_DOMAIN missing}"
readonly VALIDATION="${CERTBOT_VALIDATION:?CERTBOT_VALIDATION missing}"

record="${DOMAIN}.${ACME_ZONE}"

ccache="$(mktemp -p /run/certbot-dnsupd krb5cc.XXXXXX)"
trap 'rm -f "${ccache}"' EXIT
export KRB5CCNAME="FILE:${ccache}"

kinit -kt "${KEYTAB}" "${PRINCIPAL}" >/dev/null

nsupdate -g <<NSU
server ${IPA_DNS_SERVER} 53
zone ${ACME_ZONE}
update delete ${record} TXT "${VALIDATION}"
send
NSU

exit 0
