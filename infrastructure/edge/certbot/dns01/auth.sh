#!/usr/bin/env bash
# =============================================================================
# Certbot DNS-01 ACME auth hook — FreeIPA nsupdate (GSS-TSIG / Kerberos)
#
# Called by certbot during DNS-01 challenge validation.
# Creates a TXT record in the delegated acme.home.arpa zone via nsupdate -g.
#
# CNAME delegation pattern:
#   _acme-challenge.<domain>  CNAME → <domain>.acme.home.arpa.
#
# Prerequisites:
#   - Kerberos keytab: /etc/letsencrypt/krb5/certbot-dnsupd.keytab
#   - IPA service principal: certbot-dnsupd/<hostname>@HOME.ARPA
#   - FreeIPA DNS zone: acme.home.arpa (allows nsupdate from this principal)
#   - CNAME records for each domain in home.arpa zone
#
# Deployed to: /usr/local/lib/certbot-dns01/auth.sh
# =============================================================================
set -euo pipefail
umask 077

readonly IPA_DNS_SERVER="192.168.50.5"
readonly ACME_ZONE="acme.home.arpa."
readonly KEYTAB="/etc/letsencrypt/krb5/certbot-dnsupd.keytab"
readonly PRINCIPAL="certbot-dnsupd/$(hostname -f)@HOME.ARPA"

readonly DOMAIN="${CERTBOT_DOMAIN:?CERTBOT_DOMAIN missing}"
readonly VALIDATION="${CERTBOT_VALIDATION:?CERTBOT_VALIDATION missing}"

# Sanity check: verify CNAME delegation exists for this domain
expected_target="${DOMAIN}.acme.home.arpa."
cname="$(dig +time=2 +tries=1 +short CNAME "_acme-challenge.${DOMAIN}." @"${IPA_DNS_SERVER}" || true)"
if [[ "${cname}" != "${expected_target}" ]]; then
  echo "CNAME mismatch: _acme-challenge.${DOMAIN} -> '${cname}', expected '${expected_target}'" >&2
  exit 2
fi

record="${DOMAIN}.${ACME_ZONE}"   # e.g.: opnsense.mgmt.home.arpa.acme.home.arpa.

ccache="$(mktemp -p /run/certbot-dnsupd krb5cc.XXXXXX)"
trap 'rm -f "${ccache}"' EXIT
export KRB5CCNAME="FILE:${ccache}"

kinit -kt "${KEYTAB}" "${PRINCIPAL}" >/dev/null

nsupdate -g <<NSU
server ${IPA_DNS_SERVER} 53
zone ${ACME_ZONE}
update delete ${record} TXT "${VALIDATION}"
update add ${record} 60 TXT "${VALIDATION}"
send
NSU

# Poll authoritative NS until TXT is visible (max ~20s)
for _ in $(seq 1 20); do
  if dig +time=1 +tries=1 +short TXT "${record}" @"${IPA_DNS_SERVER}" | grep -Fq "\"${VALIDATION}\""; then
    exit 0
  fi
  sleep 1
done

echo "TXT not visible yet on authoritative for ${record}" >&2
exit 1
