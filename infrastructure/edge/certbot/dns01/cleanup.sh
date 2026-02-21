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

readonly IPA_DNS_SERVER="192.168.50.5"
readonly ACME_ZONE="acme.home.arpa."
readonly KEYTAB="/etc/letsencrypt/krb5/certbot-dnsupd.keytab"
readonly PRINCIPAL="certbot-dnsupd/$(hostname -f)@HOME.ARPA"

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
